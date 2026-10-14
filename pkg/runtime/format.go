package msruntime

import (
	"sort"
	"strconv"
	"strings"
)

func Text(values ...Value) Value {
	var text strings.Builder
	for _, v := range values {
		text.WriteString(Format(v))
	}
	return text.String()
}

// FormatInt, FormatFloat and FormatBool are Format for a value of known type.
func FormatInt(value int64) string     { return strconv.FormatInt(value, 10) }
func FormatFloat(value float64) string { return formatFloat(value) }
func FormatBool(value bool) string     { return strconv.FormatBool(value) }

func Format(value Value) string {
	return formatValue(value, 0)
}

// Opaque resources are deliberately not inspected or invoked while formatting.
// The depth limit also makes cyclic values supplied by native adapters printable.
func formatValue(value Value, depth int) string {
	if depth >= 64 {
		return "..."
	}
	items := func(values []Value) string {
		parts := make([]string, len(values))
		for i, value := range values {
			parts[i] = formatValue(value, depth+1)
		}
		return strings.Join(parts, ", ")
	}
	switch v := value.(type) {
	case string:
		return v
	case int64:
		return strconv.FormatInt(v, 10)
	case float64:
		return formatFloat(v)
	case bool:
		return strconv.FormatBool(v)
	case Unit:
		return "unit"
	case Decimal:
		return v.String()
	case Struct:
		return formatValue(structRecord(v), depth)
	case Record:
		fields := fieldsSnapshot(v.Fields)
		names := make([]string, 0, len(fields))
		for name := range fields {
			names = append(names, name)
		}
		sort.Strings(names)
		parts := make([]string, len(names))
		for i, name := range names {
			parts[i] = name + ": " + formatValue(fields[name], depth+1)
		}
		return displayType(v.Type) + "(" + strings.Join(parts, ", ") + ")"
	case Alternative:
		text := displayType(v.Type) + "." + v.Tag
		if len(v.Fields) > 0 {
			text += "(" + items(v.Fields) + ")"
		}
		return text
	case *List:
		return "[" + items(v.Boxed()) + "]"
	case *Map:
		parts := make([]string, len(v.Entries))
		for i, entry := range v.Entries {
			parts[i] = formatValue(entry.Key, depth+1) + ": " + formatValue(entry.Value, depth+1)
		}
		return "Map(" + strings.Join(parts, ", ") + ")"
	case *Set:
		return "Set(" + items(v.Items) + ")"
	case Bytes:
		parts := make([]string, len(v.Items))
		for i, b := range v.Items {
			parts[i] = strconv.Itoa(int(b))
		}
		return "Bytes(" + strings.Join(parts, ", ") + ")"
	case View:
		return formatValue(v.Receiver, depth+1)
	case Function, Generic:
		return "[function]"
	case Duration:
		return strconv.FormatInt(int64(v), 10) + "ns"
	case Instant:
		return "Instant(" + strconv.FormatInt(v.Tick, 10) + ")"
	case OperationId:
		return "OperationId(" + strconv.FormatUint(v.number, 10) + ")"
	case libraryBigInt:
		return v.n.String()
	case libraryTimestamp:
		return v.t.UTC().Format("2006-01-02T15:04:05.999999999Z07:00")
	case libraryRegex:
		return v.pattern.String()
	case libraryIPAddress:
		return v.address.String()
	case libraryCidr:
		return v.prefix.String()
	}
	return "[object]"
}

func displayType(key string) string {
	name, _ := splitType(key)
	if at := strings.LastIndexAny(name, "/#"); at >= 0 {
		name = name[at+1:]
	}
	return name
}
