package golower

import (
	"go/ast"
	"go/token"
	"sort"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

// format renders a value of type t as text, as string interpolation and
// toString do. Scalars use runtime helpers; other types get a generated
// function per type that mirrors their structure.
func (g *gen) format(t *checker.Type, v ast.Expr) ast.Expr {
	t = g.sub(t)
	switch t.ID {
	case "String":
		return v
	case "Int":
		return rtCall("FormatInt", v)
	case "Float":
		return rtCall("FormatFloat", v)
	case "Bool":
		return rtCall("FormatBool", v)
	case "Unit":
		return textLiteral("unit")
	}
	return call(g.formatFunc(t), v, intLiteral(0))
}

// formatFunc is a function of (T, depth int) string.
func (g *gen) formatFunc(t *checker.Type) ast.Expr {
	t = g.sub(t)
	key := "format:" + checker.TypeKey(t)
	return g.helperFunc(key, "format_"+g.nameOf(t), func(name string) ast.Decl {
		params := []*ast.Field{field("v", g.goType(t)), field("depth", ident("int"))}
		body := g.formatBody(t)
		return &ast.FuncDecl{Name: ident(name), Type: functionType(params, ident("string")), Body: block(body...)}
	})
}

// nested formats a part one level deeper, guarding against cyclic values.
func (g *gen) nested(t *checker.Type, v ast.Expr) ast.Expr {
	t = g.sub(t)
	switch t.ID {
	case "String", "Int", "Float", "Bool", "Unit":
		return g.format(t, v)
	}
	return call(g.formatFunc(t), v, binary(ident("depth"), token.ADD, intLiteral(1)))
}

func (g *gen) formatBody(t *checker.Type) []ast.Stmt {
	guard := &ast.IfStmt{Cond: binary(ident("depth"), token.GEQ, intLiteral(64)), Body: block(returned(textLiteral("...")))}
	v := ident("v")
	join := func(parts []ast.Expr, open, close string) ast.Expr {
		var out ast.Expr = textLiteral(open)
		for i, p := range parts {
			if i > 0 {
				out = binary(out, token.ADD, textLiteral(", "))
			}
			out = binary(out, token.ADD, p)
		}
		return binary(out, token.ADD, textLiteral(close))
	}
	switch {
	case isStd(t, "Optional"):
		return []ast.Stmt{guard,
			&ast.IfStmt{Cond: not(selector(v, "Some")), Body: block(returned(textLiteral("Optional.none")))},
			returned(join([]ast.Expr{g.nested(t.Args[0], selector(v, "Val"))}, "Optional.some(", ")"))}
	case isStd(t, "Result"):
		return []ast.Stmt{guard,
			&ast.IfStmt{Cond: selector(v, "Failed"), Body: block(returned(join([]ast.Expr{g.nested(t.Args[1], selector(v, "Err"))}, "Result.error(", ")")))},
			returned(join([]ast.Expr{g.nested(t.Args[0], selector(v, "Val"))}, "Result.ok(", ")"))}
	case isStd(t, "List"):
		elem := t.Args[0]
		fn := closure([]*ast.Field{field("x", g.goType(elem))}, ident("string"), returned(g.nested(elem, ident("x"))))
		return []ast.Stmt{guard, returned(rtCall("FormatList", v, fn))}
	case isStd(t, "Set"):
		elem := t.Args[0]
		fn := closure([]*ast.Field{field("x", g.goType(elem))}, ident("string"), returned(g.nested(elem, ident("x"))))
		return []ast.Stmt{guard, returned(rtCall("FormatSet", v, fn))}
	case isStd(t, "Map"):
		k := closure([]*ast.Field{field("x", g.goType(t.Args[0]))}, ident("string"), returned(g.nested(t.Args[0], ident("x"))))
		val := closure([]*ast.Field{field("x", g.goType(t.Args[1]))}, ident("string"), returned(g.nested(t.Args[1], ident("x"))))
		return []ast.Stmt{guard, returned(rtCall("FormatMap", v, k, val))}
	case t.Kind == "function":
		return []ast.Stmt{returned(textLiteral("[function]"))}
	case isStdType(t) && t.Kind == "native":
		return []ast.Stmt{returned(rtCall("FormatNative", v))}
	case t.Kind == "record":
		fields := checker.Fields(t)
		sort.SliceStable(fields, func(i, j int) bool { return fields[i].Name < fields[j].Name })
		var parts []ast.Expr
		for _, f := range fields {
			parts = append(parts, binary(textLiteral(f.Name+": "), token.ADD, g.nested(f.Type, selector(v, fieldName(f.Name)))))
		}
		return []ast.Stmt{guard, returned(join(parts, t.Name+"(", ")"))}
	case t.Kind == "alternative":
		var clauses []ast.Stmt
		for _, c := range checker.Cases(t) {
			caseType := g.caseType(t, c.Name)
			var result ast.Expr = textLiteral(t.Name + "." + c.Name)
			if len(c.Fields) > 0 {
				var parts []ast.Expr
				for _, f := range c.Fields {
					parts = append(parts, g.nested(f.Type, selector(ident("x"), fieldName(f.Name))))
				}
				result = binary(result, token.ADD, join(parts, "(", ")"))
			}
			clauses = append(clauses, &ast.CaseClause{List: []ast.Expr{caseType}, Body: []ast.Stmt{returned(result)}})
		}
		sw := &ast.TypeSwitchStmt{Assign: &ast.AssignStmt{Lhs: []ast.Expr{ident("x")}, Tok: token.DEFINE, Rhs: []ast.Expr{&ast.TypeAssertExpr{X: v}}}, Body: block(clauses...)}
		trimSwitch(sw, "x")
		return []ast.Stmt{guard, sw, returned(textLiteral(""))}
	case t.Kind == "contract":
		return []ast.Stmt{returned(rtCall("Describe", v, ident("depth")))}
	}
	g.fail("no text form for %s", t)
	return []ast.Stmt{returned(textLiteral(""))}
}
