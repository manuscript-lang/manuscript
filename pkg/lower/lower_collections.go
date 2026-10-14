package lower

import (
	"go/ast"

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
func (g *generator) directCollectionCall(e *syntax.Expression, _ []syntax.Argument) ast.Expr {
	x := g.ir.Expression(e).Call
	if x.Collection == "" {
		return nil
	}
	receiver := func() ast.Expr { return sourceAt(x.Receiver.Source.Pos, g.expression(x.Receiver.Source)) }
	switch x.Collection {
	case "ListAt":
		if value := g.typedListAt(e); value != nil {
			return call(selector(value, "Box"), g.key(g.ir.Expression(e).Type))
		}
		return g.locatedOperation(e, runtimeName("ListAt"), ident("ctx"), receiver(), g.edgeValue(x.Arguments[0].Value), g.key(g.ir.Expression(e).Type))
	case "ListAppend":
		if x.ListSuffix != "" {
			return g.locatedOperation(e, runtimeName("ListAppend"+x.ListSuffix), ident("ctx"), receiver(), g.scalarEdge(x.Arguments[0].Value))
		}
		return g.locatedOperation(e, runtimeName("ListAppend"), ident("ctx"), receiver(), g.edgeValue(x.Arguments[0].Value))
	case "CollectionLengthInt", "ListIsEmpty", "StringByteLength":
		return g.locatedOperation(e, runtimeName(x.Collection), ident("ctx"), g.expression(x.Receiver.Source))
	case "StringAt":
		return g.locatedOperation(e, runtimeName("StringAt"), ident("ctx"), receiver(), g.edgeValue(x.Arguments[0].Value), g.key(g.ir.Expression(e).Type))
	case "OptionalUnwrap":
		if x.UnwrapAt != nil {
			return call(selector(sourceAt(e.Pos, g.typedListAt(x.UnwrapAt)), "Unwrap"), ident("ctx"))
		}
		return g.locatedOperation(e, runtimeName("OptionalUnwrap"), ident("ctx"), g.expression(x.Receiver.Source))
	}
	args := []ast.Expr{ident("ctx"), receiver()}
	for _, a := range x.Arguments {
		args = append(args, sourceAt(a.Pos, g.edgeValue(a.Value)))
	}
	args = append(args, g.typeScope(x.Receiver.Type.Args[0]))
	if x.Collection == "MapGet" {
		args = append(args, g.key(g.ir.Expression(e).Type))
	}
	return g.locatedOperation(e, runtimeName(x.Collection), args...)
}
