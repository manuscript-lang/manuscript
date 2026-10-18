package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"go/ast"
	"go/token"
	"strings"
)

type counterAggregate struct {
	builder          bool
	fragment         string
	pos              syntax.Position
	binding          *checker.Binding
	field            string
	delta            int64
	affine, subtract bool
}

// A single published inventory avoids rescanning enclosing callable trees.
// Conservatively mark even lambda-local bindings: aggregation inside a lambda
// can fall back rather than require another capture/ownership analysis.
func (g *gen) captureInventory() map[*checker.Binding]bool {
	captured := map[*checker.Binding]bool{}
	if g.program == nil {
		return captured
	}
	depth := 0
	visitor := syntax.Visitor{Expression: func(e *syntax.Expression) {
		if e.Kind == syntax.KindLambda {
			depth++
		}
		if depth > 0 && e.Kind == syntax.KindName {
			if info := g.info(e); info != nil && info.Binding != nil {
				captured[info.Binding] = true
			}
		}
	}, LeaveExpression: func(e *syntax.Expression) {
		if e.Kind == syntax.KindLambda {
			depth--
		}
	}}
	for _, module := range g.program.Modules {
		for _, d := range module.Declarations {
			visitor.Walk(d)
		}
	}
	return captured
}

func (p *intProof) unobservedStride(e *syntax.Expression) bool {
	if e == nil {
		return false
	}
	if e.Kind == syntax.KindName && p.g.capturedBindings[p.g.info(e).Binding] {
		return false
	}
	if _, ok := p.g.fn.listLengths[e]; ok {
		return true
	}
	if e.Kind == syntax.KindBinary {
		return p.unobservedStride(e.Left) && p.unobservedStride(e.Right)
	}
	return e.Kind == syntax.KindNumber || e.Kind == syntax.KindName || e.Kind == syntax.KindUnary && e.Text == "-" && e.Right.Kind == syntax.KindNumber
}

// This recognizer proves a call has no observable work, not merely a return
// interval. The specialized ABI and all source plumbing must be exact Ints.
func (p *intProof) pureCounter(e *syntax.Expression, counter *checker.Binding) bool {
	if e.Kind == syntax.KindName {
		return p.g.resultPlain(e) && p.g.info(e).Binding == counter
	}
	if e.Kind != syntax.KindCall || !p.g.resultPlain(e) || len(e.Args) != 1 || !p.g.resultParameter(e.Args[0].Value, counter) {
		return false
	}
	info, callee := p.g.info(e), p.g.info(e.Left)
	if (e.Left.Kind != syntax.KindName && e.Left.Kind != syntax.KindApply) || !p.g.resultPlain(e.Left) || callee == nil || callee.Binding != nil || info.Symbol == nil || callee.Symbol != info.Symbol || info.Symbol.Native != "" || len(info.Symbol.Variables) > 1 || p.g.sub(info.Type).ID != "Int" {
		return false
	}
	signature := p.g.sub(callee.Type)
	if signature == nil || len(signature.Params) != 1 || signature.Params[0].Type.ID != "Int" || signature.Result.ID != "Int" || defaulted(signature, 0) {
		return false
	}
	d := info.Symbol.Decl
	if d == nil || p.g.recursive[d] || len(d.Params) != 1 || d.Params[0].Default != nil || len(d.Body) != 1 || d.Body[0].Kind != syntax.KindReturn {
		return false
	}
	bindings := p.g.program.ParameterBindings(d)
	return len(bindings) == 1 && !bindings[0].Mutable && p.g.resultParameter(d.Body[0].Value, bindings[0])
}

func (p *intProof) aggregateUpdate(update *syntax.Statement, counter *checker.Binding, counterBounds intBounds) *counterAggregate {
	if p.g.capturedBindings[counter] {
		return nil
	}
	var result counterAggregate
	var stride *syntax.Expression
	if update.Kind == syntax.KindCall {
		if local := p.g.fn.localCollections; local != nil {
			if op, ok := local.builderAppends[update.Value]; ok {
				return &counterAggregate{binding: op.binding, builder: true, fragment: op.fragment, pos: update.Pos}
			}
		}
		op := p.g.fn.recordUpdates[update.Value]
		if op == nil || len(update.Value.Args) != 1 {
			return nil
		}
		result.binding, result.field, result.subtract = op.binding, op.field, op.operator == "-"
		stride = update.Value.Args[0].Value
		if !p.constantStride(stride, counter, nil) {
			return nil
		}
	} else {
		carry := p.target(update)
		v := update.Value
		if update.Kind != syntax.KindAssign || carry == nil || carry == counter || p.g.capturedBindings[carry] || v == nil || v.Kind != syntax.KindBinary || (v.Text != "+" && v.Text != "-") || v.Left.Kind != syntax.KindName || p.g.info(v.Left).Binding != carry || !p.g.fn.safeInt[v] {
			return nil
		}
		result.binding, result.subtract = carry, v.Text == "-"
		stride = v.Right
		result.affine = p.pureCounter(stride, counter)
		if !result.affine && !p.constantStride(stride, counter, carry) {
			return nil
		}
	}
	if result.affine {
		// Each new temporary must fit even though the original updates fit.
		product, ok := multiplyIntBounds(intBounds{1, 63}, counterBounds)
		if !ok {
			return nil
		}
		if _, ok := addIntBounds(product, intBounds{0, 1953}, false); !ok {
			return nil
		}
	} else {
		if !p.unobservedStride(stride) {
			return nil
		}
		bounds := p.expression(stride, false)
		if bounds.lo != bounds.hi {
			return nil
		}
		if _, ok := multiplyIntBounds(intBounds{1, 63}, bounds); !ok {
			return nil
		}
		result.delta = bounds.lo
	}
	return &result
}

func (g *gen) aggregateChunk(chunk *counterChunk, cond ast.Expr, body []ast.Stmt) []ast.Stmt {
	counter := ident(g.bindingName(chunk.counter))
	limit := intLiteral(int(chunk.limit))
	n := g.temp()
	target := ast.Expr(ident(g.bindingName(chunk.aggregate.binding)))
	if chunk.aggregate.field != "" {
		target = selector(target, fieldName(chunk.aggregate.field))
	}
	delta := ast.Expr(binary(ident(n), token.MUL, intLiteral(int(chunk.aggregate.delta))))
	if chunk.aggregate.affine {
		product := binary(ident(n), token.MUL, counter)
		series := binary(binary(ident(n), token.MUL, binary(ident(n), token.SUB, intLiteral(1))), token.QUO, intLiteral(2))
		delta = binary(product, token.ADD, series)
	}
	operator := token.ADD
	if chunk.aggregate.subtract {
		operator = token.SUB
	}
	polled := append([]ast.Stmt{g.locatedStatement(chunk.pos, evaluated(rtCall("CheckCancelled", ident("ctx"))))}, body...)
	var change ast.Stmt = assign(target, token.ASSIGN, binary(target, operator, delta))
	if chunk.aggregate.builder {
		text := &ast.SliceExpr{X: textLiteral(strings.Repeat(chunk.aggregate.fragment, 63)), High: binary(ident(n), token.MUL, intLiteral(len(chunk.aggregate.fragment)))}
		change = g.locatedStatement(chunk.aggregate.pos, evaluated(rtCall("StringBuilder_Append", ident("ctx"), target, text)))
	}
	inner := []ast.Stmt{
		define(n, binary(limit, token.SUB, counter)),
		&ast.IfStmt{Cond: binary(ident(n), token.GTR, intLiteral(63)), Body: block(assign(ident(n), token.ASSIGN, intLiteral(63)))},
		change,
		assign(counter, token.ASSIGN, binary(counter, token.ADD, ident(n))),
		&ast.IfStmt{Cond: cond, Body: block(polled...)},
	}
	return []ast.Stmt{&ast.ForStmt{Cond: cond, Body: block(inner...)}}
}
