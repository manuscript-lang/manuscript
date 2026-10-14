package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func methodSymbol(m *checker.Method) *checker.Symbol {
	return &checker.Symbol{ID: m.ID, Module: m.Module, Decl: m.Decl, Type: m.Type}
}

func (g *generator) nativeMethodCall(e *syntax.Expression, _ []syntax.Argument) ast.Expr {
	x := g.ir.Expression(e).Call
	if x.Method == nil || !x.Native {
		return nil
	}
	m := g.nativeMethods[x.Method.ID]
	s := methodSymbol(m)
	if g.wantScalar == 0 && !g.shareNativeBody(s) {
		return nil
	}
	receiver := sourceAt(x.Receiver.Source.Pos, g.expression(x.Receiver.Source))
	values := []ast.Expr{ident("ctx"), receiver}
	bySlot := make([]ast.Expr, len(x.Parameters))
	var captures []ast.Stmt
	if !x.Ordered {
		name := g.temp()
		captures = append(captures, define(name, receiver))
		values[1] = ident(name)
	}
	for _, a := range x.Arguments {
		value := sourceAt(a.Pos, g.callArgument(a))
		if !x.Ordered {
			name := g.temp()
			captures = append(captures, define(name, value))
			value = ident(name)
		}
		bySlot[a.Slot] = value
	}
	values = append(values, bySlot...)
	for _, p := range x.Parameters {
		if p.Omittable {
			values = append(values, ident("true"))
		}
	}
	if x.Ordered {
		return g.locatedOperation(e, ident(m.ID+"Native"), values...)
	}
	captures = append(captures, assign(ident("sourcePosition"), token.ASSIGN, textLiteral(e.Pos.String())), returned(call(ident(m.ID+"Native"), values...)))
	return call(closure(nil, nativeResultType(m.Type.Result), captures...))
}
