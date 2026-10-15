package lower

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"go/ast"
	"strings"
)

const debugListThreshold = 1024

// Debug alone trades repeated construction cost for less native compilation.
// Only complete immutable scalar lists qualify; mixed/effectful lists retain
// the existing expression and control-flow lowering in every build mode.
func (g *generator) debugListLiteral(e *syntax.Expression, typ *checker.Type) ast.Expr {
	if !g.debugLiterals || len(e.Elements) <= debugListThreshold {
		return nil
	}
	values := make([]ast.Expr, len(e.Elements))
	for i, item := range e.Elements {
		values[i] = g.debugLiteralScalar(item)
		if values[i] == nil {
			return nil
		}
	}
	dataName := fmt.Sprintf("debugLiteralData%d", len(g.literalData)+1)
	array := &ast.ArrayType{Len: intLiteral(len(values)), Elt: runtimeName("Value")}
	g.literalData = append(g.literalData, variable(dataName, nil, composite(array, values...)))
	// Keep construction in the source statement. An anonymous copy thunk
	// introduces extra physical Go lines/frames that confuse source stepping.
	// Appending to nil allocates fresh mutable storage without exposing data.
	items := call(ident("append"), call(sliceOf(runtimeName("Value")), ident("nil")), &ast.SliceExpr{X: ident(dataName)})
	items.Ellipsis = 1
	return address(composite(runtimeName("List"), keyed("Type", g.key(typ)), keyed("Items", items)))
}

// A literal's syntax alone is insufficient: retain the checked primitive
// identity and reject conversions and every mutable/reference-bearing value.
// Unary numbers retain normal lowering, including the sign of rounded zero;
// numeric widths and rounding belong to checked expression lowering.
func (g *generator) debugLiteralScalar(e *syntax.Expression) ast.Expr {
	info := g.info(e)
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
	}
	return nil
}
