package ir

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strings"
)

func (p *Program) resolveCall(e *syntax.Expression) *Call {
	info := p.checked.Info(e)
	x := &Call{Symbol: info.Symbol, TypeArgs: info.TypeArgs, Ordered: true}
	args := e.Args
	if info.Arguments != nil {
		args = info.Arguments
	}
	var signature *checker.Type
	var defaults []syntax.Parameter
	if info.Symbol != nil {
		signature = info.Symbol.Type
		defaults = info.Symbol.Decl.Params
	}
	if e.Left.Kind == syntax.KindMember {
		callee := p.checked.Info(e.Left)
		if callee != nil {
			x.Method = callee.Method
		}
		if x.Method != nil {
			x.Receiver = Use(p.checked, e.Left.Left, nil)
		}
		if x.Method != nil {
			signature = x.Method.Type
			defaults = x.Method.Decl.Params
		}
	}
	if info.Constructor != nil {
		signature = checker.ConstructorSignature(info.Constructor)
		if info.Case != "" {
			for _, cs := range checker.Cases(info.Constructor) {
				if cs.Name == info.Case {
					signature = &checker.Type{Kind: "function", Params: cs.Fields, Result: info.Type}
				}
			}
		}
	}
	if callee := p.checked.Info(e.Left); callee != nil && callee.Type != nil && callee.Type.Kind == "function" {
		signature = callee.Type
	}
	if info.Constructor != nil && info.Case == "" && info.Constructor.Def != nil && info.Constructor.Def.Symbol != nil {
		defaults = info.Constructor.Def.Symbol.Decl.Fields
	}
	if signature != nil {
		for i, param := range signature.Params {
			v := Parameter{Name: param.Name, Type: param.Type, Omittable: signature.Defaults[param.Name]}
			if i < len(defaults) {
				v.Default = defaults[i].Default
				v.Omittable = v.Omittable || v.Default != nil
			}
			x.Parameters = append(x.Parameters, v)
		}
	}
	previous := -1
	for _, arg := range args {
		v := Argument{Name: arg.Name, Pos: arg.Pos, Slot: -1}
		var expected *checker.Type
		for slot := range x.Parameters {
			param := &x.Parameters[slot]
			if param.Name == arg.Name {
				v.Slot = slot
				param.Supplied = true
				expected = param.Type
				break
			}
		}
		v.Value = Use(p.checked, arg.Value, expected)
		x.Ordered = x.Ordered && v.Slot > previous
		previous = v.Slot
		x.Arguments = append(x.Arguments, v)
	}
	x.Native = p.nativeCallAvailable(e) || p.nativeMethodAvailable(e)
	x.Numeric = p.numericCallName(e)
	if x.Method != nil && x.Method.Contract == nil {
		t := x.Receiver.Type
		x.ListSuffix = ListSuffix(t)
		count := len(args)
		switch x.Method.Native {
		case "collections/at":
			if count == 1 {
				x.Collection = "ListAt"
			}
		case "append":
			if count == 1 && t.ID == "@std/List" {
				x.Collection = "ListAppend"
			}
		case "length":
			if count == 0 && (t.ID == "@std/List" || t.ID == "@std/Map" || t.ID == "@std/Set") {
				x.Collection = "CollectionLengthInt"
			}
		case "is_empty", "collections/is_empty":
			if count == 0 && t.ID == "@std/List" {
				x.Collection = "ListIsEmpty"
			}
		case "string/at":
			if count == 1 && t.ID == "String" {
				x.Collection = "StringAt"
			}
		case "byte_length":
			if count == 0 && t.ID == "String" {
				x.Collection = "StringByteLength"
			}
		case "optional/unwrap":
			if count == 0 {
				x.Collection = "OptionalUnwrap"
				if p.typedListAtSuffix(e.Left.Left) != "" {
					x.UnwrapAt = e.Left.Left
				}
			}
		default:
			if len(t.Args) != 0 {
				x.Collection = map[string]string{
					"@std/List/collections/contains": "ListContains", "@std/Map/contains": "MapContains", "@std/Map/get": "MapGet",
					"@std/Map/with_entry": "MapWithEntry", "@std/Map/collections/map_add": "MapWithEntry", "@std/Map/collections/map_remove": "MapRemove",
					"@std/Set/contains": "SetContains", "@std/Set/with_value": "SetWithValue", "@std/Set/collections/set_add": "SetWithValue", "@std/Set/collections/set_remove": "SetRemove",
				}[t.ID+"/"+x.Method.Native]
				want := 1
				if x.Collection == "MapWithEntry" {
					want = 2
				}
				if count != want || x.Collection == "MapWithEntry" && (args[0].Name == "value" || args[1].Name == "key") {
					x.Collection = ""
				}
			}
		}
	}
	if x.Symbol != nil {
		s := x.Symbol
		x.Prepared = s.Native == "" && len(s.Variables) == 0 && s.Decl != nil && s.Decl.Kind == syntax.KindFn
	} else if x.Method != nil {
		m, t := x.Method, x.Receiver.Type
		x.Prepared = m.Contract != nil && m.Native == "" && (t.Kind == syntax.KindRecord || t.Kind == "alternative") && len(t.Args) == 0 && !hasTypeVariable(t) && !strings.HasPrefix(t.ID, "@std/")
	}
	x.Prepared = x.Prepared && len(args) == len(x.Parameters) && x.Ordered
	if info.Constructor != nil && info.Native != "view" && info.Case == "" {
		if r := p.Records[checker.TypeKey(info.Constructor)]; r != nil && len(x.Arguments) == len(r.Fields) {
			seen := map[string]bool{}
			valid := true
			for _, a := range x.Arguments {
				valid = valid && r.Field(a.Name) != nil && !seen[a.Name]
				seen[a.Name] = true
			}
			if valid {
				x.Record = r
			}
		}
	}
	return x
}
