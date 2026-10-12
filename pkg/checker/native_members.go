package checker

import (
	"github.com/manuscript-lang/manuscript/internal/nativeabi"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strings"
)

// nativeReceiverAvailable applies the shared function's receiver requirements.
// For example, equality search requires Equal, join requires List[String], and
// to_set requires Hashable, without strengthening List's element requirements.
func nativeReceiverAvailable(c *checker, receiver *Type, name string) bool {
	identity, mapped := nativeabi.ReceiverFunctions[receiver.Name][name]
	if !mapped {
		return true
	}
	module, function, _ := strings.Cut(identity, "/")
	symbol := standardModules["@std/"+module+".ms"][function]
	if symbol == nil || len(symbol.Type.Params) == 0 {
		return false
	}
	sub := map[string]*Type{}
	if !unify(symbol.Type.Params[0].Type, receiver, variableSet(symbol.Variables), sub) {
		return false
	}
	for _, variable := range symbol.Variables {
		actual := sub[variable.ID]
		if actual == nil {
			continue
		} // Method variables are checked at specialization.
		for _, bound := range variable.Bounds {
			if !c.satisfies(actual, Sub(bound, sub)) {
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
	if e.Kind == syntax.KindApply {
		member = e.Left
	}
	if member.Kind != syntax.KindMember || c.typeExpression(member.Left) != nil {
		return nil
	}
	receiver := c.expression(member.Left, nil)
	if receiver.Type.Kind == syntax.KindRecord && member.Text != "toString" {
		for _, field := range Fields(receiver.Type) {
			if field.Name == member.Text {
				return nil
			}
		}
	}
	methods := c.methods(receiver.Type, member.Text)
	// Implementations have already specialized their receiver variables. They
	// dispatch through the contract, rather than native receiver operations.
	if len(methods) != 1 || methods[0].Contract != nil || methods[0].Native == "" || methods[0].Native == "contract" {
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
	if e.Left.Kind == syntax.KindApply {
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
	if len(vars) > 0 || e.Left.Kind == syntax.KindApply {
		copy.Type = c.specialize(info.Type, vars, supplied, e.Pos)
	}
	c.Expressions[e.Left] = &copy
	*info = copy
}
