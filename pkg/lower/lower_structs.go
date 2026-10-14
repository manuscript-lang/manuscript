package lower

import (
	"go/ast"
	"go/token"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A nongeneric source record is emitted as a Go struct with typed scalar
// fields. Code that knows a value's record type reads and writes fields
// through the struct's accessors; the runtime's generic operations reach it
// through rt.Struct. Standard records and generic records keep the map-backed
// rt.Record, which library code constructs and inspects directly.
type structType struct {
	name   string // Go type name
	key    string // runtime type key
	fields []structField
}

type structField struct {
	name   string // source name
	scalar string // Go scalar type, "" for Value
}

func (s *structType) field(name string) *structField {
	for i := range s.fields {
		if s.fields[i].name == name {
			return &s.fields[i]
		}
	}
	return nil
}

func (f structField) goType() ast.Expr {
	if f.scalar != "" {
		return ident(f.scalar)
	}
	return runtimeName("Value")
}

func fieldName(name string) string { return "f_" + name }

// planStructs decides which declared records become Go structs.
func (g *generator) planStructs() {
	g.structs = map[string]*structType{}
	for _, module := range g.program.Modules {
		for _, d := range module.Declarations {
			if d.Kind != syntax.KindRecord {
				continue
			}
			s := g.program.Symbol(module.File, d.Name)
			if s == nil || s.Type == nil || s.Native != "" || len(s.Variables) != 0 || strings.HasPrefix(s.Type.ID, "@std/") {
				continue
			}
			st := &structType{name: "record_" + s.ID, key: checker.TypeKey(s.Type)}
			for _, f := range checker.Fields(s.Type) {
				st.fields = append(st.fields, structField{name: f.Name, scalar: primitiveEqualityType(f.Type)})
			}
			g.structs[st.key] = st
			g.structOrder = append(g.structOrder, st)
		}
	}
}

// structFor returns the Go struct for a record type, or nil.
func (g *generator) structFor(t *checker.Type) *structType {
	if t == nil || t.Def == nil || t.Kind != syntax.KindRecord || len(t.Args) != 0 {
		return nil
	}
	return g.structs[checker.TypeKey(t)]
}

// structDeclarations emits every planned struct with its accessors and the
// rt.Struct methods.
func (g *generator) structDeclarations() []ast.Decl {
	var decls []ast.Decl
	for _, st := range g.structOrder {
		var fields []*ast.Field
		var names []ast.Expr
		for _, f := range st.fields {
			fields = append(fields, field(fieldName(f.name), f.goType()))
			names = append(names, textLiteral(f.name))
		}
		namesVar := st.name + "_names"
		decls = append(decls,
			&ast.GenDecl{Tok: token.TYPE, Specs: []ast.Spec{&ast.TypeSpec{Name: ident(st.name), Type: &ast.StructType{Fields: &ast.FieldList{List: fields}}}}},
			variable(namesVar, nil, sliceLiteral(ident("string"), names...)),
		)
		receiver := &ast.FieldList{List: []*ast.Field{field("r", &ast.StarExpr{X: ident(st.name)})}}
		method := func(name string, params []*ast.Field, result ast.Expr, body ...ast.Stmt) {
			decls = append(decls, &ast.FuncDecl{Recv: receiver, Name: ident(name), Type: functionType(params, result), Body: block(body...)})
		}
		method("StructType", nil, ident("string"), returned(textLiteral(st.key)))
		method("StructNames", nil, sliceOf(ident("string")), returned(ident(namesVar)))
		var gets, sets []ast.Stmt
		for i, f := range st.fields {
			slot := address(selector(ident("r"), fieldName(f.name)))
			gets = append(gets, &ast.CaseClause{List: []ast.Expr{intLiteral(i)}, Body: []ast.Stmt{returned(runtimeCall("ReadField", ident("r"), slot))}})
			var value ast.Expr = ident("value")
			if f.scalar != "" {
				value = unbox(value, f.scalar)
			}
			sets = append(sets, &ast.CaseClause{List: []ast.Expr{intLiteral(i)}, Body: []ast.Stmt{evaluated(runtimeCall("WriteField", ident("r"), slot, value))}})
			// The unshared fast path is a plain field access small enough for Go to
			// inline; the locked path stays out of line.
			shared := &ast.IfStmt{Cond: runtimeCall("SharedFields")}
			method("slowGet_"+f.name, nil, f.goType(), returned(runtimeCall("ReadField", ident("r"), slot)))
			method("slowSet_"+f.name, []*ast.Field{field("value", f.goType())}, nil, evaluated(runtimeCall("WriteField", ident("r"), slot, ident("value"))))
			getShared, setShared := *shared, *shared
			getShared.Body = block(returned(call(selector(ident("r"), "slowGet_"+f.name))))
			setShared.Body = block(evaluated(call(selector(ident("r"), "slowSet_"+f.name), ident("value"))), &ast.ReturnStmt{})
			method("Get_"+f.name, nil, f.goType(), &getShared, returned(selector(ident("r"), fieldName(f.name))))
			method("Set_"+f.name, []*ast.Field{field("value", f.goType())}, nil, &setShared, assign(selector(ident("r"), fieldName(f.name)), token.ASSIGN, ident("value")))
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
	return g.structPointer(st, g.expression(e))
}

func (g *generator) structPointer(st *structType, value ast.Expr) ast.Expr {
	return &ast.TypeAssertExpr{X: value, Type: &ast.StarExpr{X: ident(st.name)}}
}

// structField resolves a source field access on a record-typed operand.
func (g *generator) structFieldOf(e *syntax.Expression) (*structType, *structField) {
	st := g.structFor(g.program.Info(e.Left).Type)
	if st == nil {
		return nil, nil
	}
	if f := st.field(e.Text); f != nil {
		return st, f
	}
	return nil, nil
}

// constructStruct lowers a record construction, or returns nil when the call
// does not name every field exactly once.
func (g *generator) constructStruct(st *structType, args []syntax.Argument) ast.Expr {
	if len(args) != len(st.fields) {
		return nil
	}
	seen := map[string]bool{}
	for _, a := range args {
		if st.field(a.Name) == nil || seen[a.Name] {
			return nil
		}
		seen[a.Name] = true
	}
	var elements []ast.Expr
	for _, a := range args {
		f := st.field(a.Name)
		var value ast.Expr
		if f.scalar != "" {
			value = g.scalar(a.Value, f.scalar)
		} else {
			value = g.argumentValue(a)
		}
		elements = append(elements, keyed(fieldName(a.Name), sourceAt(a.Pos, value)))
	}
	return call(runtimeName("Value"), address(composite(ident(st.name), elements...)))
}
