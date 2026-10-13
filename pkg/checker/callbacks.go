package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// Inferred returns require one exact value type; Never provides no competing
// value, and normal fallthrough contributes Unit. Nested callbacks own frames.
type callbackReturns struct {
	typ        *Type
	context    *Type
	unresolved bool
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
		c.error(pos, "type", "callback returns require the same type: "+formatMismatch(typ, r.typ))
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
	if t == nil || t.ID == "<invalid>" || variables[t.ID] {
		return false
	}
	for _, arg := range t.Args {
		if !inferenceTypeKnown(arg, variables) {
			return false
		}
	}
	for _, param := range t.Params {
		if !inferenceTypeKnown(param.Type, variables) {
			return false
		}
	}
	return t.Result == nil || inferenceTypeKnown(t.Result, variables)
}

func (c *checker) callback(e *syntax.Expression, expected *Type) *Info {
	context := callbackContext(expected)
	if context != nil && len(context.Params) != len(e.Params) {
		c.error(e.Pos, "type", "callback parameter count does not match its context")
		context = nil
	}
	params := make([]Param, len(e.Params))
	seen := map[string]bool{}
	defaults := map[string]bool{}
	for index, param := range e.Params {
		if seen[param.Name] {
			c.error(param.Pos, "type", "duplicate parameter or field "+param.Name)
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
	c.LambdaParameters[e] = nil
	for index, param := range params {
		if e.Params[index].Default != nil {
			c.expression(e.Params[index].Default, param.Type)
		}
		c.LambdaParameters[e] = append(c.LambdaParameters[e], c.bind(param.Name, param.Type, false, e.Params[index].Pos))
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
		c.error(e.Pos, "type", "reachable fallthrough in anonymous function")
	}
	t := function(params, result)
	if len(defaults) > 0 {
		t.Defaults = defaults
	}
	info := &Info{Type: t}
	for binding := range c.captures[c.function] {
		info.Captures = append(info.Captures, binding)
		if oldFunction != binding.Function && c.captures[oldFunction] != nil {
			c.captures[oldFunction][binding] = true
		}
	}
	c.scope, c.result, c.function, c.loops, c.returnInference = oldScope, oldResult, oldFunction, oldLoops, oldReturns
	return info
}
