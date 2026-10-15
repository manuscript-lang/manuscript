package golower

import (
	"go/ast"
	"go/token"
	"strings"
	"unicode"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

// typeDecl is one Go type the program declares: a record struct, the sealed
// interface and case structs of a sum type, or the interface of a contract.
// Generic declarations get one typeDecl per instantiation.
type typeDecl struct {
	node
	key  string
	name string
	t    *checker.Type
}

func isStd(t *checker.Type, name string) bool { return t != nil && t.ID == "@std/"+name }
func isStdType(t *checker.Type) bool          { return t != nil && strings.HasPrefix(t.ID, "@std/") }

// goKeywords are the Go keywords and predeclared names a Manuscript name must
// not shadow when it becomes a struct field or a case suffix.
var goKeywords = map[string]bool{
	"break": true, "case": true, "chan": true, "const": true, "continue": true, "default": true,
	"defer": true, "else": true, "fallthrough": true, "for": true, "func": true, "go": true,
	"goto": true, "if": true, "import": true, "interface": true, "map": true, "package": true,
	"range": true, "return": true, "select": true, "struct": true, "switch": true, "type": true, "var": true,
}

// fieldName is the exported Go field for a Manuscript field: generated user
// types and the runtime's generated standard types name fields alike, so code
// reads either.
func fieldName(name string) string { return camel(name) }

// scalarGo is the Go spelling of a primitive type, or "".
func scalarGo(t *checker.Type) string {
	if t == nil || t.Kind != "primitive" {
		return ""
	}
	switch t.ID {
	case "Int":
		return "int64"
	case "Float":
		return "float64"
	case "Bool":
		return "bool"
	case "String":
		return "string"
	}
	return ""
}

// valueNatives are immutable standard types the runtime represents as plain Go
// values: nanosecond counts, not pointers to them.
var valueNatives = map[string]bool{"@std/Duration": true, "@std/Instant": true, "@std/Timestamp": true}

// isReference reports whether t lowers to a Go pointer: a type whose holders
// observe each other's mutation or identity. Everything else is a value and is
// never mutated after construction. See
// documentation/contributing/go-lowering-representation.md.
func isReference(t *checker.Type) bool {
	switch {
	case t == nil:
		return false
	case isStd(t, "List"), isStd(t, "Map"), isStd(t, "Set"):
		return true
	case valueNatives[t.ID]:
		return false
	case t.Kind == "record", t.Kind == "native":
		return true
	}
	return false
}

// goType is the single Go type of a Manuscript type. Type variables must have
// been substituted: monomorphization leaves none.
func (g *gen) goType(t *checker.Type) ast.Expr {
	t = g.sub(t)
	if t == nil {
		g.fail("lowering reached a type with no checked identity")
		return ident("struct{}")
	}
	if s := scalarGo(t); s != "" {
		return ident(s)
	}
	switch {
	case t.Kind == "primitive":
		return rtName("Unit")
	case t.Kind == "variable" && g.inRuntime:
		return ident(t.Name)
	case t.Kind == "variable":
		g.fail("type variable %s was not instantiated; this is a Manuscript lowering bug", t.Name)
		return ident("struct{}")
	case t.Kind == "function":
		return g.funcType(t)
	case isStd(t, "Optional"):
		return generic(rtName("Option"), g.goType(t.Args[0]))
	case isStd(t, "Result"):
		return generic(rtName("Result"), g.goType(t.Args[0]), g.goType(t.Args[1]))
	case isStd(t, "List"):
		return pointerTo(generic(rtName("List"), g.goType(t.Args[0])))
	case isStd(t, "Map"):
		return pointerTo(generic(rtName("Map"), g.goType(t.Args[0]), g.goType(t.Args[1])))
	case isStd(t, "Set"):
		return pointerTo(generic(rtName("Set"), g.goType(t.Args[0])))
	case isStdType(t):
		return g.stdType(t)
	}
	decl := g.declare(t)
	if isReference(t) {
		return pointerTo(ident(decl.name))
	}
	return ident(decl.name)
}

// stdType names a standard type declared by the runtime. Standard records are
// pointers to their runtime struct; sum types and contracts are interfaces.
func (g *gen) stdType(t *checker.Type) ast.Expr {
	name := rtName(strings.TrimPrefix(t.ID, "@std/"))
	var args []ast.Expr
	for _, a := range t.Args {
		args = append(args, g.goType(a))
	}
	typ := generic(name, args...)
	if isReference(t) {
		return pointerTo(typ)
	}
	return typ
}

// funcType is the Go function type of a Manuscript function type. Labels are
// not part of the Go type; every function takes the execution first.
func (g *gen) funcType(t *checker.Type) *ast.FuncType {
	params := []*ast.Field{field("ctx", pointerTo(rtName("Execution")))}
	for i, p := range t.Params {
		params = append(params, field("a"+itoa(i), g.goType(p.Type)))
	}
	return functionType(params, g.goType(t.Result))
}

func itoa(i int) string { return intLiteral(i).(*ast.BasicLit).Value }

// declare registers the Go declarations for a user record, sum type, or
// contract type, instantiated at t's arguments, and returns them. The first
// unit to ask builds the declaration; the others only name it.
func (g *gen) declare(t *checker.Type) *typeDecl {
	t = g.sub(t)
	key := checker.TypeKey(t)
	name := g.typeName(t)
	g.mu.Lock()
	d := g.types[key]
	created := d == nil
	if created {
		d = &typeDecl{key: key, t: t, name: name}
		d.typ = true
		g.types[key] = d
	}
	g.mu.Unlock()
	g.touch(&d.node)
	if !created {
		return d
	}
	g.building(&d.node, func() {
		switch t.Kind {
		case "record":
			d.decl = g.recordDecl(d)
		case "alternative":
			d.decl = g.alternativeDecl(d)
		case "contract":
			d.decl = g.contractDecl(d)
		default:
			g.fail("no Go type for %s (%s)", t.String(), t.Kind)
		}
	})
	return d
}

// typeName makes a unique readable Go name: the source name, then the
// instantiation's argument names.
func (g *gen) typeName(t *checker.Type) string {
	return g.claim(g.nameOf(t), checker.TypeKey(t))
}

func (g *gen) nameOf(t *checker.Type) string {
	t = g.sub(t)
	var b strings.Builder
	b.WriteString(sanitize(t.Name))
	if g.dup[sanitize(t.Name)] {
		b.WriteString("_")
		b.WriteString(shortHash(t.ID))
	}
	for _, a := range t.Args {
		b.WriteString("_")
		b.WriteString(g.nameOf(a))
	}
	return b.String()
}

var reserved = map[string]bool{"main": true, "init": true, "rt": true, "os": true, "ctx": true}

func sanitize(name string) string {
	var b strings.Builder
	for _, r := range name {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || r == '_' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// caseName is the Go struct of one case of a sum type.
func (g *gen) caseName(d *typeDecl, c string) string { return d.name + "_" + sanitize(c) }

func (g *gen) recordDecl(d *typeDecl) []ast.Decl {
	var fields []*ast.Field
	for _, f := range checker.Fields(d.t) {
		fields = append(fields, field(fieldName(f.Name), g.goType(f.Type)))
	}
	return []ast.Decl{typeSpec(d.name, &ast.StructType{Fields: &ast.FieldList{List: fields}})}
}

// alternativeDecl declares a sealed interface and one struct per case. The
// marker method keeps other types from satisfying the interface.
func (g *gen) alternativeDecl(d *typeDecl) []ast.Decl {
	marker := "is" + d.name
	decls := []ast.Decl{typeSpec(d.name, &ast.InterfaceType{Methods: &ast.FieldList{List: []*ast.Field{
		{Names: []*ast.Ident{ident(marker)}, Type: functionType(nil, nil)},
	}}})}
	for _, c := range checker.Cases(d.t) {
		var fields []*ast.Field
		for _, f := range c.Fields {
			fields = append(fields, field(fieldName(f.Name), g.goType(f.Type)))
		}
		name := g.caseName(d, c.Name)
		decls = append(decls, typeSpec(name, &ast.StructType{Fields: &ast.FieldList{List: fields}}),
			&ast.FuncDecl{
				Recv: &ast.FieldList{List: []*ast.Field{{Type: ident(name)}}},
				Name: ident(marker), Type: functionType(nil, nil), Body: block(),
			})
	}
	return decls
}

func typeSpec(name string, typ ast.Expr) ast.Decl {
	return &ast.GenDecl{Tok: token.TYPE, Specs: []ast.Spec{&ast.TypeSpec{Name: ident(name), Type: typ}}}
}
