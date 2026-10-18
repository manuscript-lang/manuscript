package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// body lowers a statement list. Each statement's pre-statements (hoisted
// matches, tries, and spilled operands) come first, and the first emitted
// statement carries the source position.
func (g *gen) body(stmts []*syntax.Statement, result *checker.Type) []ast.Stmt {
	fn := g.fn
	saved := fn.literalStarts
	fn.literalStarts = nil
	defer func() { fn.literalStarts = saved }()
	var out []ast.Stmt
	tail := g.tailResultOperand(stmts)
	lineTail := g.tailLineOperand(stmts)
	for i, s := range stmts {
		if (tail != nil || lineTail != nil) && i == len(stmts)-2 {
			// Use the ordinary expression plumbing: its pre-statements may
			// themselves return or evaluate effectful operands.
			saved := g.fn.pre
			g.fn.pre = nil
			var value ast.Expr
			if lineTail != nil {
				value = g.linePresence(lineTail)
			} else {
				value = g.valueAs(tail, g.fn.result)
			}
			lowered := append(g.fn.pre, returned(value))
			g.fn.pre = saved
			lowered[0] = g.locatedStatement(s.Pos, lowered[0])
			out = append(out, lowered...)
			break
		}
		lowered := g.statement(s)
		g.recordLiteralStart(s)
		if len(lowered) == 0 {
			continue
		}
		lowered[0] = g.locatedStatement(s.Pos, lowered[0])
		out = append(out, lowered...)
	}
	return out
}

// Keep only straight-line literal writes. Any other statement may contain a
// nested assignment (including in a match expression), so discard all facts.
// Each body owns its facts; no scans or facts from enclosing branches are needed.
func (g *gen) recordLiteralStart(s *syntax.Statement) {
	var binding *checker.Binding
	if s.Kind == syntax.KindBind && s.Pattern.Kind == syntax.KindName {
		binding = g.program.PatternBinding(s.Pattern)
	} else if s.Kind == syntax.KindAssign && s.Target == nil {
		binding = g.program.AssignedBinding(s.Value)
	}
	value := s.Value
	if value != nil && value.Kind == syntax.KindUnary && value.Text == "-" {
		value = value.Right
	}
	if binding != nil && binding.Type.ID == "Int" && value != nil && value.Kind == syntax.KindNumber {
		if g.fn.literalStarts == nil {
			g.fn.literalStarts = map[*checker.Binding]bool{}
		}
		g.fn.literalStarts[binding] = true
		return
	}
	g.fn.literalStarts = nil
}

// statement lowers one statement, flushing the pre-statements its expressions
// produced ahead of it.
func (g *gen) statement(s *syntax.Statement) []ast.Stmt {
	saved := g.fn.pre
	g.fn.pre = nil
	main := g.statementKind(s)
	out := append(g.fn.pre, main...)
	g.fn.pre = saved
	return out
}

func (g *gen) statementKind(s *syntax.Statement) []ast.Stmt {
	switch s.Kind {
	case syntax.KindBind:
		return g.bind(s)
	case syntax.KindAssign:
		return g.assignment(s)
	case syntax.KindCall:
		return g.callStatement(s)
	case syntax.KindReturn:
		return g.returnStatement(s)
	case syntax.KindBreak:
		return g.branch(token.BREAK)
	case syntax.KindContinue:
		return g.branch(token.CONTINUE)
	case syntax.KindIf:
		return g.ifStatement(s)
	case syntax.KindWhile, syntax.KindFor:
		return g.loop(s)
	case syntax.KindWith:
		return g.with(s)
	}
	g.fail("missing lowering for statement %s", s.Kind)
	return nil
}

// callStatement evaluates an expression for its effects.
func (g *gen) callStatement(s *syntax.Statement) []ast.Stmt {
	if s.Value.Kind == syntax.KindMatch {
		return g.matchStatement(s.Value)
	}
	value := g.expr(s.Value)
	if _, ok := value.(*ast.CallExpr); ok && g.statementCall(value) {
		return []ast.Stmt{evaluated(value)}
	}
	return []ast.Stmt{discard(value)}
}

// statementCall reports whether e may stand alone as a Go statement.
func (g *gen) statementCall(e ast.Expr) bool {
	c, ok := e.(*ast.CallExpr)
	if !ok {
		return false
	}
	if id, ok := c.Fun.(*ast.Ident); ok {
		switch id.Name {
		case "int", "float64", "string", "bool", "len", "cap":
			return false
		}
	}
	return true
}

func (g *gen) returnStatement(s *syntax.Statement) []ast.Stmt {
	var value ast.Expr = g.unit()
	if g.testBody() && (s.Value == nil || s.Value.Kind == syntax.KindUnit) {
		value = g.testSuccess()
	}
	if s.Value != nil && !(g.testBody() && s.Value.Kind == syntax.KindUnit) {
		value = g.valueAs(s.Value, g.fn.result)
	}
	return []ast.Stmt{returned(value)}
}

func (g *gen) bind(s *syntax.Statement) []ast.Stmt {
	var value ast.Expr
	if b := g.program.PatternBinding(s.Pattern); s.Pattern.Kind == syntax.KindName && b != nil {
		value = g.valueAs(s.Value, b.Type)
	} else {
		value = g.expr(s.Value)
	}
	return g.pattern(s.Pattern, value, g.info(s.Value).Type)
}

// pattern binds the parts of value, whose type is t, to the pattern's names.
func (g *gen) pattern(p *syntax.Pattern, value ast.Expr, t *checker.Type) []ast.Stmt {
	switch p.Kind {
	case syntax.KindName:
		b := g.program.PatternBinding(p)
		if b == nil {
			return []ast.Stmt{discard(value)}
		}
		name := g.bindingName(b)
		if b.Mutable {
			g.mutable(name)
		}
		out := []ast.Stmt{define(name, value)}
		return append(out, g.keepUnused(b)...)
	}
	tmp := g.temp()
	out := []ast.Stmt{define(tmp, value)}
	switch p.Kind {
	case syntax.KindRecord:
		for _, f := range p.Fields {
			ft := g.fieldType(t, f.Name)
			out = append(out, g.pattern(f.Pattern, selector(ident(tmp), fieldName(f.Name)), ft)...)
		}
	case syntax.KindList:
		items := g.temp()
		out = append(out, define(items, rtCall("Positions", ident(tmp), intLiteral(len(p.Elements)))))
		for i, child := range p.Elements {
			out = append(out, g.pattern(child, index(ident(items), intLiteral(i)), t.Args[0])...)
		}
	}
	if len(out) == 1 {
		out = append(out, discard(ident(tmp)))
	}
	return out
}

func (g *gen) mutable(name string) {
	if g.fn.mutables == nil {
		g.fn.mutables = map[string]bool{}
	}
	g.fn.mutables[name] = true
}

func (g *gen) fieldType(t *checker.Type, name string) *checker.Type {
	for _, f := range checker.Fields(g.sub(t)) {
		if f.Name == name {
			return f.Type
		}
	}
	g.fail("%s has no field %s", t, name)
	return nil
}

func (g *gen) assignment(s *syntax.Statement) []ast.Stmt {
	if s.Target != nil {
		receiverType := g.info(s.Target.Left).Type
		ft := g.fieldType(receiverType, s.Target.Text)
		values := g.operandsAs([]*syntax.Expression{s.Target.Left, s.Value}, []*checker.Type{receiverType, ft})
		return []ast.Stmt{assign(selector(values[0], fieldName(s.Target.Text)), token.ASSIGN, values[1])}
	}
	target := g.program.AssignedBinding(s.Value)
	value := g.valueAs(s.Value, g.sub(target.Type))
	return []ast.Stmt{assign(ident(g.bindingName(target)), token.ASSIGN, value)}
}

func (g *gen) ifStatement(s *syntax.Statement) []ast.Stmt {
	if s.Pattern != nil {
		return g.ifLet(s)
	}
	cond := g.valueAs(s.Value, boolType)
	stmt := &ast.IfStmt{Cond: cond, Body: block(g.body(s.Body, nil)...)}
	if len(s.Else) > 0 {
		stmt.Else = block(g.body(s.Else, nil)...)
	}
	return []ast.Stmt{stmt}
}

// ifLet lowers `if let name = optional` to a presence test, and `if let name = result` to a
// success test, around the payload binding.
func (g *gen) ifLet(s *syntax.Statement) []ast.Stmt {
	tmp := g.temp()
	value := g.expr(s.Value)
	body := g.pattern(s.Pattern, selector(ident(tmp), "Val"), g.sub(g.info(s.Value).Type).Args[0])
	body = append(body, g.body(s.Body, nil)...)
	cond := ast.Expr(selector(ident(tmp), "Some"))
	if g.sub(g.info(s.Value).Type).ID == "@std/Result" {
		cond = not(selector(ident(tmp), "Failed"))
	}
	stmt := &ast.IfStmt{Cond: cond, Body: block(body...)}
	if len(s.Else) > 0 {
		stmt.Else = block(g.body(s.Else, nil)...)
	}
	return []ast.Stmt{block(define(tmp, value), stmt)}
}

var (
	boolType = &checker.Type{Name: "Bool", ID: "Bool", Kind: "primitive"}
	intType  = &checker.Type{Name: "Int", ID: "Int", Kind: "primitive"}
	unitType = &checker.Type{Name: "Unit", ID: "Unit", Kind: "primitive"}
)

// branch is break or continue for the innermost loop. Inside a match's Go
// switch a bare break would leave the switch, so the loop is labeled then.
func (g *gen) branch(tok token.Token) []ast.Stmt {
	loop := g.fn.loops[len(g.fn.loops)-1]
	var out []ast.Stmt
	// Leaving the loop's body closes the resources it registered, innermost first.
	for i := len(g.fn.withs) - 1; i >= loop.withs; i-- {
		out = append(out, evaluated(call(selector(ident(g.fn.withs[i]), "Run"))))
	}
	if g.fn.switches > loop.switches {
		loop.used = true
		return append(out, &ast.BranchStmt{Tok: tok, Label: ident(loop.label)})
	}
	return append(out, &ast.BranchStmt{Tok: tok})
}

// loop lowers while and for. Every back edge polls for cancellation.
func (g *gen) loop(s *syntax.Statement) []ast.Stmt {
	state := &loopState{label: g.temp(), switches: g.fn.switches, withs: len(g.fn.withs)}
	g.fn.loops = append(g.fn.loops, state)
	out := g.loopStatements(s)
	g.fn.loops = g.fn.loops[:len(g.fn.loops)-1]
	if state.used {
		last := len(out) - 1
		out[last] = &ast.LabeledStmt{Label: ident(state.label), Stmt: out[last]}
	}
	return out
}

func (g *gen) loopStatements(s *syntax.Statement) []ast.Stmt {
	tick := g.temp()
	// Inline, with the counter a plain local, so the loop keeps it in a register.
	poll := &ast.IfStmt{
		Init: &ast.IncDecStmt{X: ident(tick), Tok: token.INC},
		Cond: binary(binary(ident(tick), token.AND, &ast.BasicLit{Kind: token.INT, Value: "63"}), token.EQL, &ast.BasicLit{Kind: token.INT, Value: "0"}),
		Body: block(evaluated(rtCall("CheckCancelled", ident("ctx")))),
	}
	declare := varDecl(tick, ident("uint32"), nil)
	if s.Kind == syntax.KindWhile {
		saved := g.fn.pre
		g.fn.pre = nil
		// The header belongs to the enclosing loop, not to this one, but its
		// statements run inside this loop's Go for, so exits must be labeled.
		loops := g.fn.loops
		g.fn.loops = loops[:len(loops)-1]
		g.fn.switches++
		cond := g.valueAs(s.Value, boolType)
		g.fn.switches--
		g.fn.loops = loops
		pre := g.fn.pre
		g.fn.pre = saved
		g.markCounterStep(s)
		if len(pre) == 0 {
			if counter, descending := g.pollCounter(s); counter != nil {
				initial := g.temp()
				value := ident(g.bindingName(counter))
				declare = define(initial, value)
				distance := binary(value, token.SUB, ident(initial))
				if descending {
					distance = binary(ident(initial), token.SUB, value)
				}
				// The same 64th-iteration phase, expressed as a zero test so
				// Go can use an add and bit test instead of a masked compare.
				distance = binary(distance, token.ADD, intLiteral(1))
				poll = &ast.IfStmt{
					Cond: binary(binary(distance, token.AND, intLiteral(63)), token.EQL, intLiteral(0)),
					Body: block(evaluated(rtCall("CheckCancelled", ident("ctx")))),
				}
			}
		}
		body := g.body(s.Body, nil)
		if len(pre) == 0 {
			if chunk := g.fn.counterChunks[s]; chunk != nil {
				return g.chunkLoop(s, chunk, cond, body)
			}
			return []ast.Stmt{declare, &ast.ForStmt{Cond: cond, Body: block(append([]ast.Stmt{poll}, body...)...)}}
		}
		var inner []ast.Stmt
		inner = append(inner, poll)
		inner = append(inner, pre...)
		inner = append(inner, &ast.IfStmt{Cond: not(cond), Body: block(&ast.BranchStmt{Tok: token.BREAK})})
		inner = append(inner, body...)
		return []ast.Stmt{declare, &ast.ForStmt{Body: block(inner...)}}
	}
	binding := g.program.LoopBinding(s)
	if setup, from, to, ok := g.countingRange(s.Value); ok {
		body := g.body(s.Body, nil)
		body = append(g.keepUnused(binding), body...)
		counter := g.temp()
		body = append([]ast.Stmt{poll, define(g.bindingName(binding), ident(counter))}, body...)
		count := &ast.ForStmt{
			Init: define(counter, from),
			Cond: binary(ident(counter), token.LSS, to),
			Post: &ast.IncDecStmt{X: ident(counter), Tok: token.INC},
			Body: block(body...),
		}
		return append(append(setup, declare), count)
	}
	iterable := g.expr(s.Value)
	if out, ok := g.closedRangeChunk(s, iterable); ok {
		return out
	}
	body := g.body(s.Body, nil)
	body = append([]ast.Stmt{poll}, body...)
	return append([]ast.Stmt{declare}, g.rangeLoop(s, binding, iterable, body)...)
}

// pollCounter recognizes a counter that advances exactly once per completed
// iteration. Unlike the overflow proof, it must reject every other write and
// every continue: either could leave the poll phase unrelated to iterations.
func (g *gen) pollCounter(s *syntax.Statement) (*checker.Binding, bool) {
	cond := s.Value
	if cond.Kind != syntax.KindBinary || cond.Left.Kind != syntax.KindName ||
		(cond.Text != "<" && cond.Text != ">") || cond.Right.Kind != syntax.KindNumber {
		return nil, false
	}
	counter := g.info(cond.Left).Binding
	if counter == nil || counter.Type.ID != "Int" || !g.fn.literalStarts[counter] {
		return nil, false
	}
	var step *syntax.Statement
	for _, stmt := range s.Body {
		if stmt.Kind == syntax.KindAssign && stmt.Target == nil && g.fn.stepped[stmt.Value] &&
			g.program.AssignedBinding(stmt.Value) == counter {
			step = stmt
		}
	}
	if step == nil {
		return nil, false
	}
	valid := true
	syntax.Visitor{Statement: func(stmt *syntax.Statement) {
		if stmt.Kind == syntax.KindContinue || stmt.Kind == syntax.KindAssign && stmt.Target == nil &&
			g.program.AssignedBinding(stmt.Value) == counter && stmt != step {
			valid = false
		}
	}}.Callable(nil, s.Body)
	if !valid {
		return nil, false
	}
	return counter, cond.Text == ">"
}

// countingRange recognizes `range(start, end)` from @std/collections.ms as the
// iterable of a for loop. The loop then counts without building the list, so
// a large bound allocates nothing. Both bounds are evaluated once, in written
// order, before the first iteration.
func (g *gen) countingRange(e *syntax.Expression) (setup []ast.Stmt, from, to ast.Expr, ok bool) {
	if e.Kind != syntax.KindCall {
		return nil, nil, nil, false
	}
	info := g.info(e)
	if info == nil || info.Symbol == nil || info.Symbol.Native != "collections/range" || len(info.Arguments) != 2 {
		return nil, nil, nil, false
	}
	args := g.arguments(info.Arguments, g.calleeOf(info.Symbol, g.info(e.Left).Type))
	bounds := make([]ast.Expr, len(args))
	for i, arg := range args {
		if literal, isLiteral := arg.(*ast.BasicLit); isLiteral {
			bounds[i] = literal
			continue
		}
		name := g.temp()
		setup = append(setup, define(name, arg))
		bounds[i] = ident(name)
	}
	return setup, bounds[0], bounds[1], true
}

// rangeLoop iterates a collection. A list traversal captures its backing
// slice and initial length, which is what ranging over the slice does.
func (g *gen) rangeLoop(s *syntax.Statement, binding *checker.Binding, iterable ast.Expr, body []ast.Stmt) []ast.Stmt {
	t := g.info(s.Value).Type
	name := g.bindingName(binding)
	keep := g.keepUnused(binding)
	body = append(keep, body...)
	switch {
	case isStd(t, "List"):
		return []ast.Stmt{&ast.RangeStmt{Key: ident("_"), Value: ident(name), Tok: token.DEFINE, X: selector(iterable, "Items"), Body: block(body...)}}
	case isStd(t, "Set"):
		return []ast.Stmt{&ast.RangeStmt{Key: ident("_"), Value: ident(name), Tok: token.DEFINE, X: call(selector(iterable, "Snapshot")), Body: block(body...)}}
	case isStd(t, "Map"):
		// One copy of the entries; each iteration binds a pointer into it.
		entries, at := g.temp(), g.temp()
		body = append([]ast.Stmt{define(name, address(index(ident(entries), ident(at))))}, body...)
		return []ast.Stmt{
			define(entries, call(selector(iterable, "Copies"))),
			&ast.RangeStmt{Key: ident(at), Tok: token.DEFINE, X: ident(entries), Body: block(body...)},
		}
	}
	g.fail("cannot iterate %s", t)
	return nil
}

// with registers a lexical cleanup. The close operation runs when the block
// ends normally, before break and continue leave it, and from the function's
// deferred unwind on return, error, fault, or cancellation.
func (g *gen) with(s *syntax.Statement) []ast.Stmt {
	b := g.program.LoopBinding(s)
	value := g.expr(s.Value)
	g.fn.cleanup = true
	name := g.bindingName(b)
	action := g.temp()
	resource := g.sub(b.Type)
	closer := g.closeOperation(s, resource, ident(name))
	out := []ast.Stmt{define(name, value)}
	out = append(out, g.keepUnused(b)...)
	register := call(selector(ident("cs"), "Push"), ident("ctx"), closure([]*ast.Field{field("ctx", pointerTo(rtName("Execution")))}, nil, evaluated(closer)))
	out = append(out, define(action, register))
	g.fn.withs = append(g.fn.withs, action)
	out = append(out, g.body(s.Body, nil)...)
	g.fn.withs = g.fn.withs[:len(g.fn.withs)-1]
	out = append(out, evaluated(call(selector(ident(action), "Run"))))
	return []ast.Stmt{block(out...)}
}

// closeOperation calls the resource's close implementation.
func (g *gen) closeOperation(s *syntax.Statement, resource *checker.Type, value ast.Expr) ast.Expr {
	m := g.program.Cleanup(s)
	if m == nil {
		g.fail("%s: with has no close operation", s.Pos)
		return ident("nil")
	}
	m = g.resolveMethod(m, resource, "close")
	return g.invokeMethod(m, resource, value, "close", nil, nil)
}

// markCounterStep marks the increment of `while i < n` (or decrement of
// `while i > n`) whose operand the guard bounds, so `i + 1` cannot exceed n.
// Locals change only by assignment in their own function, and the step must be
// a top-level statement reached before any other assignment to i.
func (g *gen) markCounterStep(s *syntax.Statement) {
	cond := s.Value
	if cond == nil || cond.Kind != syntax.KindBinary || cond.Left.Kind != syntax.KindName || (cond.Text != "<" && cond.Text != ">") {
		return
	}
	counter := g.info(cond.Left)
	if counter == nil || counter.Binding == nil || counter.Binding.Type.ID != "Int" || g.info(cond.Right).Type.ID != "Int" {
		return
	}
	step := "+"
	if cond.Text == ">" {
		step = "-"
	}
	assigns := func(stmt *syntax.Statement) (found bool) {
		syntax.Visitor{Statement: func(inner *syntax.Statement) {
			if inner.Kind == syntax.KindAssign && inner.Target == nil && inner.Name == cond.Left.Text {
				found = true
			}
		}}.Callable(nil, []*syntax.Statement{stmt})
		return found
	}
	for _, stmt := range s.Body {
		if !assigns(stmt) {
			continue
		}
		v := stmt.Value
		if stmt.Kind == syntax.KindAssign && stmt.Target == nil && v != nil && v.Kind == syntax.KindBinary && v.Text == step &&
			v.Left.Kind == syntax.KindName && v.Right.Kind == syntax.KindNumber && v.Right.Text == "1" {
			if info := g.info(v.Left); info != nil && info.Binding == counter.Binding {
				if g.fn.stepped == nil {
					g.fn.stepped = map[*syntax.Expression]bool{}
				}
				g.fn.stepped[v] = true
			}
		}
		return
	}
}
