package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"go/ast"
	"go/token"
)

// Keep every original update in order. A fixed unroll only amortizes induction
// and polling; the existing closed-list proof covers every accumulator prefix.
func (g *gen) closedRangeChunk(s *syntax.Statement, iterable ast.Expr) ([]ast.Stmt, bool) {
	if !g.fn.rangeChunks[s] || len(s.Body) != 1 {
		return nil, false
	}
	update := s.Body[0]
	carry := g.program.AssignedBinding(update.Value)
	element := g.program.LoopBinding(s)
	v := update.Value
	if update.Kind != syntax.KindAssign || update.Target != nil || carry == nil || carry == element || g.capturedBindings[carry] || g.capturedBindings[element] || v == nil || v.Kind != syntax.KindBinary || (v.Text != "+" && v.Text != "-") || !g.fn.safeInt[v] || !g.resultParameter(v.Left, carry) || !g.resultParameter(v.Right, element) {
		return nil, false
	}
	items, at, end, chunk := g.temp(), g.temp(), g.temp(), g.temp()
	name := g.bindingName(element)
	body := func(value ast.Expr) []ast.Stmt {
		return append([]ast.Stmt{define(name, value)}, g.body(s.Body, nil)...)
	}
	var unrolled []ast.Stmt
	for i := 0; i < 3; i++ {
		unrolled = append(unrolled, block(body(index(ident(chunk), intLiteral(i)))...))
	}
	unrolled = append(unrolled, assign(ident(chunk), token.ASSIGN, &ast.SliceExpr{X: ident(chunk), Low: intLiteral(3)}))
	poll := g.locatedStatement(s.Pos, evaluated(rtCall("CheckCancelled", ident("ctx"))))
	queried := []ast.Stmt{define(name, index(ident(items), ident(at))), poll}
	queried = append(queried, g.body(s.Body, nil)...)
	queried = append(queried, &ast.IncDecStmt{X: ident(at), Tok: token.INC})
	length := func() ast.Expr { return call(ident("len"), ident(items)) }
	loop := []ast.Stmt{
		define(end, length()),
		&ast.IfStmt{Cond: binary(binary(length(), token.SUB, ident(at)), token.GTR, intLiteral(63)), Body: block(assign(ident(end), token.ASSIGN, binary(ident(at), token.ADD, intLiteral(63))))},
		define(chunk, &ast.SliceExpr{X: ident(items), Low: ident(at), High: ident(end)}),
		&ast.ForStmt{Cond: binary(call(ident("len"), ident(chunk)), token.GEQ, intLiteral(3)), Body: block(unrolled...)},
		&ast.RangeStmt{Key: ident("_"), Value: ident(name), Tok: token.DEFINE, X: ident(chunk), Body: block(g.body(s.Body, nil)...)},
		assign(ident(at), token.ASSIGN, ident(end)),
		&ast.IfStmt{Cond: binary(ident(at), token.LSS, length()), Body: block(queried...)},
	}
	return []ast.Stmt{define(items, selector(iterable, "Items")), &ast.ForStmt{Init: define(at, intLiteral(0)), Cond: binary(ident(at), token.LSS, length()), Body: block(loop...)}}, true
}
