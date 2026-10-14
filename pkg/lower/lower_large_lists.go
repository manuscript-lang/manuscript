package lower

import (
	"fmt"
	"go/ast"
	"go/token"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A list literal with at least largeListThreshold items is not lowered as one
// Go composite literal: the Go compiler's time and memory grow faster than the
// item count when a single function holds that many expressions.
const (
	largeListThreshold = 256
	largeListChunk     = 64
)

// largeListValue lowers a large list literal, or returns nil for a small one.
// Debug builds keep their own large-literal lowering, which the debugger
// tests pin.
func (g *generator) largeListValue(e *syntax.Expression, info *checker.Info) ast.Expr {
	if g.debugLiterals || len(e.Elements) < largeListThreshold {
		return nil
	}
	if table := g.listTable(e, info.Type); table != nil {
		return table
	}
	return address(composite(runtimeName("List"), keyed("Type", g.key(info.Type)), keyed("Items", g.chunkedItems(e))))
}

// listTable lowers a literal whose items are all constants of the list's
// scalar element type to a typed package-level array. Each evaluation copies
// it into a fresh List, so mutation never reaches the shared data.
func (g *generator) listTable(e *syntax.Expression, typ *checker.Type) ast.Expr {
	if typ == nil || len(typ.Args) != 1 || typ.Args[0].Kind != "primitive" {
		return nil
	}
	goType := map[string]string{"Int": "int64", "Float": "float64", "Bool": "bool", "String": "string"}[typ.Args[0].ID]
	if goType == "" {
		return nil
	}
	values := make([]ast.Expr, len(e.Elements))
	for i, item := range e.Elements {
		if values[i] = g.constantScalar(item, typ.Args[0].ID, goType); values[i] == nil {
			return nil
		}
	}
	data, table := fmt.Sprintf("listData%d", len(g.literalData)), fmt.Sprintf("listTable%d", len(g.literalData)+1)
	g.literalData = append(g.literalData,
		variable(data, nil, sliceLiteral(ident(goType), values...)),
		variable(table, &ast.IndexExpr{X: runtimeName("ListTable"), Index: ident(goType)}, nil))
	return call(selector(ident(table), "List"), g.key(typ), ident(data))
}

// constantScalar is item's Go constant when item is a literal of exactly the
// checked primitive id, or nil. Conversions, interpolation, and Decimal keep
// normal lowering. Negative Floats do too: Go folds -0.0 to positive zero.
func (g *generator) constantScalar(item *syntax.Expression, id, goType string) ast.Expr {
	info := g.program.Info(item)
	if info == nil || info.ErrorSource != nil || info.Type == nil || info.Type.Kind != "primitive" || info.Type.ID != id {
		return nil
	}
	switch item.Kind {
	case syntax.KindNumber:
		if g.nativeType(item) == goType {
			return numberValue(item).(*ast.CallExpr).Args[0]
		}
	case syntax.KindUnary:
		if item.Text != "-" || goType != "int64" || item.Right.Kind != syntax.KindNumber || g.nativeType(item.Right) != "int64" {
			return nil
		}
		if item.Right.Text == "9223372036854775808" {
			return signedInteger("-9223372036854775808")
		}
		return &ast.UnaryExpr{Op: token.SUB, X: numberValue(item.Right).(*ast.CallExpr).Args[0]}
	case syntax.KindBool:
		if goType == "bool" {
			return ident(item.Text)
		}
	case syntax.KindText:
		if goType != "string" {
			return nil
		}
		var text strings.Builder
		for _, part := range item.Parts {
			if part.Value != nil {
				return nil
			}
			text.WriteString(part.Text)
		}
		return textLiteral(text.String())
	}
	return nil
}

// chunkedItems evaluates items in source order through immediately called
// closures of at most largeListChunk assignments each, so every Go function
// stays small. Like a match expression's closure, each chunk raises returns,
// loop exits, and propagation as panics that the enclosing function handles.
// Each assignment carries its item's source line, so the closures' extra
// physical lines do not shift profile or debugger locations.
func (g *generator) chunkedItems(e *syntax.Expression) ast.Expr {
	items := g.temp()
	body := []ast.Stmt{define(items, call(ident("make"), sliceOf(runtimeName("Value")), intLiteral(len(e.Elements))))}
	g.expressionDepth++
	for start := 0; start < len(e.Elements); start += largeListChunk {
		end := min(start+largeListChunk, len(e.Elements))
		part := g.temp()
		array := &ast.StarExpr{X: &ast.ArrayType{Len: intLiteral(end - start), Elt: runtimeName("Value")}}
		var chunk []ast.Stmt
		for at := start; at < end; at++ {
			item := e.Elements[at]
			chunk = append(chunk, g.locatedStatement(item.Pos, assign(index(ident(part), intLiteral(at-start)), token.ASSIGN, g.expression(item))))
		}
		fill := call(closure([]*ast.Field{field(part, array)}, nil, chunk...), call(paren(array), &ast.SliceExpr{X: ident(items), Low: intLiteral(start), High: intLiteral(end)}))
		body = append(body, g.locatedStatement(e.Pos, evaluated(fill)))
	}
	g.expressionDepth--
	return call(closure(nil, sliceOf(runtimeName("Value")), append(body, returned(ident(items)))...))
}
