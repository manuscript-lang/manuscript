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
	if pre, value := g.inlineTry(s); value != nil {
		switch s.Kind {
		case syntax.KindBind:
			return append(pre, g.pattern(s.Pattern, value)...)
		case syntax.KindAssign:
			return append(pre, assign(ident(g.program.Assignments[s.Value].ID), token.ASSIGN, value))
		case syntax.KindReturn:
			return append(pre, returned(value))
		default:
			return append(pre, discard(value))
		}
	}
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
		if s.Value.Kind == syntax.KindMatch {
			return g.matchStatement(s.Value)
		}
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

// A match in statement position lowers to a Go switch in the enclosing body,
// so return, break, and continue in its arms are ordinary Go statements. Only
// a match used as a value needs the generated closure.
func (g *generator) matchStatement(e *syntax.Expression) []ast.Stmt {
	out := g.match(e.Left, e.Arms, func(a *syntax.Arm) []ast.Stmt {
		body := g.body(a.Body)
		if a.Value != nil {
			body = append(body, discard(g.expression(a.Value)))
		}
		return body
	})
	cases := out[len(out)-1].(*ast.SwitchStmt)
	for _, clause := range cases.Body.List {
		if clause.(*ast.CaseClause).List == nil {
			return out
		}
	}
	cases.Body.List = append(cases.Body.List, &ast.CaseClause{Body: []ast.Stmt{evaluated(runtimeCall("Panic", textLiteral("runtime invariant: exhaustive match")))}})
	return out
}

// A loop containing match expressions gets a boundary for exits from their
// generated closures. Scan before lowering so nested loops are emitted once.
func (g *generator) loopBody(statements []*syntax.Statement, label *loopLabel) []ast.Stmt {
	direct := map[*syntax.Expression]bool{}
	syntax.Visitor{Statement: func(s *syntax.Statement) {
		if s.Kind == syntax.KindCall && s.Value.Kind == syntax.KindMatch {
			direct[s.Value] = true
		}
	}, Expression: func(e *syntax.Expression) {
		if e.Kind == syntax.KindMatch && !direct[e] {
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

// A statement whose whole value is `try call` returns the error result directly
// instead of panicking through the function's deferred handlers. It applies
// only outside expression closures, where a Go return leaves the Manuscript
// function.
func (g *generator) inlineTry(s *syntax.Statement) ([]ast.Stmt, ast.Expr) {
	if g.expressionDepth > 0 || s.Value == nil || s.Target != nil {
		return nil, nil
	}
	switch s.Kind {
	case syntax.KindBind, syntax.KindAssign, syntax.KindReturn, syntax.KindCall:
	default:
		return nil, nil
	}
	e := s.Value
	info := g.program.Expressions[e]
	if e.Kind != syntax.KindUnary || e.Text != "try" || info.ErrorSource != nil || g.booleans[e] {
		return nil, nil
	}
	tmp := g.temp()
	cause := index(selector(ident(tmp), "Fields"), intLiteral(0))
	var propagated ast.Expr = cause
	if info.ScopedPropagation {
		propagated = runtimeCall("ViewOf", textLiteral("@std/Error"), cause, g.typeScope(info.PropagatedError))
	}
	failure := composite(runtimeName("Alternative"), keyed("Type", g.resultKey), keyed("Tag", textLiteral("error")), keyed("Fields", sliceLiteral(runtimeName("Value"), propagated)))
	check := &ast.IfStmt{
		Cond: &ast.BinaryExpr{X: selector(ident(tmp), "Tag"), Op: token.EQL, Y: textLiteral("error")},
		Body: block(returned(failure)),
	}
	pre := []ast.Stmt{define(tmp, &ast.TypeAssertExpr{X: g.expression(e.Right), Type: runtimeName("Alternative")}), check}
	return pre, index(selector(ident(tmp), "Fields"), intLiteral(0))
}
