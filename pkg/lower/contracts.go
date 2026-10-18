package lower

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
		methods = append(methods, &ast.Field{Names: []*ast.Ident{ident(exportName(op.Name))}, Type: g.operationType(op.Type)})
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
	if g.inRuntime {
		// Runtime contracts take every argument; the caller fills defaults.
		plain := *t
		plain.Defaults = nil
		t = &plain
	}
	params := []*ast.Field{field("ctx", pointerTo(rtName("Execution")))}
	for i := range t.Params {
		params = append(params, field("a"+itoa(i), g.paramType(t, i)))
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
	// Converting to the contract type keeps inferred types abstract.
	return call(g.contractType(contract), composite(ident(view), keyed("self", value)))
}

// view declares the struct that adapts from to contract.
func (g *gen) view(from, contract *checker.Type) string {
	key := "view:" + checker.TypeKey(contract) + ":" + checker.TypeKey(from)
	name := g.nameOf(contract) + "_" + g.nameOf(from)
	if g.localImpl {
		// Module-local implementations make the same pair adapt differently
		// in different modules.
		scope := g.module + "@" + g.scope
		key += "@" + scope
		name += "_" + shortHash(scope)
	}
	name = g.derived(name, key)
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
		// A view exposes its receiver, so the runtime can classify a wrapped
		// standard error without invoking it.
		d.decl = append(d.decl, &ast.FuncDecl{
			Recv: &ast.FieldList{List: []*ast.Field{field("v", ident(name))}},
			Name: ident("Receiver"), Type: functionType(nil, ident("any")),
			Body: block(returned(selector(ident("v"), "self"))),
		})
		// A view prints as its receiver.
		describe := g.nested(from, selector(ident("v"), "self"))
		d.decl = append(d.decl, &ast.FuncDecl{
			Recv: &ast.FieldList{List: []*ast.Field{field("v", ident(name))}},
			Name: ident("Describe"), Type: functionType([]*ast.Field{field("depth", ident("int"))}, ident("string")),
			Body: block(returned(describe)),
		})
	})
	return name
}

func (g *gen) viewMethod(view string, from, contract *checker.Type, op checker.Operation) ast.Decl {
	if isStdType(contract) {
		// Runtime contracts take every argument; the caller fills defaults.
		plain := *op.Type
		plain.Defaults = nil
		op.Type = &plain
	}
	m := g.resolveContractMethod(from, contract, op.Name)
	params := []*ast.Field{field("ctx", pointerTo(rtName("Execution")))}
	var args []ast.Expr
	for i := range op.Type.Params {
		name := "a" + itoa(i)
		params = append(params, field(name, g.paramType(op.Type, i)))
		arg := g.forwardArg(ident(name), op.Type, i, m, from)
		if m.Native != "" && m.Native != "contract" && contract.ID == "@std/Comparable" && op.Type.Params[i].Type.ID == contract.ID {
			// A native operation takes the concrete receiver type, not the view.
			arg = call(generic(rtName("Unview"), g.goType(from)), arg)
		}
		args = append(args, arg)
	}
	body := g.invokeMethod(m, from, selector(ident("v"), "self"), op.Name, args, &checker.Info{Type: m.Type})
	return &ast.FuncDecl{
		Recv: &ast.FieldList{List: []*ast.Field{field("v", ident(view))}},
		Name: ident(exportName(op.Name)), Type: functionType(params, g.goType(op.Type.Result)),
		Body: block(returned(body)),
	}
}

// resolveContractMethod finds the implementation of an operation of contract
// for the concrete type from.
func (g *gen) resolveContractMethod(from, contract *checker.Type, name string) *checker.Method {
	for _, m := range g.resolve(from, name) {
		if m.Contract != nil && m.Contract.ID == contract.ID {
			return m
		}
	}
	// A standard or intrinsic type's own native operation can satisfy a runtime contract.
	if isStdType(from) || isStdType(contract) {
		for _, m := range g.resolve(from, name) {
			if m.Native != "" {
				return m
			}
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
		concrete = g.sub(concrete)
		// With module-local implementations the same value can arrive in
		// the views of different modules, so match on the receiver.
		byReceiver := g.matchesReceiver(g.sub(scrutinee))
		var bound ast.Expr = selector(ident("s"+tmp), "self")
		if byReceiver {
			clause.List = []ast.Expr{g.goType(concrete)}
			bound = ident("s" + tmp)
		} else {
			clause.List = []ast.Expr{ident(g.view(concrete, g.sub(scrutinee)))}
		}
		if bs := g.program.ArmBindingsFor(a); len(bs) > 0 && bs[0] != nil {
			body = append(body, define(g.bindingName(bs[0]), bound))
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
	var failure ast.Expr = composite(g.goType(result), keyed("Err", err), keyed("Failed", ident("true")))
	if checker.TypeKey(g.sub(innerType)) == checker.TypeKey(result) && info.PropagatedError == nil {
		// The failed result already has the function's exact return type.
		failure = ident(tmp)
	}
	g.fn.pre = append(g.fn.pre, define(tmp, inner), &ast.IfStmt{Cond: selector(ident(tmp), "Failed"), Body: block(returned(failure))})
	return selector(ident(tmp), "Val")
}

var _ = token.ADD

// forwardArg passes parameter i of a wrapper with signature from to the
// method m it forwards to. Both take rt.Arg for a defaulted parameter, so the
// callee still fills in an omitted argument; natives take the plain value.
func (g *gen) forwardArg(arg ast.Expr, from *checker.Type, i int, m *checker.Method, receiver *checker.Type) ast.Expr {
	fromDefault := defaulted(from, i)
	native := m.Native != "" && (m.Native != "contract" || isStdType(g.sub(receiver)))
	toDefault := !native && m.Type != nil && i < len(m.Type.Params) && defaulted(m.Type, i)
	switch {
	case fromDefault == toDefault:
		return arg
	case toDefault:
		return rtCall("Given", arg)
	case native && m.Decl != nil:
		return g.nativeFill(arg, from.Params[i].Type, m.Decl, i, g.module)
	}
	return selector(arg, "Val")
}

// nativeFill turns an rt.Arg into the plain value a native operation takes:
// an omitted argument becomes the operation's declared default, or none.
func (g *gen) nativeFill(arg ast.Expr, typ *checker.Type, decl *syntax.Declaration, i int, module string) ast.Expr {
	var expr *syntax.Expression
	if i < len(decl.Params) {
		expr = decl.Params[i].Default
	}
	if expr == nil || g.program.Info(expr) == nil && expr.Kind == syntax.KindName && expr.Text == "none" {
		return selector(arg, "Val") // an omitted Optional is the zero Option
	}
	saved, savedModule, savedPre := g.fn.pre, g.module, g.fn.pre
	g.fn.pre, g.module = nil, module
	value := g.valueAs(expr, typ)
	body := append(g.fn.pre, returned(value))
	g.fn.pre, g.module = savedPre, savedModule
	_ = saved
	return rtCall("ArgOr", arg, closure(nil, g.goType(typ), body...))
}

// matchesReceiver reports whether a match on a value of contract type
// scrutinee switches on the wrapped receiver instead of the view type.
func (g *gen) matchesReceiver(scrutinee *checker.Type) bool {
	return g.localImpl && scrutinee.Kind == "contract"
}
