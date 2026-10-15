package golower

import (
	"go/ast"
	"go/token"
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Equality is structural unless a visible `impl Equal` says otherwise. Types
// Go compares with == use it directly; every other type gets a generated
// function that compares field by field, so equality costs what hand-written
// comparison would.

// goComparable reports whether == on the Go representation of t is Manuscript
// equality: scalars and strings.
func goComparable(t *checker.Type) bool {
	return scalarGo(t) != "" || t.ID == "Unit" || t.ID == "@std/Duration" || t.ID == "@std/Timestamp"
}

// equal compares a and b, both values of type t.
func (g *gen) equal(t *checker.Type, a, b ast.Expr, at *syntax.Expression) ast.Expr {
	t = g.sub(t)
	if t.ID == "Unit" {
		return ident("true")
	}
	if goComparable(t) {
		return binary(a, token.EQL, b)
	}
	return call(g.equalFunc(t), ident("ctx"), a, b)
}

// equalFunc is an expression of type func(*rt.Execution, T, T) bool.
func (g *gen) equalFunc(t *checker.Type) ast.Expr {
	t = g.sub(t)
	if goComparable(t) {
		return generic(rtName("Equals"), g.goType(t))
	}
	key := "equal:" + checker.TypeKey(t)
	if g.localEq {
		key += "@" + g.module
	}
	return g.helperFunc(key, "equal_"+g.nameOf(t), func(name string) ast.Decl {
		body := g.equalBody(t)
		params := []*ast.Field{field("ctx", pointerTo(rtName("Execution"))), field("a", g.goType(t)), field("b", g.goType(t))}
		return &ast.FuncDecl{Name: ident(name), Type: functionType(params, ident("bool")), Body: block(body...)}
	})
}

// helperFunc is the generated function for key, built once by the first unit
// that needs it. A module-scoped key makes the name module-scoped too.
func (g *gen) helperFunc(key, base string, build func(name string) ast.Decl) ast.Expr {
	name := base
	if strings.Contains(key, "@") {
		name += "_" + shortHash(key)
	}
	name = g.claim(name, key)
	g.mu.Lock()
	h := g.helpers[key]
	created := h == nil
	if created {
		h = &helper{name: name}
		g.helpers[key] = h
	}
	g.mu.Unlock()
	g.touch(&h.node)
	if created {
		g.building(&h.node, func() { h.decl = []ast.Decl{build(name)} })
	}
	return ident(name)
}

func (g *gen) equalBody(t *checker.Type) []ast.Stmt {
	// An explicit implementation overrides structure.
	for _, m := range g.program.ResolveMethods(g.module, t, "equals") {
		if m.Contract != nil && m.Contract.ID == "@std/Equal" && m.Native == "" {
			f := g.methodFunction(m, t)
			return []ast.Stmt{returned(call(ident(f.name), ident("ctx"), ident("a"), g.viewOf(ident("b"), t, m.Contract)))}
		}
	}
	a, b := ident("a"), ident("b")
	switch {
	case isStd(t, "Optional"):
		eq := g.equalFunc(t.Args[0])
		return []ast.Stmt{returned(binary(binary(selector(a, "Some"), token.EQL, selector(b, "Some")), token.LAND,
			paren(binary(not(selector(a, "Some")), token.LOR, call(eq, ident("ctx"), selector(a, "Val"), selector(b, "Val"))))))}
	case isStd(t, "Result"):
		ok, bad := g.equalFunc(t.Args[0]), g.equalFunc(t.Args[1])
		return []ast.Stmt{
			&ast.IfStmt{Cond: binary(selector(a, "Failed"), token.NEQ, selector(b, "Failed")), Body: block(returned(ident("false")))},
			&ast.IfStmt{Cond: selector(a, "Failed"), Body: block(returned(call(bad, ident("ctx"), selector(a, "Err"), selector(b, "Err"))))},
			returned(call(ok, ident("ctx"), selector(a, "Val"), selector(b, "Val"))),
		}
	case isStd(t, "List"):
		return []ast.Stmt{returned(rtCall("ListEqual", ident("ctx"), a, b, g.equalFunc(t.Args[0])))}
	case isStd(t, "Set"):
		return []ast.Stmt{returned(rtCall("SetEqual", ident("ctx"), a, b))}
	case isStd(t, "Map"):
		return []ast.Stmt{returned(rtCall("MapEqual", ident("ctx"), a, b, g.equalFunc(t.Args[1])))}
	case t.Kind == "function":
		return []ast.Stmt{returned(ident("false"))}
	case isStdType(t) && t.Kind == "native":
		return []ast.Stmt{returned(call(selector(a, "Equal"), ident("ctx"), b))}
	case t.Kind == "record":
		stmts := []ast.Stmt{&ast.IfStmt{Cond: binary(a, token.EQL, b), Body: block(returned(ident("true")))}}
		for _, f := range checker.Fields(t) {
			stmts = append(stmts, &ast.IfStmt{
				Cond: not(g.equal(f.Type, selector(a, fieldName(f.Name)), selector(b, fieldName(f.Name)), nil)),
				Body: block(returned(ident("false"))),
			})
		}
		return append(stmts, returned(ident("true")))
	case t.Kind == "alternative":
		var clauses []ast.Stmt
		cases := checker.Cases(t)
		sort.SliceStable(cases, func(i, j int) bool { return false })
		for _, c := range cases {
			caseType := g.caseType(t, c.Name)
			var body []ast.Stmt
			other := "y"
			if len(c.Fields) == 0 {
				other = "_"
			}
			body = append(body, &ast.AssignStmt{Lhs: []ast.Expr{ident(other), ident("ok")}, Tok: token.DEFINE, Rhs: []ast.Expr{&ast.TypeAssertExpr{X: b, Type: caseType}}})
			cond := ast.Expr(ident("ok"))
			for _, f := range c.Fields {
				cond = binary(cond, token.LAND, g.equal(f.Type, selector(ident("x"), fieldName(f.Name)), selector(ident("y"), fieldName(f.Name)), nil))
			}
			body = append(body, returned(cond))
			clauses = append(clauses, &ast.CaseClause{List: []ast.Expr{caseType}, Body: body})
		}
		sw := &ast.TypeSwitchStmt{Assign: &ast.AssignStmt{Lhs: []ast.Expr{ident("x")}, Tok: token.DEFINE, Rhs: []ast.Expr{&ast.TypeAssertExpr{X: a}}}, Body: block(clauses...)}
		trimSwitch(sw, "x")
		return []ast.Stmt{sw, returned(ident("false"))}
	}
	g.fail("no equality for %s", t)
	return []ast.Stmt{returned(ident("false"))}
}
