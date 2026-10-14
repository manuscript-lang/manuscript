package lower

import (
	"fmt"
	"go/ast"
	"go/token"
	"math"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

const largeListThreshold = 1024

// literalListData retains immutable scalar input in a typed private array.
// The runtime constructor copies that data into fresh authoritative List backing
// on every evaluation. No source collection or mutable element is globalized.
func (g *generator) literalListData(e ir.List) ast.Expr {
	typ := e.Type
	if g.debugLiterals || len(e.Items) <= largeListThreshold || typ.ID != "@std/List" || len(typ.Args) != 1 {
		return nil
	}
	element := typ.Args[0]
	if element.Kind != "primitive" {
		return nil
	}
	goType, constructor := "", ""
	switch element.ID {
	case "Int":
		goType, constructor = "int64", "NewIntList"
	case "Float":
		goType, constructor = "float64", "NewFloatList"
	case "Bool":
		goType, constructor = "bool", "NewBoolList"
	case "String":
		goType, constructor = "string", "NewStringList"
	default:
		return nil
	}
	values := make([]ast.Expr, len(e.Items))
	var negativeZero []ast.Expr
	for at, item := range e.Items {
		value, signedZero := g.literalDataScalar(item, element.ID)
		if value == nil {
			return nil
		}
		values[at] = value
		if signedZero {
			negativeZero = append(negativeZero, intLiteral(at))
		}
	}
	name := fmt.Sprintf("literalData%d", len(g.literalData)+1)
	array := &ast.ArrayType{Len: intLiteral(len(values)), Elt: ident(goType)}
	g.literalData = append(g.literalData, variable(name, nil, composite(array, values...)))
	if len(negativeZero) != 0 {
		// Go constant zero has no sign. Repair only these private data cells at
		// initialization, using the existing binary64 unary semantics. The index
		// table stays constant; even 100K negative zeros produce a bounded loop.
		zero := g.locatedStatement(syntax.Position{File: "manuscript.generated.go", Line: 1}, define("zero", runtimeCall("FloatValue", runtimeCall("Unary", textLiteral("-"), call(ident("float64"), intLiteral(0))))))
		loop := &ast.RangeStmt{
			Key: ident("_"), Value: ident("index"), Tok: token.DEFINE,
			X:    sliceLiteral(ident("int"), negativeZero...),
			Body: block(assign(index(ident(name), ident("index")), token.ASSIGN, ident("zero"))),
		}
		g.literalData = append(g.literalData, &ast.FuncDecl{Name: ident("init"), Type: functionType(nil, nil), Body: block(zero, loop)})
	}
	return runtimeCall(constructor, g.key(typ), &ast.SliceExpr{X: ident(name)})
}

// Probe eligibility without lowering any expression: abandoned lowered trees
// can strand source markers or captures. Checked identities establish the exact
// representation, and numeric parsing uses the current Int64/binary64 contract.
func (g *generator) literalDataScalar(x ir.Expr, expected string) (ast.Expr, bool) {
	switch x := x.(type) {
	case ir.IntLiteral:
		if expected == "Int" && isPrimitive(x.Type, expected) {
			return signedInteger(strconv.FormatInt(x.Value, 10)), false
		}
	case ir.FloatLiteral:
		if expected == "Float" && isPrimitive(x.Type, expected) {
			return &ast.BasicLit{Kind: token.FLOAT, Value: strconv.FormatFloat(x.Value, 'g', -1, 64)}, x.Value == 0 && math.Signbit(x.Value)
		}
	case ir.BoolLiteral:
		if expected == "Bool" && isPrimitive(x.Type, expected) {
			return ident(strconv.FormatBool(x.Value)), false
		}
	case ir.Text:
		if expected == "String" && isPrimitive(x.Type, expected) {
			var text strings.Builder
			for _, part := range x.Parts {
				if part.Value != nil {
					return nil, false
				}
				text.WriteString(part.Text)
			}
			return textLiteral(text.String()), false
		}

	}
	return nil, false
}
