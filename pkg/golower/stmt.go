package golower

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
	var out []ast.Stmt
	for _, s := range stmts {
		lowered := g.statement(s)
		if len(lowered) == 0 {
			continue
		}
		lowered[0] = g.locatedStatement(s.Pos, lowered[0])
		out = append(out, lowered...)
	}
	return out
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
		return []ast.Stmt{g.branch(token.BREAK)}
	case syntax.KindContinue:
		return []ast.Stmt{g.branch(token.CONTINUE)}
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
		case "int64", "float64", "string", "bool", "len", "cap":
			return false
		}
	}
	return true
}

func (g *gen) returnStatement(s *syntax.Statement) []ast.Stmt {
	var value ast.Expr = g.unit()
	if s.Value != nil {
		value = g.valueAs(s.Value, g.fn.result)
	}
	return []ast.Stmt{returned(value)}
}

func (g *gen) bind(s *syntax.Statement) []ast.Stmt {
	value := g.expr(s.Value)
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
	cond := g.valueAs(s.Value, boolType)
	stmt := &ast.IfStmt{Cond: cond, Body: block(g.body(s.Body, nil)...)}
	if len(s.Else) > 0 {
		stmt.Else = block(g.body(s.Else, nil)...)
	}
	return []ast.Stmt{stmt}
}

var (
	boolType = &checker.Type{Name: "Bool", ID: "Bool", Kind: "primitive"}
	intType  = &checker.Type{Name: "Int", ID: "Int", Kind: "primitive"}
	unitType = &checker.Type{Name: "Unit", ID: "Unit", Kind: "primitive"}
)

// branch is break or continue for the innermost loop. Inside a match's Go
// switch a bare break would leave the switch, so the loop is labeled then.
func (g *gen) branch(tok token.Token) ast.Stmt {
	loop := g.fn.loops[len(g.fn.loops)-1]
	if g.fn.switches > loop.switches {
		loop.used = true
		return &ast.BranchStmt{Tok: tok, Label: ident(loop.label)}
	}
	return &ast.BranchStmt{Tok: tok}
}

// loop lowers while and for. Every back edge polls for cancellation.
func (g *gen) loop(s *syntax.Statement) []ast.Stmt {
	state := &loopState{label: g.temp(), switches: g.fn.switches}
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
	poll := evaluated(rtCall("Poll", ident("ctx"), address(ident(tick))))
	declare := varDecl(tick, ident("uint32"), nil)
	if s.Kind == syntax.KindWhile {
		saved := g.fn.pre
		g.fn.pre = nil
		cond := g.valueAs(s.Value, boolType)
		pre := g.fn.pre
		g.fn.pre = saved
		body := g.body(s.Body, nil)
		if len(pre) == 0 {
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
	iterable := g.expr(s.Value)
	body := g.body(s.Body, nil)
	body = append([]ast.Stmt{poll}, body...)
	return append([]ast.Stmt{declare}, g.rangeLoop(s, binding, iterable, body)...)
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
		return []ast.Stmt{&ast.RangeStmt{Key: ident("_"), Value: ident(name), Tok: token.DEFINE, X: call(selector(iterable, "Snapshot")), Body: block(body...)}}
	}
	g.fail("cannot iterate %s", t)
	return nil
}

// with registers a lexical cleanup; added when cleanup stacks land.
func (g *gen) with(s *syntax.Statement) []ast.Stmt {
	g.fail("with is not lowered yet")
	return nil
}
