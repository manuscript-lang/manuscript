package msruntime

import (
	"strings"

	"github.com/manuscript-lang/manuscript/internal/nativeabi"
)

// NativeLibraryBindings maps receiver declarations directly to native implementations.
// The first native parameter is bound to the receiver; remaining labels are unchanged.
var NativeLibraryBindings = nativeabi.ReceiverBindings

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
	var receiverType string
	switch v := receiver.(type) {
	case Record:
		if v.Type != "@std/HttpRequest" {
			return nil, false
		}
		kind = "HttpRequest"
	case *TaskGroup:
		kind = "TaskGroup"
	case *Task:
		kind, receiverType = "Task", v.typ
	case Duration:
		kind = "Duration"
	case Instant:
		kind = "Instant"
	case libraryTimestamp:
		kind = "Timestamp"
	case Alternative:
		native, _, _ := strings.Cut(v.Type, "[")
		switch native {
		case "@std/Optional":
			kind = "Optional"
		case "@std/Result":
			kind = "Result"
		case "@std/HashAlgorithm":
			kind = "HashAlgorithm"
		case "@std/CompressionFormat":
			kind = "CompressionFormat"
		case "@std/ArchiveFormat":
			kind = "ArchiveFormat"
		case "@std/NormalizationForm":
			kind = "NormalizationForm"
		default:
			return nil, false
		}
		receiverType = v.Type
	case *List:
		kind = "List"
		receiverType = v.Type
	case *Map:
		kind = "Map"
		receiverType = v.Type
	case *Set:
		kind = "Set"
		receiverType = v.Type
	case libraryBigInt:
		kind = "BigInt"
	case *libraryRandom:
		kind = "Random"
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
	case Decimal:
		kind = "Decimal"
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
		for i, arg := range typeArguments(receiverType) {
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
		args := make([]Value, len(a)+1)
		args[0] = receiver
		copy(args[1:], a)
		return invokeLibrary(spec, ctx, result, args)
	}), true
}
