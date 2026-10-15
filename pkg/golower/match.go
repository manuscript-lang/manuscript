package golower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// matchStatement lowers a match whose value is discarded.
func (g *gen) matchStatement(e *syntax.Expression) []ast.Stmt {
	return g.match(e, "", nil)
}

// matchValue hoists a match used as a value: the result is assigned in each
// arm and read after the switch, so return, break, and continue in arms are
// ordinary Go statements of the enclosing function.
func (g *gen) matchValue(e *syntax.Expression, info *checker.Info) ast.Expr {
	result := g.sub(info.Type)
	if result.ID == "Unit" || result.ID == "Never" {
		g.fn.pre = append(g.fn.pre, g.match(e, "", nil)...)
		return g.unit()
	}
	name := g.temp()
	g.fn.pre = append(g.fn.pre, varDecl(name, g.goType(result), nil))
	g.fn.pre = append(g.fn.pre, g.match(e, name, result)...)
	return ident(name)
}

// match lowers e to a Go switch. When result names a variable, each arm
// assigns its value there.
func (g *gen) match(e *syntax.Expression, result string, resultType *checker.Type) []ast.Stmt {
	scrutinee := g.info(e.Left).Type
	value := g.expr(e.Left)
	tmp := g.temp()
	out := []ast.Stmt{define(tmp, value)}
	g.fn.switches++
	defer func() { g.fn.switches-- }()
	var clauses []ast.Stmt
	var tagged bool
	switch {
	case isStd(scrutinee, "Optional") || isStd(scrutinee, "Result"):
		for i := range e.Arms {
			clauses = append(clauses, g.resultClause(scrutinee, tmp, &e.Arms[i], result, resultType))
		}
	case scrutinee.Kind == "contract":
		tagged = true
		for i := range e.Arms {
			clauses = append(clauses, g.contractClause(scrutinee, tmp, &e.Arms[i], result, resultType))
		}
	default:
		tagged = true
		for i := range e.Arms {
			clauses = append(clauses, g.caseClause(scrutinee, tmp, &e.Arms[i], result, resultType))
		}
	}
	if tagged {
		out = append(out, &ast.TypeSwitchStmt{
			Assign: &ast.AssignStmt{Lhs: []ast.Expr{ident("s" + tmp)}, Tok: token.DEFINE, Rhs: []ast.Expr{&ast.TypeAssertExpr{X: ident(tmp)}}},
			Body:   block(clauses...),
		})
		out = g.useSwitchVariable(out, "s"+tmp)
		return out
	}
	return append(out, &ast.SwitchStmt{Body: block(clauses...)})
}

// useSwitchVariable keeps `switch s := x.(type)` valid when no clause reads s.
func (g *gen) useSwitchVariable(out []ast.Stmt, name string) []ast.Stmt {
	sw := out[len(out)-1].(*ast.TypeSwitchStmt)
	used := false
	ast.Inspect(sw.Body, func(n ast.Node) bool {
		if id, ok := n.(*ast.Ident); ok && id.Name == name {
			used = true
		}
		return !used
	})
	if !used {
		sw.Assign = &ast.ExprStmt{X: &ast.TypeAssertExpr{X: sw.Assign.(*ast.AssignStmt).Rhs[0].(*ast.TypeAssertExpr).X}}
	}
	return out
}

// armBody lowers an arm's statements and final value.
func (g *gen) armBody(a *syntax.Arm, result string, resultType *checker.Type) []ast.Stmt {
	body := g.body(a.Body, nil)
	if a.Value == nil {
		return body
	}
	saved := g.fn.pre
	g.fn.pre = nil
	var value ast.Expr
	if result != "" {
		value = g.valueAs(a.Value, resultType)
	} else {
		value = g.expr(a.Value)
	}
	body = append(body, g.fn.pre...)
	g.fn.pre = saved
	if result != "" {
		return append(body, assign(ident(result), token.ASSIGN, value))
	}
	if g.statementCall(value) {
		return append(body, evaluated(value))
	}
	return append(body, discard(value))
}

// bindPayload declares the arm's payload names from positional fields.
func (g *gen) bindPayload(a *syntax.Arm, fields []checker.Param, source ast.Expr) []ast.Stmt {
	var out []ast.Stmt
	for i, b := range g.program.ArmBindingsFor(a) {
		if b == nil || i >= len(fields) {
			continue
		}
		name := g.bindingName(b)
		out = append(out, define(name, selector(source, fieldName(fields[i].Name))))
		out = append(out, g.keepUnused(b)...)
	}
	return out
}

// caseClause is the type-switch clause of an alternative arm.
func (g *gen) caseClause(t *checker.Type, tmp string, a *syntax.Arm, result string, resultType *checker.Type) ast.Stmt {
	t = g.sub(t)
	clause := &ast.CaseClause{}
	var fields []checker.Param
	if a.Path.Text != "_" {
		clause.List = []ast.Expr{g.caseType(t, a.Path.Text)}
		for _, c := range checker.Cases(t) {
			if c.Name == a.Path.Text {
				fields = c.Fields
			}
		}
	}
	clause.Body = append(g.bindPayload(a, fields, ident("s"+tmp)), g.armBody(a, result, resultType)...)
	return clause
}

// caseType is the Go struct of a case.
func (g *gen) caseType(t *checker.Type, name string) ast.Expr {
	if isStdType(t) {
		var args []ast.Expr
		for _, a := range t.Args {
			args = append(args, g.goType(a))
		}
		return generic(rtName(typeBase(t)+"_"+sanitize(name)), args...)
	}
	return ident(g.caseName(g.declare(t), name))
}

// resultClause is the clause of an Optional or Result arm.
func (g *gen) resultClause(t *checker.Type, tmp string, a *syntax.Arm, result string, resultType *checker.Type) ast.Stmt {
	clause := &ast.CaseClause{}
	var body []ast.Stmt
	payload := func(field string) {
		if bs := g.program.ArmBindingsFor(a); len(bs) > 0 && bs[0] != nil {
			name := g.bindingName(bs[0])
			body = append(body, define(name, selector(ident(tmp), field)))
			body = append(body, g.keepUnused(bs[0])...)
		}
	}
	switch a.Path.Text {
	case "some":
		clause.List = []ast.Expr{selector(ident(tmp), "Some")}
		payload("Val")
	case "none":
		clause.List = []ast.Expr{not(selector(ident(tmp), "Some"))}
	case "ok":
		clause.List = []ast.Expr{not(selector(ident(tmp), "Failed"))}
		payload("Val")
	case "error":
		clause.List = []ast.Expr{selector(ident(tmp), "Failed")}
		payload("Err")
	}
	clause.Body = append(body, g.armBody(a, result, resultType)...)
	return clause
}
