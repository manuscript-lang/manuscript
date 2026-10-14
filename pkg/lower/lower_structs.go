package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A nongeneric source record is emitted as a Go struct with typed scalar
// fields. Code that knows a value's record type reads and writes fields
// through the struct's accessors; the runtime's generic operations reach it
// through rt.Struct. Standard records and generic records keep the map-backed
// rt.Record, which library code constructs and inspects directly.
type structType = ir.Record
type structField = ir.RecordField

func structGoType(f structField) ast.Expr {
	if f.Primitive != "" {
		return ident(f.Primitive)
	}
	return runtimeName("Value")
}
func fieldName(name string) string { return "f_" + name }
func (g *generator) planStructs()  { g.structs = g.ir.Records; g.structOrder = g.ir.RecordOrder }

// structDeclarations emits every planned struct with its accessors and the
// rt.Struct methods.
func (g *generator) structDeclarations() []ast.Decl {
	var decls []ast.Decl
	for _, st := range g.structOrder {
		var fields []*ast.Field
		var names []ast.Expr
		for _, f := range st.Fields {
			fields = append(fields, field(fieldName(f.Name), structGoType(f)))
			names = append(names, textLiteral(f.Name))
		}
		namesVar := st.Name + "_names"
		decls = append(decls,
			&ast.GenDecl{Tok: token.TYPE, Specs: []ast.Spec{&ast.TypeSpec{Name: ident(st.Name), Type: &ast.StructType{Fields: &ast.FieldList{List: fields}}}}},
			variable(namesVar, nil, sliceLiteral(ident("string"), names...)),
		)
		receiver := &ast.FieldList{List: []*ast.Field{field("r", &ast.StarExpr{X: ident(st.Name)})}}
		method := func(name string, params []*ast.Field, result ast.Expr, body ...ast.Stmt) {
			decls = append(decls, &ast.FuncDecl{Recv: receiver, Name: ident(name), Type: functionType(params, result), Body: block(body...)})
		}
		method("StructType", nil, ident("string"), returned(textLiteral(st.Key)))
		method("StructNames", nil, sliceOf(ident("string")), returned(ident(namesVar)))
		var gets, sets []ast.Stmt
		for i, f := range st.Fields {
			slot := address(selector(ident("r"), fieldName(f.Name)))
			gets = append(gets, &ast.CaseClause{List: []ast.Expr{intLiteral(i)}, Body: []ast.Stmt{returned(runtimeCall("ReadField", ident("r"), slot))}})
			var value ast.Expr = ident("value")
			if f.Primitive != "" {
				value = scalarExtract(f.Type, value)
			}
			sets = append(sets, &ast.CaseClause{List: []ast.Expr{intLiteral(i)}, Body: []ast.Stmt{evaluated(runtimeCall("WriteField", ident("r"), slot, value))}})
			var read ast.Expr = runtimeCall("ReadField", ident("r"), slot)
			method("Get_"+f.Name, nil, structGoType(f), returned(read))
			method("Set_"+f.Name, []*ast.Field{field("value", structGoType(f))}, nil, evaluated(runtimeCall("WriteField", ident("r"), slot, ident("value"))))
		}
		gets = append(gets, &ast.CaseClause{Body: []ast.Stmt{returned(ident("nil"))}})
		sets = append(sets, &ast.CaseClause{})
		method("StructGet", []*ast.Field{field("index", ident("int"))}, runtimeName("Value"), &ast.SwitchStmt{Tag: ident("index"), Body: block(gets...)})
		method("StructSet", []*ast.Field{field("index", ident("int")), field("value", runtimeName("Value"))}, nil, &ast.SwitchStmt{Tag: ident("index"), Body: block(sets...)})
		method("StructClone", nil, runtimeName("Struct"), returned(runtimeCall("CopyStruct", ident("r"))))
	}
	return decls
}

// structOperand returns the receiver of a field access as the Go struct pointer.
func (g *generator) structOperand(st *structType, e *syntax.Expression) ast.Expr {
	return &ast.TypeAssertExpr{X: g.expression(e), Type: &ast.StarExpr{X: ident(st.Name)}}
}

// structField resolves a source field access on a record-typed operand.
func (g *generator) structFieldOf(e *syntax.Expression) (*structType, *structField) {
	if x := g.ir.Fields[e]; x != nil {
		return x.Record, x.Field
	}
	return nil, nil
}
func (g *generator) constructStruct(st *structType, args []ir.Argument) ast.Expr {
	var elements []ast.Expr
	for _, a := range args {
		elements = append(elements, keyed(fieldName(a.Name), sourceAt(a.Pos, g.callArgument(a))))
	}
	return call(runtimeName("Value"), address(composite(ident(st.Name), elements...)))
}
