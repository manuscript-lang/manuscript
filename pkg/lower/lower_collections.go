package lower

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// nativeReceiver binds a native method to an already lowered receiver.
func (g *generator) nativeReceiver(receiver ast.Expr, name string, receiverType *checker.Type, info *checker.Info) ast.Expr {
	args := []ast.Expr{receiver, textLiteral(name), g.key(info.Type.Result), g.typeScope(receiverType)}
	if info.Method.Native == "collections/set_map" || info.Method.Native == "collections/map_transform_keys" {
		// Output deduplication needs the mapped key/element's lexical evidence,
		// including when a generic receiver method is explicitly specialized.
		args = append(args, g.typeScope(info.Type.Result))
	}
	return runtimeCall("NativeMemberResult", args...)
}

// These checked native operations neither invoke callbacks nor acquire
// resources. Direct calls can share their runtime implementation without
// constructing a bound Function, resolving labels, or changing Optional storage.
// References to bound methods still use ordinary callable dispatch.
func (g *generator) directCollectionCall(x ir.Call) ast.Expr {
	m, ok := calleeMember(x)
	if !ok || m.Info.Method == nil || m.Info.Method.Contract != nil {
		return nil
	}
	arguments := x.Args
	switch m.Info.Method.Native {
	case "collections/at":
		if len(arguments) == 1 {
			receiver, index := g.listAtOperands(m, arguments)
			return locatedAt(x.Pos, runtimeName("ListAt"), ident("ctx"), receiver, index, g.key(x.Info.Type))
		}
	case "length":
		// Collection length reads the receiver's size; it never calls back or fails.
		switch m.ReceiverType.ID {
		case "@std/List", "@std/Map", "@std/Set":
			if len(arguments) == 0 {
				return locatedAt(x.Pos, runtimeName("CollectionLength"), ident("ctx"), g.irValue(m.Receiver))
			}
		}
	case "append":
		if len(arguments) == 1 && m.ReceiverType.ID == "@std/List" {
			receiver := sourceAt(m.ReceiverPos, g.irValue(m.Receiver))
			return locatedAt(x.Pos, runtimeName("ListAppend"), ident("ctx"), receiver, g.argumentValue(arguments[0]))
		}
	case "is_empty", "collections/is_empty":
		if len(arguments) == 0 && m.ReceiverType.ID == "@std/List" {
			return locatedAt(x.Pos, runtimeName("ListIsEmpty"), ident("ctx"), g.irValue(m.Receiver))
		}
	case "collections/contains", "contains", "get", "with_entry", "with_value", "collections/set_add", "collections/set_remove", "collections/map_add", "collections/map_remove":
		return g.directKeyedCall(x, m)
	case "string/at":
		if len(arguments) == 1 && m.ReceiverType.ID == "String" {
			receiver := sourceAt(m.ReceiverPos, g.irValue(m.Receiver))
			return locatedAt(x.Pos, runtimeName("StringAt"), ident("ctx"), receiver, g.argumentValue(arguments[0]), g.key(x.Info.Type))
		}
	case "byte_length":
		if len(arguments) == 0 && m.ReceiverType.ID == "String" {
			return locatedAt(x.Pos, runtimeName("StringByteLength"), ident("ctx"), g.irValue(m.Receiver))
		}
	case "optional/unwrap":
		if len(arguments) == 0 {
			return locatedAt(x.Pos, runtimeName("OptionalUnwrap"), ident("ctx"), g.irValue(m.Receiver))
		}
	}
	return nil
}

// directKeyedCall lowers membership and keyed access on built-in List, Map,
// and Set receivers. The element or key scope travels as data, replacing the
// per-call Execution copy of a bound native member.
func (g *generator) directKeyedCall(x ir.Call, m ir.Member) ast.Expr {
	native, arguments, receiverType := m.Info.Method.Native, x.Args, m.ReceiverType
	if len(receiverType.Args) == 0 {
		return nil
	}
	name, count := "", len(arguments)
	switch receiverType.ID + "/" + native {
	case "@std/List/collections/contains":
		name = "ListContains"
	case "@std/Map/contains":
		name = "MapContains"
	case "@std/Map/get":
		name = "MapGet"
	case "@std/Map/with_entry", "@std/Map/collections/map_add":
		name = "MapWithEntry"
	case "@std/Map/collections/map_remove":
		name = "MapRemove"
	case "@std/Set/contains":
		name = "SetContains"
	case "@std/Set/with_value", "@std/Set/collections/set_add":
		name = "SetWithValue"
	case "@std/Set/collections/set_remove":
		name = "SetRemove"
	default:
		return nil
	}
	if want := map[string]int{"MapWithEntry": 2}[name]; (want == 0 && count != 1) || (want != 0 && count != want) {
		return nil
	}
	if name == "MapWithEntry" && (arguments[0].Name == "value" || arguments[1].Name == "key") {
		return nil
	}
	// Read the receiver before the arguments, as for List.at.
	args := []ast.Expr{ident("ctx"), sourceAt(m.ReceiverPos, g.irValue(m.Receiver))}
	for _, argument := range arguments {
		// Reuse checked conversions and capture each value before a later
		// argument can mutate an earlier local, just as ordinary calls do.
		args = append(args, sourceAt(argument.Pos, g.argumentValue(argument)))
	}
	args = append(args, g.typeScope(receiverType.Args[0]))
	if name == "MapGet" {
		args = append(args, g.key(x.Info.Type))
	}
	return locatedAt(x.Pos, runtimeName(name), args...)
}

// listAtOperands lowers the receiver and index of a List.at call.
func (g *generator) listAtOperands(m ir.Member, arguments []ir.Argument) (ast.Expr, ast.Expr) {
	// Force even a plain local receiver to be read before the index:
	// a match expression in the index can reassign that local. Go does
	// not otherwise order a variable read before a later function call.
	return sourceAt(m.ReceiverPos, g.irValue(m.Receiver)), g.argumentValue(arguments[0])
}

// listAt returns the call when value is a direct List.at call, whose Optional
// result a match can consume as an element and a presence flag.
func (g *generator) listAt(value *syntax.Expression) (ir.Call, bool) {
	x, ok := g.ir.Operand(value).(ir.Call)
	if !ok {
		return x, false
	}
	m, ok := calleeMember(x)
	return x, ok && m.Info.Method != nil && m.Info.Method.Contract == nil && m.Info.Method.Native == "collections/at" && len(x.Args) == 1
}

// listAtParts lowers a List.at call to the element and its presence.
func (g *generator) listAtParts(x ir.Call) ast.Expr {
	m, _ := calleeMember(x)
	receiver, index := g.listAtOperands(m, x.Args)
	return locatedAt(x.Pos, runtimeName("ListAtParts"), ident("ctx"), receiver, index)
}
