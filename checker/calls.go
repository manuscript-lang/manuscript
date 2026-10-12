package checker

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/syntax"
)

func (c *checker) call(e *syntax.Expression, expected *Type) *Info {
	i := &Info{}
	callee := e.Left
	if typ := c.typeExpression(callee); typ != nil {
		if typ.ID == "Equal" || typ.ID == "Hashable" || typ.Kind == "primitive" || typ.Kind == "variable" {
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
		if std(typ, "BigInt") || std(typ, "Regex") || std(typ, "Timestamp") || std(typ, "Lease") || std(typ, "SynchronizedGuard") || std(typ, "List") || std(typ, "Instant") || std(typ, "Duration") || std(typ, "Decimal") || std(typ, "OperationId") {
			c.error(e.Pos, "type", "standard type has no source constructor")
			return i
		}
		if std(typ, "Background") {
			params := []Param{{"limit", primitive("Int")}}
			optional := map[string]*Type{"reporter": function([]Param{{"failure", standard("BackgroundFailure")}}, primitive("Unit")), "drain": standard("Duration"), "history_limit": primitive("Int")}
			for _, arg := range e.Args {
				if t := optional[arg.Name]; t != nil {
					params = append(params, Param{arg.Name, t})
				}
			}
			i.NoReturn = c.arguments(e.Args, params)
			i.Type = typ
			i.Native = "background"
			return i
		}
		typ = c.instantiate(typ, fields, e.Args, expected, e.Pos)
		if std(typ, "Pool") && len(typ.Args) == 1 && typ.Args[0].Kind != "contract" {
			c.error(e.Pos, "type", "pool construction requires concrete contract views")
		}
		fields = Fields(typ)
		if std(typ, "Bytes") {
			fields = []Param{{"values", standard("List", primitive("Int"))}}
		}
		i.NoReturn = c.arguments(e.Args, fields)
		i.Type = typ
		i.Constructor = typ
		return i
	}
	var alternative *Type
	var cs Case
	if callee.Kind == "member" {
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
	if callee.Kind == "name" && c.scope.binding(callee.Text) == nil && c.names[callee.Text] == nil {
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
	if callee.Kind == "apply" {
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
		if s.Native == "parallel" {
			return c.parallel(e)
		}
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
						if param.Name == arg.Name && !unify(param.Type, actual.Type, vars, sub) {
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
	params := signature.Params
	if s != nil && s.Native == "parallel_map" {
		for _, arg := range e.Args {
			if arg.Name == "timeout" {
				params = append(append([]Param{}, params...), Param{"timeout", standard("Duration")})
			}
		}
	}
	i.NoReturn = callable.NoReturn || c.arguments(i.Arguments, params)
	i.Type = signature.Result
	if i.Type != nil && i.Type.ID == "Never" {
		i.NoReturn = true
	}
	return i
}

// Only a callable with one declared parameter permits an omitted label.
// Keep the source AST intact for tools and repeated checking.
func functionArguments(args []syntax.Argument, params []Param) []syntax.Argument {
	if len(params) != 1 {
		return args
	}
	resolved := append([]syntax.Argument(nil), args...)
	for index := range resolved {
		if resolved[index].Name == "" {
			resolved[index].Name = params[0].Name
		}
	}
	return resolved
}

func (c *checker) arguments(args []syntax.Argument, params []Param) bool {
	seen := map[string]bool{}
	noReturn := false
	for _, arg := range args {
		if arg.Name == "" {
			c.error(arg.Pos, "type", "argument labels are required for this call")
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
		v := c.expression(arg.Value, expected)
		noReturn = noReturn || v.NoReturn
	}
	for _, param := range params {
		if !seen[param.Name] {
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
			if field.Name == arg.Name && !unify(Sub(field.Type, sub), actual.Type, variableSet(vars), sub) {
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
func (c *checker) parallel(e *syntax.Expression) *Info {
	i := &Info{Native: "parallel"}
	var tasks *syntax.Expression
	seen := map[string]bool{}
	for _, a := range e.Args {
		if seen[a.Name] {
			c.error(a.Pos, "type", "duplicate argument "+a.Name)
		}
		seen[a.Name] = true
		switch a.Name {
		case "tasks":
			tasks = a.Value
		case "timeout":
			v := c.expression(a.Value, standard("Duration"))
			i.NoReturn = i.NoReturn || v.NoReturn
		default:
			c.error(a.Pos, "type", "unknown parallel argument "+a.Name)
		}
	}
	pack := &Type{Kind: "pack", Name: "Pack", ID: "pack"}
	if tasks == nil || tasks.Kind != "list" {
		c.error(e.Pos, "type", "parallel tasks must be a bracket literal")
	} else {
		for _, task := range tasks.Elements {
			v := c.expression(task, nil)
			i.NoReturn = i.NoReturn || v.NoReturn
			if v.Type.Kind != "function" || len(v.Type.Params) != 0 {
				c.error(task.Pos, "type", "parallel task requires fn() -> T")
				continue
			}
			pack.Args = append(pack.Args, v.Type.Result)
		}
		c.Expressions[tasks] = &Info{Type: pack}
	}
	i.Type = standard("Result", pack, standard("ExecutionError"))
	return i
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
