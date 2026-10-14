package lower

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (g *generator) nativeReceiverMember(member *syntax.Expression, info *checker.Info) ast.Expr {
	return g.nativeReceiver(g.expression(member.Left), member.Text, g.program.Info(member.Left).Type, info)
}

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
func (g *generator) directCollectionCall(e *syntax.Expression, arguments []syntax.Argument) ast.Expr {
	callee := g.program.Info(e.Left)
	if e.Left.Kind != syntax.KindMember || callee == nil || callee.Method == nil || callee.Method.Contract != nil {
		return nil
	}
	switch callee.Method.Native {
	case "collections/at":
		if len(arguments) == 1 {
			receiver, index := g.listAtOperands(e, arguments)
			return g.locatedOperation(e, runtimeName("ListAt"), ident("ctx"), receiver, index, g.key(g.program.Info(e).Type))
		}
	case "length":
		// Collection length reads the receiver's size; it never calls back or fails.
		switch g.program.Info(e.Left.Left).Type.ID {
		case "@std/List", "@std/Map", "@std/Set":
			if len(arguments) == 0 {
				return g.locatedOperation(e, runtimeName("CollectionLength"), ident("ctx"), g.expression(e.Left.Left))
			}
		}
	case "append":
		if len(arguments) == 1 && g.program.Info(e.Left.Left).Type.ID == "@std/List" {
			receiver := sourceAt(e.Left.Left.Pos, g.expression(e.Left.Left))
			return g.locatedOperation(e, runtimeName("ListAppend"), ident("ctx"), receiver, g.argumentValue(arguments[0]))
		}
	case "is_empty", "collections/is_empty":
		if len(arguments) == 0 && g.program.Info(e.Left.Left).Type.ID == "@std/List" {
			return g.locatedOperation(e, runtimeName("ListIsEmpty"), ident("ctx"), g.expression(e.Left.Left))
		}
	case "collections/contains", "contains", "get", "with_entry", "with_value", "collections/set_add", "collections/set_remove", "collections/map_add", "collections/map_remove":
		return g.directKeyedCall(e, callee.Method.Native, arguments)
	case "string/at":
		if len(arguments) == 1 && g.program.Info(e.Left.Left).Type.ID == "String" {
			receiver := sourceAt(e.Left.Left.Pos, g.expression(e.Left.Left))
			return g.locatedOperation(e, runtimeName("StringAt"), ident("ctx"), receiver, g.argumentValue(arguments[0]), g.key(g.program.Info(e).Type))
		}
	case "byte_length":
		if len(arguments) == 0 && g.program.Info(e.Left.Left).Type.ID == "String" {
			return g.locatedOperation(e, runtimeName("StringByteLength"), ident("ctx"), g.expression(e.Left.Left))
		}
	case "optional/unwrap":
		if len(arguments) == 0 {
			return g.locatedOperation(e, runtimeName("OptionalUnwrap"), ident("ctx"), g.expression(e.Left.Left))
		}
	}
	return nil
}

// directKeyedCall lowers membership and keyed access on built-in List, Map,
// and Set receivers. The element or key scope travels as data, replacing the
// per-call Execution copy of a bound native member.
func (g *generator) directKeyedCall(e *syntax.Expression, native string, arguments []syntax.Argument) ast.Expr {
	receiverType := g.program.Info(e.Left.Left).Type
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
	args := []ast.Expr{ident("ctx"), sourceAt(e.Left.Left.Pos, g.expression(e.Left.Left))}
	for _, argument := range arguments {
		// Reuse checked conversions and capture each value before a later
		// argument can mutate an earlier local, just as ordinary calls do.
		args = append(args, sourceAt(argument.Pos, g.argumentValue(argument)))
	}
	args = append(args, g.typeScope(receiverType.Args[0]))
	if name == "MapGet" {
		args = append(args, g.key(g.program.Info(e).Type))
	}
	return g.locatedOperation(e, runtimeName(name), args...)
}

// listAtOperands lowers the receiver and index of a List.at call.
func (g *generator) listAtOperands(e *syntax.Expression, arguments []syntax.Argument) (ast.Expr, ast.Expr) {
	// Force even a plain local receiver to be read before the index:
	// a match expression in the index can reassign that local. Go does
	// not otherwise order a variable read before a later function call.
	return sourceAt(e.Left.Left.Pos, g.expression(e.Left.Left)), g.argumentValue(arguments[0])
}

// listAtMatch reports whether value is a direct List.at call, whose Optional
// result a match can consume as an element and a presence flag.
func (g *generator) listAtMatch(value *syntax.Expression) bool {
	if value.Kind != syntax.KindCall {
		return false
	}
	info := g.program.Info(value)
	arguments := value.Args
	if info.Arguments != nil {
		arguments = info.Arguments
	}
	callee := g.program.Info(value.Left)
	return value.Left.Kind == syntax.KindMember && callee != nil && callee.Method != nil && callee.Method.Contract == nil && callee.Method.Native == "collections/at" && len(arguments) == 1
}

// listAtParts lowers a List.at call to the element and its presence.
func (g *generator) listAtParts(value *syntax.Expression) ast.Expr {
	arguments := value.Args
	if info := g.program.Info(value); info.Arguments != nil {
		arguments = info.Arguments
	}
	receiver, index := g.listAtOperands(value, arguments)
	return g.locatedOperation(value, runtimeName("ListAtParts"), ident("ctx"), receiver, index)
}
