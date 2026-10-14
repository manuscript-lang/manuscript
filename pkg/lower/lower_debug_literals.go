package lower

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/ir"
	"go/ast"
	"strings"
)

const debugListThreshold = 1024

// Debug alone trades repeated construction cost for less native compilation.
// Only complete immutable scalar lists qualify; mixed/effectful lists retain
// the existing expression and control-flow lowering in every build mode.
func (g *generator) debugListLiteral(list ir.List) ast.Expr {
	if !g.debugLiterals || len(list.Items) <= debugListThreshold {
		return nil
	}
	values := make([]ast.Expr, len(list.Items))
	for i, item := range list.Items {
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
	return address(composite(runtimeName("List"), keyed("Type", g.key(list.Type)), keyed("Items", items)))
}

// A literal's syntax alone is insufficient: retain the checked primitive
// identity and reject conversions and every mutable/reference-bearing value.
// Numeric widths and rounding belong to checked expression lowering.
func (g *generator) debugLiteralScalar(x ir.Expr) ast.Expr {
	switch x := x.(type) {
	case ir.IntLiteral:
		if isPrimitive(x.Type, "Int") {
			return g.irValue(x)
		}
	case ir.FloatLiteral:
		if isPrimitive(x.Type, "Float") {
			return g.irValue(x)
		}
	case ir.BoolLiteral:
		if isPrimitive(x.Type, "Bool") {
			return g.irValue(x)
		}
	case ir.Text:
		if !isPrimitive(x.Type, "String") {
			return nil
		}
		var text strings.Builder
		for _, part := range x.Parts {
			if part.Value != nil {
				return nil
			}
			text.WriteString(part.Text)
		}
		return textLiteral(text.String())
	}
	return nil
}

func isPrimitive(t *checker.Type, id string) bool {
	return t.Kind == "primitive" && t.ID == id
}
