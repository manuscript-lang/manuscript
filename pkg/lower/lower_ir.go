package lower

import (
	"go/ast"
	"go/token"
	"strconv"

	"github.com/manuscript-lang/manuscript/pkg/ir"
)

// irValue lowers an elaborated expression. It decides nothing about meaning:
// every classification and checked fact is already on the node.
func (g *generator) irValue(x ir.Expr) ast.Expr {
	switch x := x.(type) {
	case ir.Deferred:
		return g.expression(x.Source)
	case ir.IntLiteral:
		return call(ident("int64"), signedInteger(strconv.FormatInt(x.Value, 10)))
	case ir.FloatLiteral:
		return call(ident("float64"), &ast.BasicLit{Kind: token.FLOAT, Value: strconv.FormatFloat(x.Value, 'g', -1, 64)})
	case ir.DecimalLiteral:
		return runtimeCall("DecimalLiteral", textLiteral(x.Text))
	case ir.BoolLiteral:
		return ident(strconv.FormatBool(x.Value))
	case ir.Local:
		return g.binding(x.Binding)
	case ir.Unary:
		if x.Op == "not" {
			return &ast.UnaryExpr{Op: token.NOT, X: paren(g.irScalar(x.Operand, "bool"))}
		}
		return locatedAt(x.Pos, runtimeName("Unary"), textLiteral(x.Op), g.irValue(x.Operand))
	case ir.Binary:
		return g.binary(x)
	case ir.UnitLiteral:
		return unit()
	case ir.Text:
		var values []ast.Expr
		for _, p := range x.Parts {
			if p.Value != nil {
				values = append(values, runtimeCall("Format", g.irValue(p.Value)))
			} else {
				values = append(values, textLiteral(p.Text))
			}
		}
		return runtimeCall("Text", values...)
	case ir.List:
		if value := g.debugListLiteral(x); value != nil {
			return value
		}
		elements := make([]ast.Expr, len(x.Items))
		for i, item := range x.Items {
			elements[i] = g.irValue(item)
		}
		return address(composite(runtimeName("List"), keyed("Type", g.key(x.Type)), keyed("Items", sliceLiteral(runtimeName("Value"), elements...))))
	case ir.Map:
		entries := make([]ast.Expr, len(x.Entries))
		for i, entry := range x.Entries {
			entries[i] = composite(nil, keyed("Key", g.irValue(entry.Key)), keyed("Value", g.irValue(entry.Value)))
		}
		return call(runtimeName("MapLiteral"), ident("ctx"), g.key(x.Type), sliceLiteral(runtimeName("Entry"), entries...), sourceAt(x.Pos, g.typeScope(x.Type)))
	}
	panic("missing lowering for IR node")
}

// binary lowers an infix operation. Short-circuit operators and builtin
// primitive equality and arithmetic stay typed Go; anything else dispatches
// through the runtime with the operation's site.
func (g *generator) binary(x ir.Binary) ast.Expr {
	if x.Op == "and" || x.Op == "or" {
		op := token.LAND
		if x.Op == "or" {
			op = token.LOR
		}
		return &ast.BinaryExpr{X: paren(g.irScalar(x.Left, "bool")), Op: op, Y: paren(g.irScalar(x.Right, "bool"))}
	}
	if x.Op == "==" || x.Op == "!=" {
		if value := g.primitiveEquality(x); value != nil {
			return value
		}
		return locatedAt(x.Pos, runtimeName("Equality"), ident("ctx"), textLiteral(x.Op), g.irValue(x.Left), g.irValue(x.Right), g.typeScope(x.LeftType))
	}
	if value := g.numericBinary(x); value != nil {
		return value
	}
	return locatedAt(x.Pos, runtimeName("Binary"), textLiteral(x.Op), g.irValue(x.Left), g.irValue(x.Right))
}
