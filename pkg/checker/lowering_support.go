package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// Unify infers the variables of vars that make pattern equal to actual. The
// result maps variable identities to types and is complete only when ok.
func Unify(pattern, actual *Type, vars []*Type) (map[string]*Type, bool) {
	sub := map[string]*Type{}
	if !unify(pattern, actual, variableSet(vars), sub) {
		return nil, false
	}
	return sub, true
}

// ResolveMethods returns the implementations of name visible from module for
// a concrete receiver, as the checker selects them for a member call. Lowering
// uses it to re-resolve a bounded type variable's operation once the variable
// is replaced by a concrete type.
func (p *Program) ResolveMethods(module string, receiver *Type, name string) []*Method {
	c := &checker{Program: p, module: &syntax.Module{File: module}}
	return c.methods(receiver, name)
}

// Implements reports whether receiver implements contract in module.
func (p *Program) Implements(module string, receiver, contract *Type) bool {
	c := &checker{Program: p, module: &syntax.Module{File: module}}
	return c.implements(receiver, contract)
}

// HasProperty reports whether t has the Equal or Hashable property in module.
func (p *Program) HasProperty(module string, t *Type, property string) bool {
	c := &checker{Program: p, module: &syntax.Module{File: module}}
	return c.property(t, property, nil)
}
