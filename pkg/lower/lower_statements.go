package lower

import (
	"go/ast"
	"go/token"
	"strconv"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (g *generator) body(body []*syntax.Statement) []ast.Stmt {
	var out []ast.Stmt
	for _, s := range body {
		statements := g.statement(s)
		statements[0] = g.locatedStatement(s.Pos, statements[0])
		out = append(out, statements...)
	}
	return out
}

// pattern binds value, whose Go type is native when it is not Value.
func (g *generator) pattern(p *syntax.Pattern, value ast.Expr, native string) []ast.Stmt {
	if p.Kind == syntax.KindName {
		b := g.program.PatternBinding(p)
		if typ := g.declareTyped(b); typ != "" {
			if native != typ {
				value = unbox(value, typ)
			}
			return []ast.Stmt{&ast.DeclStmt{Decl: variable(b.ID, ident(typ), value)}, discard(ident(b.ID))}
		}
		return []ast.Stmt{&ast.DeclStmt{Decl: variable(b.ID, runtimeName("Value"), value)}, discard(ident(b.ID))}
	}
	tmp := g.temp()
	out := []ast.Stmt{define(tmp, value), discard(ident(tmp))}
	if p.Kind == syntax.KindRecord {
		for _, f := range p.Fields {
			out = append(out, g.pattern(f.Pattern, runtimeCall("Field", ident(tmp), textLiteral(f.Name)), "")...)
		}
	}
	if p.Kind == syntax.KindList {
		positions := g.temp()
		out = append(out, define(positions, runtimeCall("Positions", ident(tmp), sourceAt(p.Pos, intLiteral(len(p.Elements))))), discard(ident(positions)))
		for i, child := range p.Elements {
			out = append(out, g.pattern(child, index(ident(positions), intLiteral(i)), "")...)
		}
	}
	return out
}
func (g *generator) statement(s *syntax.Statement) []ast.Stmt {
	if pre, value, native := g.inlineTry(s); value != nil {
		return append(pre, g.afterTry(s, value, native)...)
	}
	if pre := g.hoistTries(s); pre != nil {
		return append(pre, g.statement(s)...)
	}
	switch s.Kind {
	case syntax.KindBind:
		if out := g.altLet(s); out != nil {
			return out
		}
		return g.pattern(s.Pattern, g.expression(s.Value), g.nativeType(s.Value))
	case syntax.KindAssign:
		return g.assignment(s)
	case syntax.KindReturn:
		return g.returnStatement(s)
	case syntax.KindCall:
		if s.Value.Kind == syntax.KindMatch {
			return g.matchStatement(s.Value)
		}
		return []ast.Stmt{discard(g.expression(s.Value))}
	case syntax.KindBreak, syntax.KindContinue:
		return g.exitLoop(s)
	case syntax.KindIf:
		stmt := &ast.IfStmt{Cond: g.condition(s.Value), Body: block(g.body(s.Body)...)}
		if len(s.Else) > 0 {
			stmt.Else = block(g.body(s.Else)...)
		}
		return []ast.Stmt{stmt}
	case syntax.KindWhile, syntax.KindFor:
		return g.loop(s)
	case syntax.KindWith:
		return g.with(s)
	}
	panic("missing lowering for " + s.Kind)
}

// afterTry completes a statement whose value was already evaluated by an
// inline try.
func (g *generator) afterTry(s *syntax.Statement, value ast.Expr, native string) []ast.Stmt {
	switch s.Kind {
	case syntax.KindBind:
		return g.pattern(s.Pattern, value, native)
	case syntax.KindAssign:
		target := g.program.AssignedBinding(s.Value)
		if typ := g.typed[target]; typ != "" && native != typ {
			value = unbox(value, typ)
		}
		return []ast.Stmt{assign(ident(target.ID), token.ASSIGN, value)}
	case syntax.KindReturn:
		if g.resultShape != nil {
			value = g.resultShape.unbox(value)
		}
		return []ast.Stmt{returned(value)}
	}
	return []ast.Stmt{discard(value)}
}

func (g *generator) assignment(s *syntax.Statement) []ast.Stmt {
	if s.Target != nil {
		// The receiver is evaluated before the replacement value. A match in
		// the value can reassign the local the receiver names, and Go does not
		// order that variable read before the later call.
		receiverValue := g.expression(s.Target.Left)
		if containsMatch(s.Value) && !g.constant(s.Target.Left) {
			receiverValue = sourceAt(s.Target.Left.Pos, receiverValue)
		}
		if st, f := g.structFieldOf(s.Target); st != nil {
			receiver := g.structPointer(st, receiverValue)
			var value ast.Expr
			if f.scalar != "" {
				value = g.scalar(s.Value, f.scalar)
			} else {
				value = g.expression(s.Value)
			}
			return []ast.Stmt{evaluated(call(selector(receiver, "Set_"+s.Target.Text), value))}
		}
		return []ast.Stmt{evaluated(runtimeCall("SetField", receiverValue, textLiteral(s.Target.Text), g.expression(s.Value)))}
	}
	// Assignment binding identities are recorded by the checker, including shadows.
	target := g.program.AssignedBinding(s.Value)
	if typ := g.typed[target]; typ != "" {
		return []ast.Stmt{assign(ident(target.ID), token.ASSIGN, g.scalar(s.Value, typ))}
	}
	return []ast.Stmt{assign(ident(target.ID), token.ASSIGN, g.expression(s.Value))}
}

func (g *generator) returnStatement(s *syntax.Statement) []ast.Stmt {
	value := unit()
	if s.Value != nil {
		if g.resultType != "" && g.expressionDepth == 0 {
			value = g.scalar(s.Value, g.resultType)
		} else if g.resultShape != nil && g.expressionDepth == 0 {
			value = g.typedReturn(s.Value)
		} else {
			value = g.expression(s.Value)
		}
	}
	if g.expressionDepth > 0 {
		g.recovers = true
		value = runtimeCall("Return", value)
	}
	return []ast.Stmt{returned(value)}
}

// exitLoop lowers break and continue, running the cleanups opened inside the
// loop first.
func (g *generator) exitLoop(s *syntax.Statement) []ast.Stmt {
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
}

func (g *generator) loop(s *syntax.Statement) []ast.Stmt {
	g.loopCleanup = append(g.loopCleanup, len(g.cleanups))
	label := &loopLabel{name: g.temp(), depth: g.expressionDepth}
	g.loopLabels = append(g.loopLabels, label)
	element := ""
	if s.Kind != syntax.KindWhile {
		element = g.declareTyped(g.program.LoopBinding(s))
	}
	body := g.loopBody(s.Body, label)
	g.loopCleanup = g.loopCleanup[:len(g.loopCleanup)-1]
	g.loopLabels = g.loopLabels[:len(g.loopLabels)-1]
	var loop ast.Stmt
	if s.Kind == syntax.KindWhile {
		// The counter limits cancellation checks to every 64th iteration.
		tick := g.temp()
		body = append([]ast.Stmt{evaluated(runtimeCall("Poll", ident("ctx"), address(ident(tick))))}, body...)
		loop = &ast.ForStmt{Init: define(tick, call(ident("uint32"), intLiteral(0))), Cond: g.condition(s.Value), Body: block(body...)}
	} else {
		b := g.program.LoopBinding(s)
		index := g.temp()
		body = append([]ast.Stmt{discard(ident(b.ID)), evaluated(runtimeCall("PollIndex", ident("ctx"), ident(index)))}, body...)
		iterate := "Iterate" + primitiveKinds[element]
		loop = &ast.RangeStmt{Key: ident(index), Value: ident(b.ID), Tok: token.DEFINE, X: runtimeCall(iterate, g.expression(s.Value)), Body: block(body...)}
	}
	if label.used {
		loop = &ast.LabeledStmt{Label: ident(label.name), Stmt: loop}
	}
	return []ast.Stmt{loop}
}

// with lowers a resource scope: the cleanup runs when the body ends and is
// also registered for returns and faults that leave it early.
func (g *generator) with(s *syntax.Statement) []ast.Stmt {
	b := g.program.LoopBinding(s)
	cleanup := g.temp()
	g.cleanups = append(g.cleanups, cleanup)
	body := g.body(s.Body)
	g.cleanups = g.cleanups[:len(g.cleanups)-1]
	contract := textLiteral("")
	if method := g.program.Cleanup(s); method != nil && method.Contract != nil {
		contract = g.key(method.Contract)
	}
	out := []ast.Stmt{define(b.ID, g.expression(s.Value)), discard(ident(b.ID)), define(cleanup, call(selector(ident("cleanupStack"), "PushContract"), ident("ctx"), ident(b.ID), contract, g.typeScope(b.Type)))}
	g.needsCleanup = true
	out = append(out, body...)
	out = append(out, evaluated(call(selector(ident(cleanup), "Run"))))
	return []ast.Stmt{block(out...)}
}
func (g *generator) match(value *syntax.Expression, arms []syntax.Arm, body func(*syntax.Arm) []ast.Stmt) []ast.Stmt {
	tmp := g.temp()
	contractMatch := g.program.Info(value).Type.Kind == "contract"
	if b, shape := g.altLocalOf(value); shape != nil {
		return g.typedMatch(tmp, ident(b.ID), shape, arms, body)
	}
	if !contractMatch && !g.listAtMatch(value) {
		if typed, direct := g.typedDirectCall(value); typed != nil && direct.shape != nil {
			return g.typedMatch(tmp, typed, direct.shape, arms, body)
		}
	}
	out := []ast.Stmt{define(tmp, g.expression(value))}
	tag := "Tag"
	var present string
	if !contractMatch && g.listAtMatch(value) {
		present = g.temp()
		out = []ast.Stmt{&ast.AssignStmt{Lhs: []ast.Expr{ident(tmp), ident(present)}, Tok: token.DEFINE, Rhs: []ast.Expr{g.listAtParts(value)}}}
	}
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
				key = g.key(g.program.ContractPattern(a))
			}
			clause.List = []ast.Expr{key}
		}
		for i, b := range g.program.ArmBindingsFor(a) {
			if b != nil {
				var value ast.Expr = runtimeCall("Payload", ident(tmp), intLiteral(i))
				if present != "" {
					value = ident(tmp)
				}
				if contractMatch {
					value = ident(tmp)
				}
				clause.Body = append(clause.Body, define(b.ID, value), discard(ident(b.ID)))
			}
		}
		clause.Body = append(clause.Body, body(a)...)
		cases = append(cases, clause)
	}
	if present != "" {
		return append(out, &ast.SwitchStmt{Tag: runtimeCall("OptionalTag", ident(present)), Body: block(cases...)})
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
func (g *generator) inlineTry(s *syntax.Statement) ([]ast.Stmt, ast.Expr, string) {
	if g.expressionDepth > 0 || !g.program.PlainTry(s) {
		return nil, nil, ""
	}
	return g.tryReturn(s.Value)
}

// tryReturn evaluates a `try` expression into statements that return the
// error result on failure, and the expression that yields the success value
// with its Go type ("" for a boxed Value).
func (g *generator) tryReturn(e *syntax.Expression) ([]ast.Stmt, ast.Expr, string) {
	info := g.program.Info(e)
	tmp := g.temp()
	if typed, direct := g.typedDirectCall(e.Right); typed != nil && direct.shape != nil && !direct.shape.optional {
		var propagated ast.Expr = selector(ident(tmp), "Cause")
		if info.ScopedPropagation {
			propagated = runtimeCall("ViewOf", textLiteral("@std/Error"), propagated, g.typeScope(info.PropagatedError))
		}
		var failure ast.Expr
		if g.resultShape != nil {
			failure = composite(g.resultShape.typeExpr(), keyed("Cause", propagated), keyed("Failed", ident("true")))
		} else {
			failure = composite(runtimeName("Alternative"), keyed("Type", g.resultKey), keyed("Tag", textLiteral("error")), keyed("Fields", sliceLiteral(runtimeName("Value"), propagated)))
		}
		check := &ast.IfStmt{Cond: direct.shape.failed(tmp), Body: block(returned(failure))}
		return []ast.Stmt{define(tmp, typed), check}, selector(ident(tmp), "Val"), direct.shape.payload
	}
	cause := index(selector(ident(tmp), "Fields"), intLiteral(0))
	var propagated ast.Expr = cause
	if info.ScopedPropagation {
		propagated = runtimeCall("ViewOf", textLiteral("@std/Error"), cause, g.typeScope(info.PropagatedError))
	}
	var failure ast.Expr = composite(runtimeName("Alternative"), keyed("Type", g.resultKey), keyed("Tag", textLiteral("error")), keyed("Fields", sliceLiteral(runtimeName("Value"), propagated)))
	if g.resultShape != nil {
		failure = composite(g.resultShape.typeExpr(), keyed("Cause", propagated), keyed("Failed", ident("true")))
	}
	check := &ast.IfStmt{
		Cond: &ast.BinaryExpr{X: selector(ident(tmp), "Tag"), Op: token.EQL, Y: textLiteral("error")},
		Body: block(returned(failure)),
	}
	pre := []ast.Stmt{define(tmp, &ast.TypeAssertExpr{X: g.expression(e.Right), Type: runtimeName("Alternative")}), check}
	return pre, index(selector(ident(tmp), "Fields"), intLiteral(0)), ""
}

// exprFree reports whether e is built only from literals, typed locals, and
// scalar operations, so lowering it runs no call and no unlocated operation.
func (g *generator) exprFree(e *syntax.Expression) bool {
	if e == nil || g.nativeType(e) == "" {
		return false
	}
	switch e.Kind {
	case syntax.KindNumber, syntax.KindBool, syntax.KindName:
		return true
	case syntax.KindBinary:
		return g.exprFree(e.Left) && g.exprFree(e.Right)
	}
	return false
}
