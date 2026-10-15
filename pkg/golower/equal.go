package golower

import (
	"go/ast"
	"go/token"
	"sort"

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
	return scalarGo(t) != "" || t.ID == "Unit"
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
	if g.localEquality() {
		key += "@" + g.module
	}
	if d := g.helpers[key]; d != "" {
		return ident(d)
	}
	name := g.unique("equal_" + g.nameOf(t))
	if g.helpers == nil {
		g.helpers = map[string]string{}
	}
	g.helpers[key] = name
	body := g.equalBody(t)
	params := []*ast.Field{field("ctx", pointerTo(rtName("Execution"))), field("a", g.goType(t)), field("b", g.goType(t))}
	g.decls = append(g.decls, &ast.FuncDecl{Name: ident(name), Type: functionType(params, ident("bool")), Body: block(body...)})
	return ident(name)
}

// localEquality reports whether some module declares an extension Equal
// implementation, which makes the chosen equality depend on the module.
func (g *gen) localEquality() bool {
	if g.localEq == 0 {
		g.localEq = -1
		for _, m := range g.program.Methods {
			if m.Local && m.Contract != nil && m.Contract.ID == "@std/Equal" {
				g.localEq = 1
			}
		}
	}
	return g.localEq > 0
}

func (g *gen) equalBody(t *checker.Type) []ast.Stmt {
	// An explicit implementation overrides structure.
	for _, m := range g.program.ResolveMethods(g.module, t, "equals") {
		if m.Contract != nil && m.Contract.ID == "@std/Equal" && m.Native == "" {
			f := g.methodFunction(m, t)
			return []ast.Stmt{returned(call(ident(f.name), ident("ctx"), ident("a"), ident("b")))}
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
	case isStdType(t):
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
			body = append(body, &ast.AssignStmt{Lhs: []ast.Expr{ident("y"), ident("ok")}, Tok: token.DEFINE, Rhs: []ast.Expr{&ast.TypeAssertExpr{X: b, Type: caseType}}})
			cond := ast.Expr(ident("ok"))
			for _, f := range c.Fields {
				cond = binary(cond, token.LAND, g.equal(f.Type, selector(ident("x"), fieldName(f.Name)), selector(ident("y"), fieldName(f.Name)), nil))
			}
			body = append(body, returned(cond))
			clauses = append(clauses, &ast.CaseClause{List: []ast.Expr{caseType}, Body: body})
		}
		sw := &ast.TypeSwitchStmt{Assign: &ast.AssignStmt{Lhs: []ast.Expr{ident("x")}, Tok: token.DEFINE, Rhs: []ast.Expr{&ast.TypeAssertExpr{X: a}}}, Body: block(clauses...)}
		return []ast.Stmt{sw, returned(ident("false"))}
	}
	g.fail("no equality for %s", t)
	return []ast.Stmt{returned(ident("false"))}
}

// hasherFor is the key strategy of a Map or Set over key. nil selects Go's
// built-in comparison, which is Manuscript's key equality for scalars and for
// record references.
func (g *gen) hasherFor(key *checker.Type) ast.Expr {
	return ident("nil")
}
