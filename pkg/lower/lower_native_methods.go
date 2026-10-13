package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (g *generator) selectNativeMethods() {
	g.nativeMethods = map[string]*checker.Method{}
	for _, m := range g.program.Methods {
		if m.Native == "" && len(m.Variables) == 0 && !hasTypeVariable(m.Receiver) && !hasTypeVariable(m.Type) {
			g.nativeMethods[m.ID] = m
		}
	}
}
func methodSymbol(m *checker.Method) *checker.Symbol {
	return &checker.Symbol{ID: m.ID, Module: m.Module, Decl: m.Decl, Type: m.Type}
}
func (g *generator) nativeMethodAvailable(e *syntax.Expression) bool {
	if e.Kind != syntax.KindCall || e.Left.Kind != syntax.KindMember {
		return false
	}
	info := g.program.Expressions[e.Left]
	if info == nil || info.Method == nil || g.nativeMethods[info.Method.ID] == nil {
		return false
	}
	receiver := g.program.Expressions[e.Left.Left].Type
	if receiver.Kind == "contract" || hasTypeVariable(receiver) {
		return false
	}
	args := e.Args
	if converted := g.program.Expressions[e].Arguments; converted != nil {
		args = converted
	}
	// Omitted inherited interface defaults retain their existing preparation.
	return len(args) == len(info.Method.Type.Params)
}
func (g *generator) nativeMethodCall(e *syntax.Expression, args []syntax.Argument) ast.Expr {
	if !g.nativeMethodAvailable(e) {
		return nil
	}
	m := g.nativeMethods[g.program.Expressions[e.Left].Method.ID]
	s := methodSymbol(m)
	if g.wantScalar == 0 && !g.shareNativeBody(s) {
		return nil
	}
	ordered := true
	for i, a := range args {
		ordered = ordered && a.Name == m.Type.Params[i].Name
	}
	receiver := sourceAt(e.Left.Left.Pos, g.expression(e.Left.Left))
	var captures []ast.Stmt
	values := []ast.Expr{ident("ctx"), receiver}
	if ordered {
		for i, a := range args {
			var value ast.Expr
			if primitiveEqualityType(m.Type.Params[i].Type) != "" {
				value = g.scalarValueAs(a.Value, m.Type.Params[i].Type)
			} else {
				value = g.argumentValue(a)
			}
			values = append(values, sourceAt(a.Pos, value))
		}
	} else {
		name := g.temp()
		captures = append(captures, define(name, receiver))
		values[1] = ident(name)
		byName := map[string]ast.Expr{}
		for _, a := range args {
			var t *checker.Type
			for _, p := range m.Type.Params {
				if p.Name == a.Name {
					t = p.Type
				}
			}
			var value ast.Expr
			if primitiveEqualityType(t) != "" {
				value = g.scalarValueAs(a.Value, t)
			} else {
				value = g.argumentValue(a)
			}
			name := g.temp()
			captures = append(captures, define(name, sourceAt(a.Pos, value)))
			byName[a.Name] = ident(name)
		}
		for _, p := range m.Type.Params {
			values = append(values, byName[p.Name])
		}
	}
	for i := range m.Type.Params {
		if nativeDefault(s, i) {
			values = append(values, ident("true"))
		}
	}
	if ordered {
		return g.locatedOperation(e, ident(m.ID+"Native"), values...)
	}
	captures = append(captures, assign(ident("sourcePosition"), token.ASSIGN, textLiteral(e.Pos.String())), returned(call(ident(m.ID+"Native"), values...)))
	return call(closure(nil, nativeResultType(m.Type.Result), captures...))
}
