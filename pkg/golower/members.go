package golower

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// methodFunction instantiates a source implementation method for a concrete
// receiver: the implementation's type variables are fixed by unifying its
// declared receiver with the receiver the call site has.
func (g *gen) methodFunction(m *checker.Method, receiver *checker.Type) *funcDecl {
	original := g.methodByID[m.ID]
	if original == nil {
		original = m
	}
	subst := map[string]*checker.Type{}
	key := original.ID
	if len(original.Variables) > 0 {
		found, ok := checker.Unify(original.Receiver, receiver, original.Variables)
		if !ok {
			g.fail("cannot instantiate %s.%s for %s", original.Receiver, original.Decl.Name, receiver)
		}
		for _, v := range original.Variables {
			subst[v.ID] = found[v.ID]
			key += "[" + checker.TypeKey(found[v.ID]) + "]"
		}
	}
	if f := g.funcs[key]; f != nil {
		return f
	}
	name := sanitize(receiver.Name) + "_" + sanitize(original.Decl.Name)
	for _, v := range original.Variables {
		name += "_" + g.nameOf(subst[v.ID])
	}
	f := &funcDecl{key: key, name: g.unique(name), module: original.Module, method: original, decl: original.Decl, subst: subst}
	f.typ = checker.Sub(original.Type, subst)
	g.funcs[key] = f
	g.queue = append(g.queue, f)
	return f
}

// accessor reads a computed member declared with `get`.
func (g *gen) accessor(e *syntax.Expression, info *checker.Info) ast.Expr {
	receiverType := g.info(e.Left).Type
	receiver := g.expr(e.Left)
	m := g.resolveMethod(info.Method, receiverType, e.Text)
	receiverType = g.sub(receiverType)
	switch {
	case m.Native == "contract":
		return call(selector(receiver, camel(e.Text)), ident("ctx"))
	case m.Native != "" && m.Contract == nil:
		fn := g.nativeMethodName(m, receiverType)
		g.noteNative(fn)
		return call(generic(rtName(fn), g.nativeTypeArguments(m, receiverType, nil)...), ident("ctx"), receiver)
	case m.Native != "":
		g.noteNative(nativeName(m.Native))
		return call(rtName(nativeName(m.Native)), ident("ctx"), receiver)
	}
	f := g.methodFunction(m, receiverType)
	return call(ident(f.name), ident("ctx"), receiver)
}

// boundMethod is a method used as a value: a function with the receiver bound.
func (g *gen) boundMethod(e *syntax.Expression, info *checker.Info) ast.Expr {
	t := g.sub(info.Type)
	receiverType := g.info(e.Left).Type
	m := g.resolveMethod(info.Method, receiverType, e.Text)
	receiver := g.spill(g.expr(e.Left))
	params := []*ast.Field{field("ctx", pointerTo(rtName("Execution")))}
	var args []ast.Expr
	for i, p := range t.Params {
		name := "a" + itoa(i)
		params = append(params, field(name, g.goType(p.Type)))
		args = append(args, ident(name))
	}
	body := g.invokeMethod(m, receiverType, receiver, e.Text, args, info)
	return closure(params, g.goType(t.Result), returned(body))
}
