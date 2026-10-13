package compiler

import (
	"go/ast"
	"go/token"
	"strconv"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (g *generator) body(body []*syntax.Statement) []ast.Stmt {
	var out []ast.Stmt
	for _, s := range body {
		out = append(out, assign(ident("sourcePosition"), token.ASSIGN, textLiteral(s.Pos.String())))
		statements := g.statement(s)
		statements[0] = g.locatedStatement(s.Pos, statements[0])
		out = append(out, statements...)
	}
	return out
}
func (g *generator) pattern(p *syntax.Pattern, value ast.Expr) []ast.Stmt {
	if p.Kind == syntax.KindName {
		b := g.program.Bindings[p]
		return []ast.Stmt{&ast.DeclStmt{Decl: variable(b.ID, runtimeName("Value"), value)}, discard(ident(b.ID))}
	}
	tmp := g.temp()
	out := []ast.Stmt{define(tmp, value), discard(ident(tmp))}
	if p.Kind == syntax.KindRecord {
		for _, f := range p.Fields {
			out = append(out, g.pattern(f.Pattern, runtimeCall("Field", ident(tmp), textLiteral(f.Name)))...)
		}
	}
	if p.Kind == syntax.KindList {
		positions := g.temp()
		out = append(out, define(positions, runtimeCall("Positions", ident(tmp), sourceAt(p.Pos, intLiteral(len(p.Elements))))), discard(ident(positions)))
		for i, child := range p.Elements {
			out = append(out, g.pattern(child, index(ident(positions), intLiteral(i)))...)
		}
	}
	return out
}
func (g *generator) statement(s *syntax.Statement) []ast.Stmt {
	switch s.Kind {
	case syntax.KindBind:
		return g.pattern(s.Pattern, g.expression(s.Value))
	case syntax.KindAssign:
		if s.Target != nil {
			return []ast.Stmt{evaluated(runtimeCall("SetField", g.expression(s.Target.Left), textLiteral(s.Target.Text), g.expression(s.Value)))}
		}
		// Assignment binding identities are recorded by the checker, including shadows.
		return []ast.Stmt{assign(ident(g.program.Assignments[s.Value].ID), token.ASSIGN, g.expression(s.Value))}
	case syntax.KindReturn:
		value := unit()
		if s.Value != nil {
			value = g.expression(s.Value)
		}
		if g.expressionDepth > 0 {
			value = runtimeCall("Return", value)
		}
		return []ast.Stmt{returned(value)}
	case syntax.KindCall:
		return []ast.Stmt{discard(g.expression(s.Value))}
	case syntax.KindBreak, syntax.KindContinue:
		var out []ast.Stmt
		start := 0
		if len(g.loopCleanup) > 0 {
			start = g.loopCleanup[len(g.loopCleanup)-1]
		}
		for i := len(g.cleanups) - 1; i >= start; i-- {
			out = append(out, evaluated(call(selector(ident(g.cleanups[i]), "Run"))))
		}
		label := g.loopLabels[len(g.loopLabels)-1]
		label.used = true
		if label.depth < g.expressionDepth || label.escaped {
			label.escaped = true
			return append(out, evaluated(runtimeCall("ExitLoop", ident(strconv.FormatBool(s.Kind == syntax.KindBreak)))))
		}
		op := token.BREAK
		if s.Kind == syntax.KindContinue {
			op = token.CONTINUE
		}
		return append(out, &ast.BranchStmt{Tok: op, Label: ident(label.name)})
	case syntax.KindIf:
		stmt := &ast.IfStmt{Cond: runtimeCall("Bool", g.expression(s.Value)), Body: block(g.body(s.Body)...)}
		if len(s.Else) > 0 {
			stmt.Else = block(g.body(s.Else)...)
		}
		return []ast.Stmt{stmt}
	case syntax.KindWhile, syntax.KindFor:
		g.loopCleanup = append(g.loopCleanup, len(g.cleanups))
		label := &loopLabel{name: g.temp(), depth: g.expressionDepth}
		g.loopLabels = append(g.loopLabels, label)
		body := g.loopBody(s.Body, label)
		g.loopCleanup = g.loopCleanup[:len(g.loopCleanup)-1]
		g.loopLabels = g.loopLabels[:len(g.loopLabels)-1]
		var loop ast.Stmt
		if s.Kind == syntax.KindWhile {
			body = append([]ast.Stmt{evaluated(runtimeCall("CheckCancelled", ident("ctx")))}, body...)
			loop = &ast.ForStmt{Cond: runtimeCall("Bool", g.expression(s.Value)), Body: block(body...)}
		} else {
			b := g.program.LoopBindings[s]
			body = append([]ast.Stmt{discard(ident(b.ID)), evaluated(runtimeCall("CheckCancelled", ident("ctx")))}, body...)
			loop = &ast.RangeStmt{Key: ident("_"), Value: ident(b.ID), Tok: token.DEFINE, X: runtimeCall("Iterate", g.expression(s.Value)), Body: block(body...)}
		}
		if label.used {
			loop = &ast.LabeledStmt{Label: ident(label.name), Stmt: loop}
		}
		return []ast.Stmt{loop}
	case syntax.KindWith:
		b := g.program.LoopBindings[s]
		cleanup := g.temp()
		g.cleanups = append(g.cleanups, cleanup)
		body := g.body(s.Body)
		g.cleanups = g.cleanups[:len(g.cleanups)-1]
		contract := textLiteral("")
		if method := g.program.Cleanups[s]; method != nil && method.Contract != nil {
			contract = g.key(method.Contract)
		}
		out := []ast.Stmt{define(b.ID, g.expression(s.Value)), discard(ident(b.ID)), define(cleanup, call(selector(ident("cleanupStack"), "PushContract"), ident("ctx"), ident(b.ID), contract, g.typeScope(b.Type)))}
		out = append(out, body...)
		out = append(out, evaluated(call(selector(ident(cleanup), "Run"))))
		return []ast.Stmt{block(out...)}
	}
	panic("missing lowering for " + s.Kind)
}
func (g *generator) match(value *syntax.Expression, arms []syntax.Arm, body func(*syntax.Arm) []ast.Stmt) []ast.Stmt {
	tmp := g.temp()
	contractMatch := g.program.Expressions[value].Type.Kind == "contract"
	out := []ast.Stmt{define(tmp, g.expression(value))}
	tag := "Tag"
	if contractMatch {
		out = append(out, assign(ident(tmp), token.ASSIGN, runtimeCall("ContractReceiver", ident(tmp))))
		tag = "ConcreteType"
	}
	var cases []ast.Stmt
	for at := range arms {
		a := &arms[at]
		clause := &ast.CaseClause{}
		if a.Path.Text != "_" {
			key := textLiteral(a.Path.Text)
			if contractMatch {
				key = g.key(g.program.ContractPatterns[a])
			}
			clause.List = []ast.Expr{key}
		}
		for i, b := range g.program.ArmBindings[a] {
			if b != nil {
				var value ast.Expr = runtimeCall("Payload", ident(tmp), intLiteral(i))
				if contractMatch {
					value = ident(tmp)
				}
				clause.Body = append(clause.Body, define(b.ID, value), discard(ident(b.ID)))
			}
		}
		clause.Body = append(clause.Body, body(a)...)
		cases = append(cases, clause)
	}
	return append(out, &ast.SwitchStmt{Tag: runtimeCall(tag, ident(tmp)), Body: block(cases...)})
}

// A loop containing match expressions gets a boundary for exits from their
// generated closures. Scan before lowering so nested loops are emitted once.
func (g *generator) loopBody(statements []*syntax.Statement, label *loopLabel) []ast.Stmt {
	syntax.Visitor{Expression: func(e *syntax.Expression) {
		if e.Kind == syntax.KindMatch {
			label.escaped = true
		}
	}}.Callable(nil, statements)
	if !label.escaped {
		return g.body(statements)
	}
	label.used = true
	g.expressionDepth++
	body := g.body(statements)
	g.expressionDepth--
	body = append(body, returned(unit()))
	return []ast.Stmt{&ast.SwitchStmt{Tag: runtimeCall("LoopBody", closure(nil, runtimeName("Value"), body...)), Body: block(
		&ast.CaseClause{List: []ast.Expr{intLiteral(1)}, Body: []ast.Stmt{&ast.BranchStmt{Tok: token.BREAK, Label: ident(label.name)}}},
		&ast.CaseClause{List: []ast.Expr{intLiteral(2)}, Body: []ast.Stmt{&ast.BranchStmt{Tok: token.CONTINUE, Label: ident(label.name)}}},
	)}}
}
