package debugger

import (
	"reflect"
	"strconv"
	"strings"

	"github.com/go-delve/delve/service/api"
)

// sourceValue is a bounded inspection view, not a target mutation handle.
type sourceValue struct {
	Name        string        `json:"name"`
	Type        string        `json:"type"`
	Value       string        `json:"value"`
	Children    []sourceValue `json:"children,omitempty"`
	Truncated   bool          `json:"truncated,omitempty"`
	Unavailable string        `json:"unavailable,omitempty"`
	Key         *sourceValue  `json:"key,omitempty"` // maps retain key load state independently of the display name
}

var valueLoad = api.LoadConfig{FollowPointers: true, MaxVariableRecurse: 6, MaxStringLen: 512, MaxArrayValues: 32, MaxStructFields: -1}

func unwrap(value api.Variable) api.Variable {
	for depth := 0; depth < 8 && (value.Kind == reflect.Interface || value.Kind == reflect.Ptr) && len(value.Children) == 1; depth++ {
		value = value.Children[0]
	}
	return value
}

func field(value api.Variable, name string) (api.Variable, bool) {
	for _, child := range value.Children {
		if child.Name == name {
			return child, true
		}
	}
	return api.Variable{}, false
}

// Runtime type keys use repeated bracketed arguments; keep the editor's source
// spelling, including nested generic types, without parsing a prettyprint string.
func runtimeType(key string) string {
	at := 0
	var parse func() string
	parse = func() string {
		start := at
		for at < len(key) && !strings.ContainsRune("[]&", rune(key[at])) {
			at++
		}
		name := strings.TrimPrefix(key[start:at], "@std/")
		if strings.HasPrefix(name, "module/") {
			_, name, _ = strings.Cut(name, "#")
		}
		args := []string{}
		for at < len(key) && key[at] == '[' {
			at++
			args = append(args, parse())
			if at < len(key) && key[at] == ']' {
				at++
			}
		}
		if len(args) > 0 {
			name += "[" + strings.Join(args, ", ") + "]"
		}
		return name
	}
	return parse()
}

func renderValue(variable api.Variable, name, declared string, depth int, recordTypes map[string]string) sourceValue {
	v := unwrap(variable)
	r := sourceValue{Name: name, Type: declared}
	if variable.Unreadable != "" || v.Unreadable != "" {
		r.Unavailable = v.Unreadable
		if r.Unavailable == "" {
			r.Unavailable = variable.Unreadable
		}
		r.Value = "<unavailable>"
		return r
	}
	if (v.Kind == reflect.Interface || v.Kind == reflect.Ptr) && len(v.Children) == 0 {
		r.Value, r.Unavailable = "<unavailable>", "native value was not loaded"
		return r
	}
	// Delve reports signed DWARF integers as Kind Int even for Go int64.
	// Use the concrete native type, like the VS Code adapter, for primitives.
	primitive := map[string]string{"int64": "Int", "uint8": "Int", "float64": "Float", "bool": "Bool", "string": "String"}[v.Type]
	if v.Type == "" {
		primitive = map[reflect.Kind]string{reflect.Int64: "Int", reflect.Uint8: "Int", reflect.Float64: "Float", reflect.Bool: "Bool", reflect.String: "String"}[v.Kind]
	}
	if primitive != "" {
		// Like the editor, do not mislabel recycled dead container slots.
		if isContainer(declared) {
			r.Value, r.Unavailable = "<unavailable after last use>", "native slot no longer contains the declared container"
			return r
		}
		r.Type, r.Value = primitive, v.Value
		if v.Kind == reflect.String {
			r.Value = strconv.Quote(v.Value)
			r.Truncated = int64(len(v.Value)) < v.Len
		}
		return r
	}
	if t, ok := field(v, "Type"); ok && t.Value != "" {
		r.Type = runtimeType(t.Value)
		if isContainer(declared) && strings.Split(r.Type, "[")[0] != strings.Split(declared, "[")[0] {
			r.Type, r.Value, r.Unavailable = declared, "<unavailable after last use>", "native slot no longer contains the declared container"
			return r
		}
	}
	kind := v.Type[strings.LastIndex(v.Type, ".")+1:]
	if r.Type == "" {
		r.Type = recordTypes[kind]
	}
	if r.Type == "" {
		r.Type = kind
	}
	r.Value = r.Type
	if kind == "Unit" {
		r.Type, r.Value = "Unit", "unit"
		return r
	}
	if depth >= 3 {
		r.Truncated = true
		return r
	}
	children := []api.Variable{}
	r.Truncated = v.Len > int64(len(v.Children))
	switch {
	case strings.HasPrefix(kind, "record_"):
		for _, c := range v.Children {
			if strings.HasPrefix(c.Name, "f_") {
				c.Name = strings.TrimPrefix(c.Name, "f_")
				children = append(children, c)
			}
		}
	case kind == "Alternative":
		if tag, ok := field(v, "Tag"); ok {
			r.Value = tag.Value
		}
		if fields, ok := field(v, "Fields"); ok {
			children = fields.Children
			for i := range children {
				children[i].Name = strconv.Itoa(i)
			}
			r.Truncated = int64(len(children)) < fields.Len
		} else {
			r.Truncated = true
		}
	case kind == "Record":
		if tag, ok := field(v, "Tag"); ok {
			r.Value = tag.Value
		}
		if fields, ok := field(v, "Fields"); ok {
			for i := 0; i+1 < len(fields.Children); i += 2 {
				c := fields.Children[i+1]
				c.Name = fields.Children[i].Value
				children = append(children, c)
			}
			r.Truncated = int64(len(fields.Children)/2) < fields.Len
		} else {
			r.Truncated = true
		}
	case kind == "List" || kind == "Set" || kind == "Bytes":
		if items, ok := field(v, "Items"); ok {
			r.Value = r.Type + " (" + strconv.FormatInt(items.Len, 10) + " items)"
			children = items.Children
			for i := range children {
				children[i].Name = strconv.Itoa(i)
			}
			r.Truncated = int64(len(children)) < items.Len
		} else {
			r.Truncated = true
		}
	case kind == "Map":
		if entries, ok := field(v, "Entries"); ok {
			r.Value = r.Type + " (" + strconv.FormatInt(entries.Len, 10) + " items)"
			for _, entry := range entries.Children {
				keyVariable, keyOK := field(entry, "Key")
				c, valueOK := field(entry, "Value")
				if !keyOK || !valueOK || entry.Unreadable != "" {
					r.Truncated = true
					continue
				}
				key := renderValue(keyVariable, "", "", depth+1, recordTypes)
				c.Name = key.Value
				value := renderValue(c, c.Name, "", depth+1, recordTypes)
				value.Key = &key
				r.Children = append(r.Children, value)
				r.Truncated = r.Truncated || key.Truncated || key.Unavailable != ""
			}
			r.Truncated = r.Truncated || int64(len(r.Children)) < entries.Len
		} else {
			r.Truncated = true
		}
	}
	for _, c := range children {
		r.Children = append(r.Children, renderValue(c, c.Name, "", depth+1, recordTypes))
	}
	return r
}

func isContainer(t string) bool {
	for _, kind := range []string{"List", "Set", "Map", "Bytes", "Optional", "Result"} {
		if t == kind || strings.HasPrefix(t, kind+"[") {
			return true
		}
	}
	return false
}
