package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

type callInferenceContext struct {
	result, expected *Type
	pos              syntax.Position
	conflict         bool
}

// Infer ordinary arguments first, then use the expected result to complete
// missing evidence before checking callbacks whose input types are known.
// Callback results supply evidence for generic result variables. Revisit deferred
// callbacks when another argument provides their input context.
func (c *checker) inferArguments(args []syntax.Argument, params []Param, variables []*Type, sub map[string]*Type, context *callInferenceContext) {
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
		if pattern == nil {
			return
		}
		if invalidType(actual.Type) {
			if std(pattern, "Optional") && actual.Type.Kind == "function" {
				pattern = pattern.Args[0]
			}
			if !inferInvalidArgument(pattern, actual.Type, vars, sub) {
				c.error(arg.Pos, "type", conflictingInference)
			}
			return
		}
		if !c.errorAssignable(actual.Type, Sub(pattern, sub)) && !c.unifyArgument(pattern, actual.Type, vars, sub) {
			if hint := labelMismatchHint(actual.Type, Sub(pattern, sub)); hint != "" {
				c.error(arg.Pos, "type", "callback mismatch: "+hint)
				c.unknownType = true
				c.labelMismatch = true
				return
			}
			c.error(arg.Pos, "type", conflictingInference)
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
	if context != nil {
		c.inferExpectedResult(variables, sub, context)
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
			// Retain complete probe evidence, including root diagnostics. Invalid
			// slots may be reused only if the final signature has the same slots;
			// new concrete context forces a fresh check in argumentExpression.
			// Even a complete signature may need rechecking after deferred returns
			// or try; they can become valid under the inferred enclosing result.
			if inferenceTypeResolved(actual.Type, c.inferenceVariables, true) && (!actual.inferenceDeferred || invalidType(actual.Type)) && c.checkedArguments != nil {
				c.checkedArguments[arg.Value] = checkedArgument{actual, append([]syntax.Diagnostic(nil), c.Diagnostics[checkpoint:]...)}
			}
			c.inferenceVariables = previous
			if len(c.Diagnostics) != checkpoint {
				c.Diagnostics = c.Diagnostics[:checkpoint]
				if !inferenceTypeKnown(actual.Type, vars) && !invalidType(actual.Type) {
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

// Keep valid evidence and mismatches when another part of an argument is
// invalid. Error markers fill only the variables whose evidence failed.
func inferInvalidArgument(pattern, actual *Type, vars map[string]bool, sub map[string]*Type) bool {
	if pattern == nil || actual == nil {
		return pattern == actual
	}
	if vars[pattern.ID] {
		previous := sub[pattern.ID]
		if previous == nil || previous.ID == "<invalid>" {
			sub[pattern.ID] = requiredType(actual)
			return true
		}
		return actual.ID == "<invalid>" || Same(previous, actual)
	}
	if actual.ID == "<invalid>" {
		for _, arg := range pattern.Args {
			inferInvalidArgument(arg, actual, vars, sub)
		}
		for _, param := range pattern.Params {
			inferInvalidArgument(param.Type, actual, vars, sub)
		}
		inferInvalidArgument(pattern.Result, actual, vars, sub)
		return true
	}
	if pattern.ID != actual.ID || len(pattern.Args) != len(actual.Args) || len(pattern.Params) != len(actual.Params) {
		return false
	}
	valid := true
	for index, arg := range pattern.Args {
		if !inferInvalidArgument(arg, actual.Args[index], vars, sub) {
			valid = false
		}
	}
	for index, param := range pattern.Params {
		if param.Name != actual.Params[index].Name {
			valid = false
		}
		if !inferInvalidArgument(param.Type, actual.Params[index].Type, vars, sub) {
			valid = false
		}
	}
	return inferInvalidArgument(pattern.Result, actual.Result, vars, sub) && valid
}

func invalidType(t *Type) bool {
	if t == nil {
		return false
	}
	if t.ID == "<invalid>" {
		return true
	}
	for _, arg := range t.Args {
		if invalidType(arg) {
			return true
		}
	}
	for _, param := range t.Params {
		if invalidType(param.Type) {
			return true
		}
	}
	return invalidType(t.Result)
}

// Result evidence is transactional and invariant. A failed structural match
// must not commit the prefix it happened to match. The only widening here is
// the same explicit Error boundary checked after ordinary expression inference.
func (c *checker) inferExpectedResult(variables []*Type, sub map[string]*Type, context *callInferenceContext) {
	if invalidType(context.expected) {
		// Keep usable parts of a failed annotation and poison only the result
		// variables whose evidence is invalid; the resolution error owns them.
		inferInvalidArgument(context.result, context.expected, variableSet(variables), sub)
		return
	}
	if !inferenceTypeKnown(context.expected, c.inferenceVariables) || invalidType(context.result) {
		return
	}
	missing := false
	for _, variable := range variables {
		missing = missing || sub[variable.ID] == nil
	}
	if !missing {
		return // Keep argument evidence; ordinary result checking reports mismatches.
	}
	vars := variableSet(variables)
	trial := map[string]*Type{}
	for key, value := range sub {
		trial[key] = value
	}
	result := Sub(context.result, sub)
	matched := unify(context.result, context.expected, vars, trial)
	if !matched && std(result, "Result") && std(context.expected, "Result") &&
		len(result.Args) == 2 && len(context.expected.Args) == 2 &&
		c.errorAssignable(result.Args[1], context.expected.Args[1]) {
		trial = map[string]*Type{}
		for key, value := range sub {
			trial[key] = value
		}
		matched = unify(context.result.Args[0], context.expected.Args[0], vars, trial)
	}
	if !matched && c.errorAssignable(result, context.expected) {
		return // Existing concrete error evidence needs no substitution.
	}
	if !matched {
		c.error(context.pos, "type", "conflicting generic inference; expected result type "+context.expected.String()+" does not match "+result.String()+"; give consistent argument and result types or specify the type arguments")
		context.conflict = true
		for _, variable := range variables {
			if sub[variable.ID] == nil {
				sub[variable.ID] = primitive("<invalid>")
			}
		}
		return
	}
	for key, value := range trial {
		sub[key] = value
	}
}
