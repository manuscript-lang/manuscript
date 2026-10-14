package checker

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (c *checker) call(e *syntax.Expression, expected *Type) *Info {
	i := &Info{}
	callee := e.Left
	if typ := c.typeExpression(callee); typ != nil {
		if typ.Kind == "primitive" || typ.Kind == "variable" {
			c.error(e.Pos, "type", "this type has no source constructor")
			return i
		}
		if typ.Kind == "contract" {
			typ = c.instantiate(typ, nil, nil, expected, e.Pos)
			if len(e.Args) != 1 || e.Args[0].Name != "value" {
				c.error(e.Pos, "type", "contract view requires exactly value: receiver")
				return i
			}
			receiver := c.expression(e.Args[0].Value, nil)
			if !c.implements(receiver.Type, typ) {
				c.error(e.Pos, "type", receiver.Type.String()+" does not implement "+typ.String())
			}
			i.Type = typ
			i.Constructor = typ
			i.Native = "view"
			i.NoReturn = receiver.NoReturn
			return i
		}
		if typ.Kind == "alternative" {
			c.error(e.Pos, "type", "construct an alternative case rather than its type")
			return i
		}
		var fields []Param
		fields = Fields(typ)
		if std(typ, "Bytes") {
			fields = []Param{{"values", standard("List", primitive("Int"))}}
		}
		if std(typ, "Task") || std(typ, "BigInt") || std(typ, "Regex") || std(typ, "Timestamp") || std(typ, "SynchronizedGuard") || std(typ, "List") || std(typ, "Instant") || std(typ, "Duration") || std(typ, "Decimal") || std(typ, "OperationId") {
			c.error(e.Pos, "type", "standard type has no source constructor")
			return i
		}
		typ = c.instantiate(typ, fields, e.Args, expected, e.Pos)
		fields = Fields(typ)
		if std(typ, "Queue") && len(e.Args) == 0 {
			fields = nil
		}
		if std(typ, "Bytes") {
			fields = []Param{{"values", standard("List", primitive("Int"))}}
		}
		i.NoReturn = c.arguments(e.Args, fields, ConstructorSignature(typ).Defaults)
		i.Type = typ
		i.Constructor = typ
		return i
	}
	var alternative *Type
	var cs Case
	if callee.Kind == syntax.KindMember {
		alternative = c.typeExpression(callee.Left)
		if alternative != nil {
			var ok bool
			cs, ok = caseOf(alternative, callee.Text)
			if !ok {
				c.error(e.Pos, "resolution", "unknown alternative case "+callee.Text)
				return i
			}
		}
	}
	if callee.Kind == syntax.KindName && c.scope.binding(callee.Text) == nil && c.names[callee.Text] == nil {
		alternative, cs = c.findCase(callee.Text, callee.Pos)
	}
	if alternative != nil {
		if len(cs.Fields) == 0 {
			c.error(e.Pos, "type", "nullary cases omit call parentheses")
		}
		alternative = c.instantiate(alternative, cs.Fields, e.Args, expected, e.Pos)
		cs, _ = caseOf(alternative, cs.Name)
		i.NoReturn = c.arguments(e.Args, cs.Fields)
		i.Type = alternative
		i.Constructor = alternative
		i.Case = cs.Name
		return i
	}
	var s *Symbol
	var supplied []*Type
	explicit := false
	if callee.Kind == syntax.KindApply {
		s = c.functionSymbol(callee.Left)
		if s != nil {
			supplied = c.resolveArguments(callee.Types)
			explicit = true
		}
	} else {
		s = c.functionSymbol(callee)
	}
	var signature *Type
	var callable *Info
	if s != nil {
		i.Symbol = s
		i.Native = s.Native
		signature = s.Type
		if len(s.Variables) > 0 {
			if !explicit {
				sub := map[string]*Type{}
				vars := variableSet(s.Variables)
				for _, arg := range functionArguments(e.Args, signature.Params) {
					if c.contextual(arg.Value) {
						continue
					}
					actual := c.independentArgument(arg.Value)
					if actual == nil {
						continue
					}
					for _, param := range signature.Params {
						if param.Name == arg.Name && !c.unifyArgument(param.Type, actual.Type, vars, sub) {
							c.error(arg.Pos, "type", "conflicting generic inference")
						}
					}
				}
				for _, v := range s.Variables {
					supplied = append(supplied, sub[v.ID])
				}
			}
			signature = c.specialize(signature, s.Variables, supplied, e.Pos)
			i.TypeArgs = supplied
		} else if explicit && len(supplied) > 0 {
			c.error(e.Pos, "type", "nongeneric function cannot take type arguments")
		}
		callable = &Info{Type: signature, Symbol: s}
		c.Expressions[callee] = callable
	} else {
		callable = c.nativeCallable(callee)
		if callable != nil {
			c.specializeNativeCall(e, callable)
		} else {
			callable = c.expression(callee, nil)
		}
		signature = callable.Type
		i.Method = callable.Method
		i.Native = callable.Native
	}
	if signature == nil || signature.Kind != "function" {
		c.error(e.Pos, "type", "callee is not a function")
		return i
	}
	i.Arguments = functionArguments(e.Args, signature.Params)
	i.NoReturn = callable.NoReturn || c.arguments(i.Arguments, signature.Params, signature.Defaults)
	i.Type = signature.Result
	if i.Type != nil && i.Type.ID == "Never" {
		i.NoReturn = true
	}
	return i
}

// Single-parameter calls omit any label; multi-parameter calls allow name shorthand.
// Keep the source AST intact for tools and repeated checking.
func functionArguments(args []syntax.Argument, params []Param) []syntax.Argument {
	resolved := append([]syntax.Argument(nil), args...)
	for index := range resolved {
		if resolved[index].Name == "" {
			if len(params) == 1 {
				resolved[index].Name = params[0].Name
			} else if value := resolved[index].Value; value.Kind == syntax.KindName && value.Pos == resolved[index].Pos {
				for _, param := range params {
					if param.Name == value.Text {
						resolved[index].Name = value.Text
						break
					}
				}
			}
		}
	}
	return resolved
}

func (c *checker) arguments(args []syntax.Argument, params []Param, defaults ...map[string]bool) bool {
	seen := map[string]bool{}
	noReturn := false
	for index, arg := range args {
		if arg.Name == "" {
			message := "argument labels are required for this call"
			if index < len(params) {
				message += "; write " + params[index].Name + ": ..."
				seen[params[index].Name] = true
			}
			c.error(arg.Pos, "type", message)
			v := c.expression(arg.Value, nil)
			noReturn = noReturn || v.NoReturn
			continue
		}
		if seen[arg.Name] {
			c.error(arg.Pos, "type", "duplicate argument "+arg.Name)
		}
		seen[arg.Name] = true
		var expected *Type
		for _, param := range params {
			if param.Name == arg.Name {
				expected = param.Type
				break
			}
		}
		if expected == nil {
			c.error(arg.Pos, "type", "unknown argument "+arg.Name)
		}
		v := c.argumentExpression(arg.Value, expected)
		noReturn = noReturn || v.NoReturn
	}
	for _, param := range params {
		if !seen[param.Name] && (len(defaults) == 0 || !defaults[0][param.Name]) {
			pos := c.modulePosition()
			if len(args) > 0 {
				pos = args[0].Pos
			}
			c.error(pos, "type", "missing argument "+param.Name)
		}
	}
	return noReturn
}
func (c *checker) modulePosition() syntax.Position {
	return syntax.Position{File: c.module.File, Line: 1, Column: 1}
}
func (c *checker) specialize(t *Type, vars, args []*Type, pos syntax.Position) *Type {
	sub := map[string]*Type{}
	if len(vars) != len(args) {
		c.error(pos, "type", "generic arity mismatch")
	}
	for index, v := range vars {
		var a *Type
		if index < len(args) {
			a = args[index]
		}
		if a == nil {
			c.error(pos, "type", "cannot infer type argument "+v.Name)
			a = primitive("<invalid>")
		}
		sub[v.ID] = a
	}
	for _, v := range vars {
		for _, bound := range v.Bounds {
			if !c.satisfies(sub[v.ID], Sub(bound, sub)) {
				c.error(pos, "type", fmt.Sprintf("%s does not satisfy %s", sub[v.ID], Sub(bound, sub)))
			}
		}
	}
	return Sub(t, sub)
}

// mentionsVariable reports whether a type still contains an unresolved variable.
func mentionsVariable(t *Type, vars map[string]bool) bool {
	if t == nil {
		return false
	}
	if vars[t.ID] {
		return true
	}
	for _, a := range t.Args {
		if mentionsVariable(a, vars) {
			return true
		}
	}
	for _, p := range t.Params {
		if mentionsVariable(p.Type, vars) {
			return true
		}
	}
	return mentionsVariable(t.Result, vars)
}
func (c *checker) instantiate(t *Type, fields []Param, args []syntax.Argument, expected *Type, pos syntax.Position) *Type {
	if t.Def == nil {
		return t
	}
	vars := t.Def.Variables
	sub := map[string]*Type{}
	for index, v := range vars {
		if index < len(t.Args) && t.Args[index].ID != v.ID {
			sub[v.ID] = t.Args[index]
		}
	}
	if expected != nil && expected.ID == t.ID && len(expected.Args) == len(vars) {
		for index, v := range vars {
			if sub[v.ID] == nil {
				sub[v.ID] = expected.Args[index]
			}
		}
	}
	for _, arg := range args {
		if c.contextual(arg.Value) {
			continue
		}
		actual := c.independentArgument(arg.Value)
		if actual == nil {
			continue
		}
		for _, field := range fields {
			if field.Name != arg.Name || c.errorAssignable(actual.Type, Sub(field.Type, sub)) {
				continue
			}
			target := Sub(field.Type, sub)
			if !c.unifyArgument(target, actual.Type, variableSet(vars), sub) && mentionsVariable(target, variableSet(vars)) {
				c.error(arg.Pos, "type", "constructor arguments conflict with expected type")
			}
		}
	}
	actualArgs := []*Type{}
	for _, v := range vars {
		a := sub[v.ID]
		if a == nil {
			c.error(pos, "type", "cannot infer constructor type argument "+v.Name)
			a = primitive("<invalid>")
		}
		actualArgs = append(actualArgs, a)
	}
	r := *t
	r.Args = actualArgs
	c.wellFormed(&r, pos, map[string]bool{})
	return &r
}

// Prefer an already optional value. Otherwise check the payload with its own
// context (including empty lists and incomplete data constructors), then wrap
// only the supplied argument. Ordinary expression compatibility stays exact.
func (c *checker) argumentExpression(e *syntax.Expression, expected *Type) *Info {
	if !std(expected, "Optional") || len(expected.Args) != 1 {
		return c.expression(e, expected)
	}
	checkpoint := len(c.Diagnostics)
	info := c.infer(e, expected)
	payload := expected.Args[0]
	if compatible(info.Type, expected) {
		return c.checkExpression(e, info, expected)
	}
	if compatible(info.Type, payload) || c.errorAssignable(info.Type, payload) {
		info = c.checkExpression(e, info, payload)
		info.OptionalArgument = expected
		return info
	}
	if len(c.Diagnostics) == checkpoint || (info.Constructor == nil && e.Kind != syntax.KindList && e.Kind != syntax.KindMap) {
		return c.checkExpression(e, info, expected)
	}
	diagnostics := append([]syntax.Diagnostic(nil), c.Diagnostics[checkpoint:]...)
	c.Diagnostics = c.Diagnostics[:checkpoint]
	info = c.expression(e, payload)
	if len(c.Diagnostics) == checkpoint {
		info.OptionalArgument = expected
		return info
	}
	// Retain the original optional-boundary diagnostics when neither form fits.
	c.Diagnostics = append(c.Diagnostics[:checkpoint], diagnostics...)
	return info
}

// Inference matches the complete optional first, then its payload. Failed
// attempts must not leave substitutions that constrain the second attempt.
func (c *checker) unifyArgument(pattern, actual *Type, vars map[string]bool, sub map[string]*Type) bool {
	attempt := func(target *Type) bool {
		trial := map[string]*Type{}
		for key, value := range sub {
			trial[key] = value
		}
		if !unify(target, actual, vars, trial) {
			return false
		}
		for key, value := range trial {
			sub[key] = value
		}
		return true
	}
	if attempt(pattern) {
		return true
	}
	return std(pattern, "Optional") && len(pattern.Args) == 1 &&
		(c.errorAssignable(actual, Sub(pattern.Args[0], sub)) || attempt(pattern.Args[0]))
}

// Only complete, independently typed arguments contribute inference evidence.
// Context-dependent arguments are checked again against the inferred signature.
func (c *checker) independentArgument(e *syntax.Expression) *Info {
	checkpoint := len(c.Diagnostics)
	info := c.expression(e, nil)
	if len(c.Diagnostics) != checkpoint {
		c.Diagnostics = c.Diagnostics[:checkpoint]
		return nil
	}
	return info
}
