package compiler

import (
	"fmt"
	"go/ast"
	"go/token"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Measured with bundled Go 1.25.1: small literals do not benefit from a data
// table; 4K–100K scalars do. For effectful elements, 256 assignments per closure
// bounds native compiler work without the call/code-size cost of 64 or the SSA
// cost of 1024. See scripts/bench-flat-literals for the retained comparisons.
const largeListLiteral = 1024
const listLiteralChunk = 256

func (g *generator) listLiteral(e *syntax.Expression, typ *checker.Type) ast.Expr {
	var items ast.Expr
	if len(e.Elements) <= largeListLiteral {
		elements := make([]ast.Expr, len(e.Elements))
		for i, item := range e.Elements {
			elements[i] = g.expression(item)
		}
		items = sliceLiteral(runtimeName("Value"), elements...)
	} else {
		name := g.temp()
		body := []ast.Stmt{define(name, call(ident("make"), sliceOf(runtimeName("Value")), intLiteral(len(e.Elements))))}
		var data []ast.Expr
		var pending []ast.Stmt
		flush := func() {
			if len(pending) != 0 {
				body = append(body, evaluated(call(closure(nil, nil, pending...))))
				pending = nil
			}
		}
		for i, item := range e.Elements {
			if value := g.literalScalar(item); value != nil {
				data = append(data, &ast.KeyValueExpr{Key: intLiteral(i), Value: value})
				continue
			}
			// Separate assignments capture even plain local reads before a later
			// element can mutate them. Closures share the source callable's frame,
			// cleanup stack, type evidence and nonlocal return/loop boundaries.
			pending = append(pending, assign(index(ident(name), intLiteral(i)), token.ASSIGN, g.expression(item)))
			if len(pending) == listLiteralChunk {
				flush()
			}
		}
		flush()
		if len(data) != 0 {
			dataName := fmt.Sprintf("literalData%d", len(g.literalData)+1)
			array := &ast.ArrayType{Len: intLiteral(len(e.Elements)), Elt: runtimeName("Value")}
			if len(data) == len(e.Elements) {
				for i, entry := range data {
					data[i] = entry.(*ast.KeyValueExpr).Value
				}
			}
			g.literalData = append(g.literalData, variable(dataName, nil, composite(array, data...)))
			// Only immutable primitive values enter this private table. Each
			// evaluation copies into fresh storage; source mutations cannot reach
			// the table. Records, nested lists, views and call results stay local.
			copyData := evaluated(call(ident("copy"), ident(name), &ast.SliceExpr{X: ident(dataName)}))
			body = append([]ast.Stmt{body[0], copyData}, body[1:]...)
		}
		body = append(body, returned(ident(name)))
		items = call(closure(nil, sliceOf(runtimeName("Value")), body...))
	}
	return address(composite(runtimeName("List"), keyed("Type", g.key(typ)), keyed("Items", items)))
}

// A literal's syntax alone is insufficient: retain the checked primitive
// identity and reject conversions and every mutable/reference-bearing value.
func (g *generator) literalScalar(e *syntax.Expression) ast.Expr {
	info := g.program.Expressions[e]
	if info.ErrorSource != nil || info.Type.Kind != "primitive" {
		return nil
	}
	switch e.Kind {
	case syntax.KindNumber:
		if info.Type.ID == "Int" || info.Type.ID == "Float" {
			return g.expression(e)
		}
	case syntax.KindBool:
		if info.Type.ID == "Bool" {
			return ident(e.Text)
		}
	case syntax.KindText:
		if info.Type.ID == "String" {
			var text strings.Builder
			for _, part := range e.Parts {
				if part.Value != nil {
					return nil
				}
				text.WriteString(part.Text)
			}
			return textLiteral(text.String())
		}
	case syntax.KindUnary:
		if e.Text == "-" && e.Right.Kind == syntax.KindNumber && (info.Type.ID == "Int" || info.Type.ID == "Float") {
			if info.Type.ID == "Float" {
				value, _ := strconv.ParseFloat(e.Right.Text, 64)
				if value == 0 {
					// Go constants have no negative zero. Keep the runtime negation.
					return nil
				}
			}
			if info.Type.ID == "Int" && e.Right.Text == "9223372036854775808" {
				return call(ident("int64"), signedInteger("-9223372036854775808"))
			}
			return &ast.UnaryExpr{Op: token.SUB, X: g.expression(e.Right)}
		}
	}
	return nil
}
