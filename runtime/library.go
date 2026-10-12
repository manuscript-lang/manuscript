package msruntime

// LibrarySpec is the shared source of truth for checker and native bindings.
// Function identities include their module to avoid collisions such as parse/join.
type LibraryParam struct{ Name, Type string }
type LibrarySpec struct {
	Module, Name, Result string
	Params               []LibraryParam
	Variables            []LibraryParam // name and compiler bound (empty means unconstrained)
	Body                 func(*Execution, string, []Value) Value
}

var Library []LibrarySpec
var libraryFunctions = map[string]LibrarySpec{}

func libraryAdd(module, name, result string, params []LibraryParam, body func(*Execution, string, []Value) Value) {
	spec := LibrarySpec{Module: module, Name: name, Result: result, Params: params, Body: body}
	Library = append(Library, spec)
	libraryFunctions[module+"/"+name] = spec
}
func libraryGeneric(module, name, result string, variables, params []LibraryParam, body func(*Execution, string, []Value) Value) {
	libraryAdd(module, name, result, params, body)
	Library[len(Library)-1].Variables = variables
	libraryFunctions[module+"/"+name] = Library[len(Library)-1]
}
func libraryFunction(name, result string) (Value, bool) {
	spec, ok := libraryFunctions[name]
	if !ok {
		return nil, false
	}
	labels := make([]string, len(spec.Params))
	for i, p := range spec.Params {
		labels[i] = p.Name
	}
	return NewFunction(labels, result, func(ctx *Execution, args []Value) Value { return spec.Body(ctx, result, args) }), true
}
func libraryOK(result string, value Value) Value { return Alternative{result, "ok", []Value{value}} }
func libraryError(result, code, message string) Value {
	// Messages are diagnostics, codes are stable and intentionally shared across packages.
	return Alternative{result, "error", []Value{Alternative{"@std/LibraryError", code, func() []Value {
		if code == "Failed" {
			return []Value{message}
		}
		return nil
	}()}}}
}
func libraryResult(typ string) string             { return "Result[" + typ + "][LibraryError]" }
func libraryList(typ string, values []Value) List { return List{"@std/List[" + typ + "]", values} }
func libraryStrings(values []string) List {
	items := make([]Value, len(values))
	for i, s := range values {
		items[i] = s
	}
	return libraryList("String", items)
}
func libraryStringValues(v Value) []string {
	items := v.(List).Items
	out := make([]string, len(items))
	for i, x := range items {
		out[i] = x.(string)
	}
	return out
}
func libraryBound(result string, n int64) Value {
	if n < 0 {
		return libraryError(result, "InvalidInput", "")
	}
	return nil
}
func librarySlice(length int, start, end int64) {
	if start < 0 || end < start || end > int64(length) {
		Panic("invalid half-open slice bounds")
	}
}
