package msruntime

import "github.com/manuscript-lang/manuscript/internal/nativeabi"

// NativeLibraryBindings maps receiver operations to the shared function implementation.
// The first function parameter is bound to the receiver; remaining labels are unchanged.
var NativeLibraryBindings = nativeabi.ReceiverFunctions

func NativeLibrarySpec(receiver, name string) (LibrarySpec, bool) {
	function, ok := NativeLibraryBindings[receiver][name]
	if !ok {
		return LibrarySpec{}, false
	}
	spec, ok := libraryFunctions[function]
	return spec, ok
}

func nativeLibraryMember(receiver Value, name, result string) (Value, bool) {
	var kind string
	var args []string
	switch v := receiver.(type) {
	case Alternative:
		native, types := splitType(v.Type)
		if native != "@std/Optional" {
			return nil, false
		}
		kind, args = "Optional", types
	case *List:
		kind = "List"
		args = typeArguments(v.Type)
	case *Map:
		kind = "Map"
		args = typeArguments(v.Type)
	case *Set:
		kind = "Set"
		args = typeArguments(v.Type)
	case libraryBigInt:
		kind = "BigInt"
	case libraryRegex:
		kind = "Regex"
	case Bytes:
		kind = "Bytes"
	case string:
		kind = "String"
	case int64:
		kind = "Int"
	case float64:
		kind = "Float"
	default:
		return nil, false
	}
	spec, ok := NativeLibrarySpec(kind, name)
	if !ok {
		return nil, false
	}
	if result == "" {
		// Bind receiver variables for runtime callers of nongeneric operations.
		variables := map[string]string{}
		for i, arg := range args {
			if i < len(spec.Variables) {
				variables["@std/"+spec.Variables[i].Name] = arg
			}
		}
		result = ResolveType(libraryRuntimeType(spec.Result), variables)
	}
	labels := make([]string, len(spec.Params)-1)
	for i, p := range spec.Params[1:] {
		labels[i] = p.Name
	}
	return NewFunction(labels, result, func(ctx *Execution, a []Value) Value {
		return invokeLibrary(spec, ctx, result, append([]Value{receiver}, a...))
	}), true
}
