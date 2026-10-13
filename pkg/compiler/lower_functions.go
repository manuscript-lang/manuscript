package compiler

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func recordDefaults(d *syntax.Declaration) bool {
	if d == nil || d.Kind != syntax.KindRecord {
		return false
	}
	for _, f := range d.Fields {
		if f.Default != nil {
			return true
		}
	}
	return false
}
func (g *generator) declaredFunction(s *checker.Symbol) ast.Expr {
	d := s.Decl
	if d.Kind == syntax.KindFn {
		return g.function(d.Name, d.Params, d.Result, d.Body, g.program.Parameters[d], nil, s.Type)
	}
	var args []ast.Expr
	for i, field := range d.Fields {
		args = append(args, composite(runtimeName("Argument"), keyed("Name", textLiteral(field.Name)), keyed("Value", ident(g.program.Parameters[d][i].ID))))
	}
	t := checker.ConstructorSignature(s.Type)
	return g.function(d.Name, d.Fields, &syntax.Type{Pos: d.Pos}, nil, g.program.Parameters[d], nil, t,
		returned(runtimeCall("ConstructWithContext", ident("ctx"), g.key(s.Type), sliceLiteral(runtimeName("Argument"), args...))))
}
func (g *generator) function(name string, params []syntax.Parameter, result *syntax.Type, body []*syntax.Statement, bindings []*checker.Binding, self *checker.Binding, t *checker.Type, tail ...ast.Stmt) ast.Expr {
	oldCleanups, oldLoops, oldLabels, oldDepth, oldResult := g.cleanups, g.loopCleanup, g.loopLabels, g.expressionDepth, g.resultKey
	oldNeedsCleanup := g.needsCleanup
	g.resultKey = g.key(t.Result)
	g.expressionDepth = 0
	g.cleanups = nil
	g.needsCleanup = false
	g.loopCleanup = nil
	g.loopLabels = nil
	defer func() {
		g.cleanups = oldCleanups
		g.needsCleanup = oldNeedsCleanup
		g.loopCleanup = oldLoops
		g.loopLabels = oldLabels
		g.expressionDepth = oldDepth
		g.resultKey = oldResult
	}()
	var labels []string
	for _, p := range t.Params {
		labels = append(labels, p.Name)
	}
	prologue := []ast.Stmt{
		define("sourcePosition", textLiteral(result.Pos.String())),
		&ast.DeferStmt{Call: runtimeCall("TraceSource", address(ident("sourcePosition")), textLiteral(name))},
	}
	var out []ast.Stmt
	if self != nil {
		out = append(out, define(self.ID, ident("receiver")), discard(ident(self.ID)))
	}
	for i, b := range bindings {
		out = append(out, define(b.ID, index(ident("args"), intLiteral(i))), discard(ident(b.ID)))
		// Checked source values are concrete (including Unit and Optional.none);
		// Invoke leaves nil only for an omitted argument.
		if params[i].Default == nil && t.Defaults[t.Params[i].Name] && b.Type.ID == "@std/Optional" {
			out = append(out, &ast.IfStmt{Cond: &ast.BinaryExpr{X: ident(b.ID), Op: token.EQL, Y: ident("nil")}, Body: block(assign(ident(b.ID), token.ASSIGN, runtimeCall("NewAlternative", g.key(b.Type), textLiteral("none"), ident("nil"), ident("nil"))))})
		}
		if params[i].Default != nil {
			stmt := &ast.IfStmt{Cond: &ast.BinaryExpr{X: ident(b.ID), Op: token.EQL, Y: ident("nil")}, Body: block(assign(ident(b.ID), token.ASSIGN, g.expression(params[i].Default)))}
			out = append(out, g.locatedStatement(params[i].Default.Pos, stmt))
		}
	}
	out = append(out, g.body(body)...)
	out = append(out, tail...)
	// Defaults and generated match closures belong to this callable; nested
	// source functions save their own flag. Lexical cleanup lists are empty again
	// after lowering each scope, so their final length cannot prove absence.
	if g.needsCleanup {
		prologue = append(prologue, define("cleanupStack", runtimeCall("NewCleanupStack")), &ast.DeferStmt{Call: call(selector(ident("cleanupStack"), "Unwind"))})
	}
	out = append(prologue, out...)
	out = append(out, g.locatedStatement(syntax.Position{File: "manuscript.generated.go", Line: 1}, returned(unit())))
	return runtimeCall("NewSourceFunction", stringSlice(labels), g.key(t.Result), textLiteral(result.Pos.String()), closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"), out...))
}
