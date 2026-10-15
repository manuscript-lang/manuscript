package golower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A contract value is a Go interface value. Its dynamic type is a generated
// view struct, one per (implementing type, contract), that holds the receiver
// and forwards each operation to the implementation, so a view keeps its
// concrete receiver exactly as the language requires.

// contractDecl declares a user contract as a Go interface.
func (g *gen) contractDecl(d *typeDecl) []ast.Decl {
	var methods []*ast.Field
	for _, op := range g.operations(d.t) {
		methods = append(methods, &ast.Field{Names: []*ast.Ident{ident(camel(op.Name))}, Type: g.operationType(op.Type)})
	}
	return []ast.Decl{typeSpec(d.name, &ast.InterfaceType{Methods: &ast.FieldList{List: methods}})}
}

// operations are the contract's operations with the contract's own type
// arguments applied.
func (g *gen) operations(contract *checker.Type) []checker.Operation {
	if contract.Def == nil {
		return nil
	}
	sub := map[string]*checker.Type{}
	for i, v := range contract.Def.Variables {
		if i < len(contract.Args) {
			sub[v.ID] = contract.Args[i]
		}
	}
	var ops []checker.Operation
	for _, op := range contract.Def.Operations {
		op.Type = checker.Sub(op.Type, sub)
		ops = append(ops, op)
	}
	return ops
}

// operationType is the Go method type of an operation.
func (g *gen) operationType(t *checker.Type) *ast.FuncType {
	params := []*ast.Field{field("ctx", pointerTo(rtName("Execution")))}
	for i, p := range t.Params {
		params = append(params, field("a"+itoa(i), g.goType(p.Type)))
	}
	return functionType(params, g.goType(t.Result))
}

// contractType is the Go interface of a contract type.
func (g *gen) contractType(t *checker.Type) ast.Expr {
	if isStdType(t) {
		return g.stdType(t)
	}
	return ident(g.declare(t).name)
}

// viewOf wraps value, of the concrete type from, as a value of contract.
func (g *gen) viewOf(value ast.Expr, from, contract *checker.Type) ast.Expr {
	from, contract = g.sub(from), g.sub(contract)
	if from.ID == contract.ID || from.Kind == "contract" {
		return value
	}
	view := g.view(from, contract)
	return composite(ident(view), keyed("self", value))
}

// view declares the struct that adapts from to contract.
func (g *gen) view(from, contract *checker.Type) string {
	key := "view:" + checker.TypeKey(contract) + ":" + checker.TypeKey(from)
	name := g.claim(g.nameOf(contract)+"_"+g.nameOf(from), key)
	g.mu.Lock()
	d := g.types[key]
	created := d == nil
	if created {
		d = &typeDecl{key: key, name: name, t: from}
		d.typ = true
		g.types[key] = d
	}
	g.mu.Unlock()
	g.touch(&d.node)
	if !created {
		return d.name
	}
	g.building(&d.node, func() {
		d.decl = append(d.decl, typeSpec(name, &ast.StructType{Fields: &ast.FieldList{List: []*ast.Field{field("self", g.goType(from))}}}))
		for _, op := range g.operations(contract) {
			d.decl = append(d.decl, g.viewMethod(name, from, contract, op))
		}
	})
	return name
}

func (g *gen) viewMethod(view string, from, contract *checker.Type, op checker.Operation) ast.Decl {
	m := g.resolveContractMethod(from, contract, op.Name)
	params := []*ast.Field{field("ctx", pointerTo(rtName("Execution")))}
	var args []ast.Expr
	for i, p := range op.Type.Params {
		name := "a" + itoa(i)
		params = append(params, field(name, g.goType(p.Type)))
		args = append(args, ident(name))
	}
	body := g.invokeMethod(m, from, selector(ident("v"), "self"), op.Name, args, &checker.Info{Type: m.Type})
	if op.Accessor {
		body = g.invokeAccessorBody(m, from, selector(ident("v"), "self"), op.Name)
	}
	return &ast.FuncDecl{
		Recv: &ast.FieldList{List: []*ast.Field{field("v", ident(view))}},
		Name: ident(camel(op.Name)), Type: functionType(params, g.goType(op.Type.Result)),
		Body: block(returned(body)),
	}
}

func (g *gen) invokeAccessorBody(m *checker.Method, from *checker.Type, receiver ast.Expr, name string) ast.Expr {
	if m.Native != "" && m.Contract != nil {
		return call(rtName(implName(m, g.sub(from))), ident("ctx"), receiver)
	}
	f := g.methodFunction(m, from)
	return call(ident(f.name), ident("ctx"), receiver)
}

// resolveContractMethod finds the implementation of an operation of contract
// for the concrete type from.
func (g *gen) resolveContractMethod(from, contract *checker.Type, name string) *checker.Method {
	for _, m := range g.program.ResolveMethods(g.module, from, name) {
		if m.Contract != nil && m.Contract.ID == contract.ID {
			return m
		}
	}
	g.fail("%s has no implementation of %s.%s", from, contract, name)
	return &checker.Method{Type: &checker.Type{Kind: "function", Result: unitType}}
}

// viewCall lowers the explicit view constructor Contract(value: x).
func (g *gen) viewCall(e *syntax.Expression, info *checker.Info) ast.Expr {
	arg := e.Args[0].Value
	value := g.expr(arg)
	return g.viewOf(value, g.info(arg).Type, info.Type)
}

// errorBoundary converts a value that crosses an Error boundary: a concrete
// error becomes an Error view, and a Result with a concrete error maps its
// error.
func (g *gen) errorBoundary(value ast.Expr, info *checker.Info) ast.Expr {
	source, target := g.sub(info.ErrorSource), g.sub(info.Type)
	if isStd(source, "Result") {
		from, to := source.Args[1], target.Args[1]
		convert := closure([]*ast.Field{field("e", g.goType(from))}, g.goType(to), returned(g.viewOf(ident("e"), from, to)))
		return call(generic(rtName("ResultMapError"), g.goType(source.Args[0]), g.goType(from), g.goType(to)), value, convert)
	}
	return g.viewOf(value, source, target)
}

// contractClause is the type-switch clause of a contract type pattern.
func (g *gen) contractClause(scrutinee *checker.Type, tmp string, a *syntax.Arm, result string, resultType *checker.Type) ast.Stmt {
	clause := &ast.CaseClause{}
	var body []ast.Stmt
	if concrete := g.program.ContractPattern(a); concrete != nil {
		clause.List = []ast.Expr{ident(g.view(g.sub(concrete), g.sub(scrutinee)))}
		if bs := g.program.ArmBindingsFor(a); len(bs) > 0 && bs[0] != nil {
			body = append(body, define(g.bindingName(bs[0]), selector(ident("s"+tmp), "self")))
			body = append(body, g.keepUnused(bs[0])...)
		}
	}
	clause.Body = append(body, g.armBody(a, result, resultType)...)
	return clause
}

// try unwraps a successful Result or returns its error from the enclosing
// function, converting the error across an Error boundary.
func (g *gen) try(e *syntax.Expression, info *checker.Info) ast.Expr {
	inner := g.expr(e.Right)
	innerType := g.info(e.Right).Type
	tmp := g.temp()
	result := g.sub(g.fn.result)
	err := ast.Expr(selector(ident(tmp), "Err"))
	if info.PropagatedError != nil || (isStd(result, "Result") && innerType.Args[1].ID != result.Args[1].ID) {
		from := innerType.Args[1]
		if info.PropagatedError != nil {
			from = info.PropagatedError
		}
		err = g.viewOf(err, from, result.Args[1])
	}
	failure := composite(g.goType(result), keyed("Err", err), keyed("Failed", ident("true")))
	g.fn.pre = append(g.fn.pre, define(tmp, inner), &ast.IfStmt{Cond: selector(ident(tmp), "Failed"), Body: block(returned(failure))})
	return selector(ident(tmp), "Val")
}

var _ = token.ADD
