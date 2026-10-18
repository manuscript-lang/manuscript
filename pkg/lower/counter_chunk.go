package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

type counterChunk struct {
	counter *checker.Binding
	limit   int64
}

// Chunk only two total, independent scalar updates. Their arithmetic has
// already been proved safe, and neither operation can observe cancellation.
// Keep the original assignments, including the counter step last.
func (p *intProof) chunk(s *syntax.Statement, counter *checker.Binding, limit int64) {
	if len(s.Body) != 2 {
		return
	}
	update, step := s.Body[0], s.Body[1]
	carry := p.target(update)
	if update.Kind != syntax.KindAssign || step.Kind != syntax.KindAssign || carry == nil ||
		carry == counter || p.target(step) != counter || !p.g.fn.safeInt[update.Value] {
		return
	}
	v := update.Value
	if v.Kind != syntax.KindBinary || (v.Text != "+" && v.Text != "-") ||
		v.Left.Kind != syntax.KindName || p.g.info(v.Left).Binding != carry ||
		!p.constantStride(v.Right, counter, carry) {
		return
	}
	p.g.fn.counterChunks[s] = &counterChunk{counter, limit}
}

func (p *intProof) constantStride(e *syntax.Expression, counter, carry *checker.Binding) bool {
	if _, ok := p.literal(e); ok {
		return true
	}
	if _, ok := p.g.fn.listLengths[e]; ok {
		return true // Inventory proves the direct immutable receiver and call.
	}
	if e.Kind == syntax.KindName {
		b := p.g.info(e).Binding
		bounds := p.get(b)
		return b != nil && b != counter && b != carry && bounds.lo == bounds.hi
	}
	return e.Kind == syntax.KindBinary && (e.Text == "+" || e.Text == "-") && p.g.fn.safeInt[e] &&
		p.constantStride(e.Left, counter, carry) && p.constantStride(e.Right, counter, carry)
}

// Poll before exactly the same 64th, 128th, ... original body. A guarded
// endpoint avoids overflow near MaxInt; the proof also bounds limit-counter.
func (g *gen) chunkLoop(s *syntax.Statement, chunk *counterChunk, cond ast.Expr, body []ast.Stmt) []ast.Stmt {
	counter := ident(g.bindingName(chunk.counter))
	limit := intLiteral(int(chunk.limit))
	end := g.temp()
	// The two small assignment copies have disjoint execution and unique source
	// markers. Lowering this fixed-size body twice keeps marker ownership local.
	polled := append([]ast.Stmt{evaluated(rtCall("CheckCancelled", ident("ctx")))}, g.body(s.Body, nil)...)
	inner := []ast.Stmt{
		define(end, limit),
		&ast.IfStmt{
			Cond: binary(binary(limit, token.SUB, counter), token.GTR, intLiteral(63)),
			Body: block(assign(ident(end), token.ASSIGN, binary(counter, token.ADD, intLiteral(63)))),
		},
		&ast.ForStmt{Cond: binary(counter, token.LSS, ident(end)), Body: block(body...)},
		&ast.IfStmt{Cond: cond, Body: block(polled...)},
	}
	return []ast.Stmt{&ast.ForStmt{Cond: cond, Body: block(inner...)}}
}
