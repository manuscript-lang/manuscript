package lower

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
	if original.Decl == nil {
		g.fail("method %s of %s has no source declaration (native %q, contract %v)", m.ID, receiver, m.Native, m.Contract)
		return &funcDecl{}
	}
	subst := map[string]*checker.Type{}
	key := original.ID
	scope := g.scopeFor(original.Module, len(original.Variables))
	if scope != "" {
		key += "@" + scope
	}
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
	g.mu.Lock()
	f := g.funcs[key]
	g.mu.Unlock()
	if f != nil {
		g.touch(&f.node)
		return f
	}
	base := sanitize(receiver.Name) + "_" + sanitize(original.Decl.Name)
	name := base
	if g.dup[base] {
		name += "_" + shortHash(original.ID)
	}
	for _, v := range original.Variables {
		name += "_" + g.nameOf(subst[v.ID])
	}
	if scope != "" {
		name += "_" + shortHash(scope)
	}
	created := &funcDecl{key: key, name: g.claim(name, key), module: original.Module, scope: scope, method: original, decl: original.Decl, subst: subst}
	created.typ = checker.Sub(original.Type, subst)
	created.fn = created
	return g.intern(created)
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
		targs, _ := g.nativeTypeArguments(m, receiverType, nil)
		return call(generic(rtName(fn), targs...), ident("ctx"), receiver)
	case m.Native != "":
		g.noteNative(implName(m, receiverType))
		return call(rtName(implName(m, receiverType)), ident("ctx"), receiver)
	}
	f := g.methodFunction(m, receiverType)
	return call(ident(f.name), ident("ctx"), receiver)
}

// boundMethod is a method used as a value: a function with the receiver bound.
func (g *gen) boundMethod(e *syntax.Expression, info *checker.Info) ast.Expr {
	t := g.sub(info.Type)
	receiverType := g.info(e.Left).Type
	m := g.resolveMethod(info.Method, receiverType, e.Text)
	receiver := g.snapshot(g.expr(e.Left))
	params := []*ast.Field{field("ctx", pointerTo(rtName("Execution")))}
	var args []ast.Expr
	for i := range t.Params {
		name := "a" + itoa(i)
		params = append(params, field(name, g.paramType(t, i)))
		args = append(args, g.forwardArg(ident(name), t, i, m, receiverType))
	}
	body := g.invokeMethod(m, receiverType, receiver, e.Text, args, info)
	return closure(params, g.goType(t.Result), returned(body))
}

// snapshot captures e now: a mutable variable may be reassigned before the
// closure that uses it runs.
func (g *gen) snapshot(e ast.Expr) ast.Expr {
	if id, ok := e.(*ast.Ident); ok && g.fn.mutables[id.Name] {
		name := g.temp()
		g.fn.pre = append(g.fn.pre, define(name, e))
		return ident(name)
	}
	return g.spill(e)
}
