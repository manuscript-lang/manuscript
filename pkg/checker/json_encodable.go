package checker

import "strings"

// JsonEncodable is a structural bound like Equal and Hashable: a type satisfies
// it when its shape has a JSON form. It has no operations and cannot be
// implemented, so the check and stringify's encoder agree by construction.

func (c *checker) jsonEncodable(t *Type) bool { return c.jsonRejection(t, map[string]bool{}) == "" }

// jsonRejection returns why t has no JSON form, or "" when it does. The reason
// names the path to the offending field so the writer can fix the type.
func (c *checker) jsonRejection(t *Type, seen map[string]bool) string {
	if t == nil || t.ID == "<invalid>" {
		return ""
	}
	name := t.String()
	switch {
	case t.Kind == "variable":
		for _, b := range t.Bounds {
			if std(b, "JsonEncodable") {
				return ""
			}
		}
		return "type parameter " + name + " needs the bound " + name + ": JsonEncodable"
	case t.Kind == "function":
		return "functions cannot be encoded"
	case t.Kind == "primitive":
		if t.ID == "Bool" || t.ID == "Int" || t.ID == "Float" || t.ID == "String" {
			return ""
		}
		return name + " has no JSON form"
	case std(t, "JsonValue") || std(t, "Decimal") || std(t, "BigInt"):
		return ""
	case std(t, "Optional"):
		if len(t.Args) == 1 && std(t.Args[0], "Optional") {
			return "nested Optional is ambiguous because none and some(none) would both encode as null; flatten it to one Optional"
		}
		return c.jsonArguments(t, seen)
	case std(t, "List"), std(t, "Set"):
		return c.jsonArguments(t, seen)
	case std(t, "Map"):
		if len(t.Args) == 2 && !(t.Args[0].Kind == "primitive" && t.Args[0].ID == "String") {
			return "map keys must be String to become JSON member names, but this key is " + t.Args[0].String()
		}
		return c.jsonArguments(t, seen)
	case t.Kind == "contract":
		return name + " is an interface, so its values have no known shape; use the concrete type"
	case strings.HasPrefix(t.ID, "@std/"):
		return name + " is a standard-library type with no JSON form; copy the fields you need into your own record or JsonValue"
	case t.Def == nil || t.Kind != "record" && t.Kind != "alternative":
		return name + " has no JSON form"
	}
	key := typeKey(t)
	if seen[key] {
		return ""
	}
	seen[key] = true
	for _, f := range Fields(t) {
		if reason := c.jsonRejection(f.Type, seen); reason != "" {
			return "field " + f.Name + " of " + name + ": " + reason
		}
	}
	for _, cs := range Cases(t) {
		for _, f := range cs.Fields {
			if reason := c.jsonRejection(f.Type, seen); reason != "" {
				return "field " + f.Name + " of " + name + "." + cs.Name + ": " + reason
			}
		}
	}
	return ""
}

func (c *checker) jsonArguments(t *Type, seen map[string]bool) string {
	for _, a := range t.Args {
		if reason := c.jsonRejection(a, seen); reason != "" {
			return t.String() + ": " + reason
		}
	}
	return ""
}
