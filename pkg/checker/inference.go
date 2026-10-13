package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// Infer ordinary arguments first, then callbacks whose input types are known.
// Callback results supply evidence for generic result variables. Revisit deferred
// callbacks when another argument provides their input context.
func (c *checker) inferArguments(args []syntax.Argument, params []Param, variables []*Type, sub map[string]*Type) {
	vars := variableSet(variables)
	pending := []syntax.Argument{}
	parameter := func(name string) *Type {
		for _, param := range params {
			if param.Name == name {
				return param.Type
			}
		}
		return nil
	}
	contribute := func(arg syntax.Argument, actual *Info) {
		pattern := parameter(arg.Name)
		if pattern != nil && !c.errorAssignable(actual.Type, Sub(pattern, sub)) && !c.unifyArgument(pattern, actual.Type, vars, sub) {
			c.error(arg.Pos, "type", "conflicting generic inference")
		}
	}
	for _, arg := range args {
		if arg.Value.Kind == syntax.KindLambda {
			pending = append(pending, arg)
		} else if !c.contextual(arg.Value) {
			if actual := c.independentArgument(arg.Value); actual != nil {
				contribute(arg, actual)
			}
		}
	}
	for len(pending) > 0 {
		progress := false
		next := []syntax.Argument{}
		for _, arg := range pending {
			pattern := Sub(parameter(arg.Name), sub)
			context := callbackContext(pattern)
			known := true
			for index, param := range arg.Value.Params {
				if param.Type == nil && (context == nil || len(context.Params) != len(arg.Value.Params) || !inferenceTypeKnown(context.Params[index].Type, vars)) {
					known = false
				}
			}
			if !known {
				next = append(next, arg)
				continue
			}
			previous := c.inferenceVariables
			c.inferenceVariables = map[string]bool{}
			for key := range previous {
				c.inferenceVariables[key] = true
			}
			for key := range vars {
				c.inferenceVariables[key] = true
			}
			checkpoint := len(c.Diagnostics)
			actual := c.infer(arg.Value, pattern)
			c.inferenceVariables = previous
			if len(c.Diagnostics) != checkpoint {
				c.Diagnostics = c.Diagnostics[:checkpoint]
				if !inferenceTypeKnown(actual.Type, vars) {
					next = append(next, arg)
					continue
				}
			}
			contribute(arg, actual)
			progress = true
		}
		if !progress {
			break
		}
		pending = next
	}
}
