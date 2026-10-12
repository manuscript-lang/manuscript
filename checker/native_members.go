package checker

import (
	rt "github.com/manuscript-lang/manuscript/runtime"
	"github.com/manuscript-lang/manuscript/syntax"
	"strings"
)

// nativeReceiverAvailable applies the shared function's receiver requirements.
// For example, equality search requires Equal, join requires List[String], and
// to_set requires Hashable, without strengthening List's element requirements.
func nativeReceiverAvailable(c *checker, receiver *Type, name string) bool {
	spec, ok := rt.NativeLibrarySpec(receiver.Name, name)
	if !ok {
		return true
	}
	vars := map[string]*Type{}
	for _, v := range spec.Variables {
		vars[v.Name] = &Type{Name: v.Name, ID: "native-member/" + v.Name, Kind: "variable"}
	}
	variables := []*Type{}
	for _, v := range spec.Variables {
		variables = append(variables, vars[v.Name])
	}
	sub := map[string]*Type{}
	if !unify(libraryParseType(spec.Params[0].Type, vars), receiver, variableSet(variables), sub) {
		return false
	}
	for _, v := range spec.Variables {
		actual := sub[vars[v.Name].ID]
		if actual == nil {
			continue
		} // method's own type variable is checked at specialization
		for _, bound := range strings.Split(v.Type, "&") {
			if bound != "" && !c.satisfies(actual, libraryParseType(bound, vars)) {
				return false
			}
		}
	}
	return true
}

// nativeCallable resolves native operations before generic specialization. Only
// pinned standard declarations introduce method variables; user contracts retain
// their existing nongeneric operation grammar.
func (c *checker) nativeCallable(e *syntax.Expression) *Info {
	member := e
	if e.Kind == "apply" {
		member = e.Left
	}
	if member.Kind != "member" || c.typeExpression(member.Left) != nil {
		return nil
	}
	receiver := c.expression(member.Left, nil)
	methods := c.methods(receiver.Type, member.Text)
	if len(methods) != 1 || methods[0].Native == "" || methods[0].Native == "contract" {
		return nil
	}
	m := methods[0]
	info := &Info{Type: m.Type, Method: m, Native: m.Native, NoReturn: receiver.NoReturn}
	c.Expressions[member] = info
	return info
}

func (c *checker) specializeNativeCall(e *syntax.Expression, info *Info) {
	vars := info.Method.Variables
	var supplied []*Type
	if e.Left.Kind == "apply" {
		supplied = c.resolveArguments(e.Left.Types)
	} else if len(vars) > 0 {
		sub := map[string]*Type{}
		for _, arg := range functionArguments(e.Args, info.Type.Params) {
			if c.contextual(arg.Value) {
				continue
			}
			actual := c.independentArgument(arg.Value)
			if actual == nil {
				continue
			}
			for _, param := range info.Type.Params {
				if param.Name == arg.Name && !unify(param.Type, actual.Type, variableSet(vars), sub) {
					c.error(arg.Pos, "type", "conflicting generic inference")
				}
			}
		}
		for _, v := range vars {
			supplied = append(supplied, sub[v.ID])
		}
	}
	copy := *info
	if len(vars) > 0 || e.Left.Kind == "apply" {
		copy.Type = c.specialize(info.Type, vars, supplied, e.Pos)
	}
	c.Expressions[e.Left] = &copy
	*info = copy
}
