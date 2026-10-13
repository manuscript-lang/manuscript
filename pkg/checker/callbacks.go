package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// Inferred returns require one exact value type; Never provides no competing
// value, and normal fallthrough contributes Unit. Nested callbacks own frames.
type callbackReturns struct {
	typ              *Type
	context          *Type
	unresolved       bool
	contextDependent bool
}

func (r *callbackReturns) add(c *checker, typ *Type, pos syntax.Position) {
	if !inferenceTypeKnown(typ, c.inferenceVariables) {
		r.unresolved = true
		return
	}
	if typ.ID == "Never" {
		return
	}
	if r.typ == nil {
		r.typ = typ
	} else if !Same(typ, r.typ) {
		r.contextDependent = true
		c.error(pos, "type", "callback returns require the same type: "+formatMismatch(typ, r.typ)+"; make every return in the callback produce one type")
	}
}

func callbackContext(expected *Type) *Type {
	if std(expected, "Optional") && len(expected.Args) == 1 {
		expected = expected.Args[0]
	}
	if expected != nil && expected.Kind == "function" {
		return expected
	}
	return nil
}

func inferenceTypeKnown(t *Type, variables map[string]bool) bool {
	return inferenceTypeResolved(t, variables, false)
}

func inferenceTypeResolved(t *Type, variables map[string]bool, allowInvalid bool) bool {
	if t == nil || (!allowInvalid && t.ID == "<invalid>") || variables[t.ID] {
		return false
	}
	for _, arg := range t.Args {
		if !inferenceTypeResolved(arg, variables, allowInvalid) {
			return false
		}
	}
	for _, param := range t.Params {
		if !inferenceTypeResolved(param.Type, variables, allowInvalid) {
			return false
		}
	}
	return t.Result == nil || inferenceTypeResolved(t.Result, variables, allowInvalid)
}

func (c *checker) callback(e *syntax.Expression, expected *Type) *Info {
	context := callbackContext(expected)
	if context != nil && len(context.Params) != len(e.Params) {
		c.error(e.Pos, "type", "callback parameter count does not match its context; the callback takes exactly the parameters its context declares")
		context = nil
	}
	params := make([]Param, len(e.Params))
	seen := map[string]bool{}
	defaults := map[string]bool{}
	for index, param := range e.Params {
		if seen[param.Name] {
			c.error(param.Pos, "type", "duplicate parameter or field "+param.Name+"; each name may appear once, so rename one")
		}
		seen[param.Name] = true
		var typ *Type
		if param.Type != nil {
			typ = c.resolve(param.Type, false)
		} else if context != nil && inferenceTypeKnown(context.Params[index].Type, c.inferenceVariables) {
			typ = context.Params[index].Type
		} else {
			c.error(param.Pos, "type", "cannot infer callback parameter "+param.Name+"; provide a type or a known function context")
			typ = primitive("<invalid>")
		}
		params[index] = Param{param.Name, typ}
		if param.Default != nil {
			defaults[param.Name] = true
		}
	}
	var result *Type
	if e.Result != nil {
		result = c.resolve(e.Result, false)
	} else if context != nil && inferenceTypeKnown(context.Result, c.inferenceVariables) {
		result = context.Result
	}
	oldScope, oldResult, oldFunction, oldLoops, oldReturns := c.scope, c.result, c.function, c.loops, c.returnInference
	c.scope = newScope(oldScope)
	c.result = result
	c.returnInference = nil
	if result == nil {
		c.result = primitive("<inferred>")
		c.returnInference = &callbackReturns{}
		if context != nil {
			c.result = context.Result
			c.returnInference.context = context.Result
		}
	}
	c.function = c.serial + 1
	c.serial++
	c.loops = 0
	c.captures[c.function] = map[*Binding]bool{}
	c.lambdaParameters[e] = nil
	for index, param := range params {
		if e.Params[index].Default != nil {
			c.expression(e.Params[index].Default, param.Type)
		}
		c.lambdaParameters[e] = append(c.lambdaParameters[e], c.bind(param.Name, param.Type, false, e.Params[index].Pos))
	}
	fall, _ := c.block(e.Body, false)
	if result == nil {
		if fall {
			c.returnInference.add(c, primitive("Unit"), e.Pos)
		}
		result = c.returnInference.typ
		if result == nil {
			result = primitive("Never")
			if c.returnInference.unresolved {
				result = primitive("<invalid>")
			}
		}
	} else if fall && result.ID != "Unit" && result.ID != "<invalid>" {
		c.error(e.Pos, "type", "reachable fallthrough in anonymous function; end every path with a 'return'")
	}
	// Context labels belong to callers; source names remain local bindings.
	// Preserve invariant parameter types and declaration order.
	if context != nil {
		for index := range params {
			params[index].Name = context.Params[index].Name
		}
		contextDefaults := map[string]bool{}
		for index, param := range e.Params {
			if defaults[param.Name] {
				contextDefaults[params[index].Name] = true
			}
		}
		defaults = contextDefaults
	}
	t := function(params, result)
	if len(defaults) > 0 {
		t.Defaults = defaults
	}
	info := &Info{Type: t}
	if c.returnInference != nil {
		info.inferenceDeferred = c.returnInference.unresolved || c.returnInference.contextDependent
	}
	for binding := range c.captures[c.function] {
		info.Captures = append(info.Captures, binding)
		if oldFunction != binding.Function && c.captures[oldFunction] != nil {
			c.captures[oldFunction][binding] = true
		}
	}
	c.scope, c.result, c.function, c.loops, c.returnInference = oldScope, oldResult, oldFunction, oldLoops, oldReturns
	return info
}
