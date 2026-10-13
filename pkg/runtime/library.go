package msruntime

import (
	"fmt"
	"strings"
)

// LibrarySpec describes native calling conventions; integration tests compare
// them with the authoritative checked Manuscript declarations.
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
	original := body
	adaptOptions := nativeParamsNeedOptions(params)
	body = func(ctx *Execution, result string, args []Value) Value {
		// Ordinary native calls already have their ordered argument slots.
		// Only adapters (or direct callers with missing slots) need a copy.
		if !adaptOptions && len(args) >= len(params) {
			return original(ctx, result, args)
		}
		normalized, ok := nativeOptions(name, params, args)
		if !ok {
			return nativeOptionFailure(result, name, params, args)
		}
		return original(ctx, result, normalized)
	}
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
	body := func(ctx *Execution, args []Value) Value { return invokeLibrary(spec, ctx, result, args) }
	if spec.Module == "log" && spec.Name == "file_transport" {
		return NewAcquisition(labels, result, body, libraryDisposeResource), true
	}
	return NewFunction(labels, result, body), true
}

// Callback traversals snapshot membership so callbacks can safely update the
// original collection. Elements themselves retain their ordinary references.
func invokeLibrary(spec LibrarySpec, ctx *Execution, result string, args []Value) Value {
	if spec.Module == "collections" {
		switch spec.Name {
		case "map", "filter", "fold", "fold_right", "find", "find_last", "find_index", "find_last_index", "some", "every", "for_each", "flat_map", "group_by", "map_for_each", "set_for_each", "map_filter", "set_filter", "set_map":
			args = append([]Value{}, args...)
			args[0] = Clone(args[0])
		}
	}
	return spec.Body(ctx, result, args)
}
func libraryOK(result string, value Value) Value { return Alternative{result, "ok", []Value{value}} }
func libraryError(result, code, message string) Value {
	var fields []Value
	if code == "Failed" {
		fields = []Value{message}
	}
	return libraryErrorFields(result, code, fields)
}
func libraryErrorFields(result, code string, fields []Value) Value {
	// The error identity comes from the declared Result, including nested success types.
	start := strings.LastIndex(result, "][")
	if start < 0 || !strings.HasSuffix(result, "]") {
		return Panic("invalid native library Result type")
	}
	errorType := result[start+2 : len(result)-1]
	return Alternative{result, "error", []Value{Alternative{errorType, code, fields}}}
}
func libraryResult(typ, errorType string) string { return "Result[" + typ + "][" + errorType + "]" }
func libraryList(typ string, values []Value) *List {
	return &List{Type: "@std/List[" + typ + "]", Items: values}
}
func libraryStrings(values []string) *List {
	items := make([]Value, len(values))
	for i, s := range values {
		items[i] = s
	}
	return libraryList("String", items)
}
func libraryStringValues(v Value) []string {
	items := v.(*List).Items
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
func librarySlice(operation string, length int, start, end int64) {
	if start < 0 || end < start || end > int64(length) {
		Panic(fmt.Sprintf("%s: start/end must satisfy 0 <= start <= end <= %d; found start %d and end %d", operation, length, start, end))
	}
}

// Faults retain the supplied argument, before relative-index or option normalization.
func libraryRangeFault(operation, parameter string, value Value, minimum, maximum int64) Value {
	if option, ok := value.(Alternative); ok && option.Tag == "some" && strings.HasPrefix(option.Type, "@std/Optional[") {
		value = option.Fields[0]
	}
	return Panic(fmt.Sprintf("%s: %s must be between %d and %d, found %s", operation, parameter, minimum, maximum, Format(value)))
}

func libraryIndexFault(operation string, length int, index int64) Value {
	if length == 0 {
		return Panic(fmt.Sprintf("%s: index has no valid value for an empty collection, found %d", operation, index))
	}
	return Panic(fmt.Sprintf("%s: index must be between %d and %d (negative indexes count from the end), found %d", operation, -length, length-1, index))
}

func libraryDisposeResource(ctx *Execution, value Value) {
	if result, ok := value.(Alternative); ok {
		if result.Tag != "ok" {
			return
		}
		value = result.Fields[0]
	}
	Invoke(Shield(ctx), Bind(value, "", "close"), nil)
}

// Native allocation ceilings apply even when a caller supplies no limit or a
// larger one, so a huge count returns LimitExceeded instead of exhausting
// memory or reaching a Go allocation panic.
const (
	nativeMaxItems = 1 << 28
	nativeMaxBytes = 1 << 30
)
