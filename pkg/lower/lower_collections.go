package lower

import (
	"go/ast"
	"go/token"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (g *generator) nativeReceiverMember(member *syntax.Expression, info *checker.Info) ast.Expr {
	args := []ast.Expr{g.expression(member.Left), textLiteral(member.Text), g.key(info.Type.Result), g.typeScope(g.program.Info(member.Left).Type)}
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
			return orderedCall(runtimeName("ListAt"), ident("ctx"), receiver, index, g.key(g.program.Info(e).Type))
		}
	case "length":
		// Collection length reads the receiver's size; it never calls back or fails.
		switch g.program.Info(e.Left.Left).Type.ID {
		case "@std/List", "@std/Map", "@std/Set":
			if len(arguments) == 0 {
				return orderedCall(runtimeName("CollectionLength"), ident("ctx"), g.expression(e.Left.Left))
			}
		}
	case "append":
		if len(arguments) == 1 && g.program.Info(e.Left.Left).Type.ID == "@std/List" {
			receiver := sequence(g.expression(e.Left.Left))
			if typ := primitiveEqualityType(g.program.Info(e.Left.Left).Type.Args[0]); typ != "" {
				return orderedCall(runtimeName("ListAppend"+primitiveKinds[typ]), ident("ctx"), receiver, g.scalar(arguments[0].Value, typ))
			}
			return orderedCall(runtimeName("ListAppend"), ident("ctx"), receiver, g.argumentValue(arguments[0]))
		}
		if len(arguments) == 1 && g.program.Info(e.Left.Left).Type.ID == "@std/StringBuilder" {
			receiver := sequence(g.expression(e.Left.Left))
			return orderedCall(runtimeName("StringBuilderAppend"), ident("ctx"), receiver, g.argumentValue(arguments[0]))
		}
	case "freeze":
		if len(arguments) == 0 && g.program.Info(e.Left.Left).Type.ID == "@std/StringBuilder" {
			return orderedCall(runtimeName("StringBuilderFreeze"), ident("ctx"), g.expression(e.Left.Left))
		}
	case "is_empty", "collections/is_empty":
		if len(arguments) == 0 && g.program.Info(e.Left.Left).Type.ID == "@std/List" {
			return orderedCall(runtimeName("ListIsEmpty"), ident("ctx"), g.expression(e.Left.Left))
		}
	case "collections/contains", "contains", "get", "collections/set_add", "collections/set_remove", "collections/map_add", "collections/map_remove":
		return g.directKeyedCall(e, callee.Method.Native, arguments)
	case "string/at":
		if len(arguments) == 1 && g.program.Info(e.Left.Left).Type.ID == "String" {
			receiver := sequence(g.expression(e.Left.Left))
			return orderedCall(runtimeName("StringAt"), ident("ctx"), receiver, g.argumentValue(arguments[0]), g.key(g.program.Info(e).Type))
		}
	case "string/length":
		if len(arguments) == 0 && g.program.Info(e.Left.Left).Type.ID == "String" {
			return orderedCall(runtimeName("StringLength"), ident("ctx"), sequence(g.expression(e.Left.Left)))
		}
	case "byte_length":
		if len(arguments) == 0 && g.program.Info(e.Left.Left).Type.ID == "String" {
			return orderedCall(runtimeName("StringByteLength"), ident("ctx"), g.expression(e.Left.Left))
		}
	case "optional/is_some", "optional/is_none":
		if len(arguments) == 0 && g.program.Info(e.Left.Left).Type.ID == "@std/Optional" {
			some := orderedCall(runtimeName("OptionalIsSome"), ident("ctx"), g.expression(e.Left.Left))
			if callee.Method.Native == "optional/is_none" {
				return &ast.UnaryExpr{Op: token.NOT, X: some}
			}
			return some
		}
	case "optional/unwrap_or":
		if len(arguments) == 1 && g.program.Info(e.Left.Left).Type.ID == "@std/Optional" {
			receiver := sequence(g.expression(e.Left.Left))
			return orderedCall(runtimeName("OptionalUnwrapOr"), ident("ctx"), receiver, g.argumentValue(arguments[0]))
		}
	case "optional/unwrap":
		if len(arguments) == 0 && g.listAtMatch(e.Left.Left) {
			// list.at(i).unwrap() needs no Optional: read the element and fault
			// at the unwrap site when it is absent.
			receiver, index := g.listAtOperands(e.Left.Left, g.program.Info(e.Left.Left).Arguments)
			return orderedCall(runtimeName("ListAtUnwrap"), ident("ctx"), receiver, index)
		}
		if len(arguments) == 0 {
			return orderedCall(runtimeName("OptionalUnwrap"), ident("ctx"), g.expression(e.Left.Left))
		}
	}
	return g.boundNativeCall(e, callee, arguments)
}

// nativeKinds are the receiver types whose library members bind per call site.
// Their runtime values map to the kind of the same name in the library table.
var nativeKinds = map[string]struct{ kind, module string }{
	"String":        {"String", "string/"},
	"@std/Bytes":    {"Bytes", "bytes/"},
	"@std/Optional": {"Optional", "optional/"},
	"@std/List":     {"List", "collections/"},
	"@std/Map":      {"Map", "collections/"},
	"@std/Set":      {"Set", "collections/"},
}

// boundNativeCall lowers a call of a library member on a receiver of fixed
// kind with every argument supplied in order. The member, result type and
// equality scope are static, so a hoisted NativeCall replaces the bound
// Function and Argument slice that ordinary dispatch builds per call.
func (g *generator) boundNativeCall(e *syntax.Expression, callee *checker.Info, arguments []syntax.Argument) ast.Expr {
	receiverType := g.program.Info(e.Left.Left).Type
	native, ok := nativeKinds[receiverType.ID]
	name := e.Left.Text
	joinsList := receiverType.ID == "@std/List" && callee.Method.Native == "string/join"
	if !ok || callee.Type == nil || !(strings.HasPrefix(callee.Method.Native, native.module) || joinsList) || name == "equals" || name == "hash" || name == "clone" || name == "toString" {
		return nil
	}
	kind := native.kind
	if len(arguments) > len(callee.Type.Params) {
		return nil
	}
	for i, argument := range arguments {
		if argument.Name != callee.Type.Params[i].Name {
			return nil
		}
	}
	// Trailing parameters declared "= none" reach the body as nil, exactly as
	// they do through Invoke; any other default needs its prepared expression.
	decl := callee.Method.Decl
	for i := len(arguments); i < len(callee.Type.Params); i++ {
		if decl == nil || len(decl.Params) != len(callee.Type.Params) || !isNoneDefault(decl.Params[i].Default) {
			return nil
		}
	}
	if hasTypeVariable(receiverType) || hasTypeVariable(callee.Type.Result) {
		return nil
	}
	bind := []ast.Expr{textLiteral(kind), textLiteral(name), textLiteral(callee.Method.Native), g.key(callee.Type.Result), g.typeScope(receiverType)}
	identity := g.module + "\x00native call\x00" + kind + "." + name + "\x00" + checker.TypeKey(receiverType) + "\x00" + checker.TypeKey(callee.Type.Result)
	if callee.Method.Native == "collections/set_map" || callee.Method.Native == "collections/map_transform_keys" {
		bind = append(bind, g.typeScope(callee.Type.Result))
	}
	// Read the receiver before the arguments, as ordinary dispatch does, and
	// capture each value before a later argument can mutate an earlier local.
	values := []ast.Expr{sequence(g.expression(e.Left.Left))}
	for _, argument := range arguments {
		values = append(values, sequence(g.argumentValue(argument)))
	}
	for i := len(arguments); i < len(callee.Type.Params); i++ {
		values = append(values, call(runtimeName("Value"), ident("nil")))
	}
	return orderedCall(runtimeName("CallNative"), ident("ctx"), g.lazyValue(identity, runtimeCall("BindNativeCall", bind...)), sliceLiteral(runtimeName("Value"), values...))
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
	case "@std/Map/collections/map_add":
		name = "MapWithEntry"
	case "@std/Map/collections/map_remove":
		name = "MapRemove"
	case "@std/Set/contains":
		name = "SetContains"
	case "@std/Set/collections/set_add":
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
	if name == "MapWithEntry" && primitiveEqualityType(receiverType.Args[0]) == "int64" {
		receiver := sequence(g.expression(e.Left.Left))
		key := sequence(g.scalar(arguments[0].Value, "int64"))
		return orderedCall(runtimeName("MapWithEntryInt"), ident("ctx"), receiver, key, sequence(g.argumentValue(arguments[1])))
	}
	// Read the receiver before the arguments, as for List.at.
	args := []ast.Expr{ident("ctx"), sequence(g.expression(e.Left.Left))}
	for _, argument := range arguments {
		// Reuse checked conversions and capture each value before a later
		// argument can mutate an earlier local, just as ordinary calls do.
		args = append(args, sequence(g.argumentValue(argument)))
	}
	args = append(args, g.typeScope(receiverType.Args[0]))
	if name == "MapGet" {
		args = append(args, g.key(g.program.Info(e).Type))
	}
	return orderedCall(runtimeName(name), args...)
}

// listAtOperands lowers the receiver and index of a List.at call.
func (g *generator) listAtOperands(e *syntax.Expression, arguments []syntax.Argument) (ast.Expr, ast.Expr) {
	// Force even a plain local receiver to be read before the index:
	// a match expression in the index can reassign that local. Go does
	// not otherwise order a variable read before a later function call.
	return sequence(g.expression(e.Left.Left)), g.argumentValue(arguments[0])
}

// listAtMatch reports whether value is a direct List.at call, whose Optional
// result a match can consume as an element and a presence flag.
func (g *generator) listAtMatch(value *syntax.Expression) bool {
	if value.Kind != syntax.KindCall {
		return false
	}
	arguments := g.program.Info(value).Arguments
	callee := g.program.Info(value.Left)
	return value.Left.Kind == syntax.KindMember && callee != nil && callee.Method != nil && callee.Method.Contract == nil && callee.Method.Native == "collections/at" && len(arguments) == 1
}

// listAtParts lowers a List.at call to the element and its presence.
func (g *generator) listAtParts(value *syntax.Expression) ast.Expr {
	receiver, index := g.listAtOperands(value, g.program.Info(value).Arguments)
	return orderedCall(runtimeName("ListAtParts"), ident("ctx"), receiver, index)
}

// mapGetMatch reports whether value is a direct Map.get call, whose Optional
// result a match can consume as a value and a presence flag.
func (g *generator) mapGetMatch(value *syntax.Expression) bool {
	if value.Kind != syntax.KindCall || value.Left.Kind != syntax.KindMember {
		return false
	}
	callee := g.program.Info(value.Left)
	if callee == nil || callee.Method == nil || callee.Method.Contract != nil || callee.Method.Native != "get" || len(g.program.Info(value).Arguments) != 1 {
		return false
	}
	receiver := g.program.Info(value.Left.Left)
	return receiver != nil && receiver.Type != nil && receiver.Type.ID == "@std/Map" && len(receiver.Type.Args) > 0
}

// mapGetParts lowers a Map.get call to the value and its presence.
func (g *generator) mapGetParts(value *syntax.Expression) ast.Expr {
	argument := g.program.Info(value).Arguments[0]
	receiver := sequence(g.expression(value.Left.Left))
	if keyType := g.program.Info(value.Left.Left).Type.Args[0]; primitiveEqualityType(keyType) == "int64" {
		return orderedCall(runtimeName("MapGetPartsInt"), ident("ctx"), receiver, sequence(g.scalar(argument.Value, "int64")))
	}
	key := sequence(g.argumentValue(argument))
	return orderedCall(runtimeName("MapGetParts"), ident("ctx"), receiver, key, g.typeScope(g.program.Info(value.Left.Left).Type.Args[0]))
}

// optionalParts reports whether value is a direct lookup a match consumes as
// an element and a presence flag instead of an Optional.
func (g *generator) optionalParts(value *syntax.Expression) bool {
	return g.listAtMatch(value) || g.mapGetMatch(value)
}

// lookupParts lowers an optionalParts lookup to its element and presence.
func (g *generator) lookupParts(value *syntax.Expression) ast.Expr {
	if g.listAtMatch(value) {
		return g.listAtParts(value)
	}
	return g.mapGetParts(value)
}

func isNoneDefault(e *syntax.Expression) bool {
	return e != nil && e.Kind == syntax.KindName && e.Text == "none"
}
