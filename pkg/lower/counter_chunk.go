package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

type counterChunk struct {
	pos       syntax.Position
	counter   *checker.Binding
	limit     int64
	aggregate *counterAggregate
}

// Group only two total updates whose arithmetic has already been proved safe.
// Aggregate unobservable prefixes only with the stronger ownership/capture and
// generated-temporary proof; otherwise keep individual source assignments.
func (p *intProof) chunk(s *syntax.Statement, counter *checker.Binding, limit int64, bounds intBounds) {
	if len(s.Body) != 2 {
		return
	}

	update, step := s.Body[0], s.Body[1]
	if step.Kind != syntax.KindAssign || p.target(step) != counter {
		return
	}
	aggregate := p.aggregateUpdate(update, counter, bounds)
	if aggregate != nil {
		p.g.fn.counterChunks[s] = &counterChunk{counter: counter, limit: limit, aggregate: aggregate, pos: s.Pos}
		return
	}
	carry := p.target(update)
	if update.Kind != syntax.KindAssign || carry == nil || carry == counter || !p.g.fn.safeInt[update.Value] {
		return
	}
	v := update.Value
	if v.Kind != syntax.KindBinary || (v.Text != "+" && v.Text != "-") || v.Left.Kind != syntax.KindName || p.g.info(v.Left).Binding != carry || !p.constantStride(v.Right, counter, carry) {
		return
	}
	p.g.fn.counterChunks[s] = &counterChunk{counter: counter, limit: limit}
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
	if chunk.aggregate != nil {
		return g.aggregateChunk(chunk, cond, body)
	}
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
