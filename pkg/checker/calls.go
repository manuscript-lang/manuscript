package checker

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strings"
)

type checkedArgument struct {
	info        *Info
	diagnostics []syntax.Diagnostic
}

func (c *checker) call(e *syntax.Expression, expected *Type) *Info {
	// Argument checks belong to this call only. Nested calls own
	// their own evidence; callback reuse also requires the same final context.
	previous := c.checkedArguments
	c.checkedArguments = map[*syntax.Expression]checkedArgument{}
	defer func() { c.checkedArguments = previous }()
	i := &Info{}
	callee := e.Left
	if typ := c.typeExpression(callee); typ != nil {
		if typ.Kind == "primitive" || typ.Kind == "variable" {
			c.error(e.Pos, "type", "this type has no source constructor: "+typ.String()+" is built in; write a literal or call a standard function that returns it")
			return i
		}
		if typ.Kind == "contract" {
			typ = c.instantiate(typ, nil, nil, expected, e.Pos)
			i.Arguments = constructorArguments(e.Args, []Param{{Name: "value"}})
			if len(i.Arguments) != 1 || i.Arguments[0].Name != "value" {
				c.error(e.Pos, "type", "contract view requires exactly value: receiver; write "+typ.String()+"(value: x) with one argument labeled value")
				return i
			}
			receiver := c.expression(e.Args[0].Value, nil)
			if !c.implements(receiver.Type, typ) {
				c.error(e.Pos, "type", receiver.Type.String()+" does not implement "+typ.String()+"; declare 'impl "+typ.String()+" for "+receiver.Type.String()+":' with every operation of the interface")
			}
			i.Type = typ
			i.Constructor = typ
			i.Native = "view"
			i.NoReturn = receiver.NoReturn
			return i
		}
		if typ.Kind == "alternative" {
			c.error(e.Pos, "type", "construct an alternative case rather than its type; call one of "+typ.Name+"'s cases: "+list(caseNames(typ), 8))
			return i
		}
		var fields []Param
		fields = Fields(typ)
		if std(typ, "Bytes") {
			fields = []Param{{"values", standard("List", primitive("Int"))}}
		}
		if std(typ, "Task") || std(typ, "BigInt") || std(typ, "Regex") || std(typ, "Timestamp") || std(typ, "SynchronizedGuard") || std(typ, "Instant") || std(typ, "Duration") || std(typ, "Decimal") || std(typ, "OperationId") {
			c.error(e.Pos, "type", "standard type has no source constructor: "+typ.String()+"; create it with a literal or the standard function documented for it (ms doc)")
			return i
		}
		i.Arguments = constructorArguments(e.Args, fields)
		typ = c.instantiate(typ, fields, i.Arguments, expected, e.Pos)
		fields = Fields(typ)
		if std(typ, "Queue") && len(e.Args) == 0 {
			fields = nil
		}
		if std(typ, "Bytes") {
			fields = []Param{{"values", standard("List", primitive("Int"))}}
		}
		i.NoReturn = c.argumentsFor(typ.Name, e.Pos, i.Arguments, fields, ConstructorSignature(typ).Defaults)
		i.Type = typ
		i.Constructor = typ
		return i
	}
	var alternative *Type
	var cs Case
	if callee.Kind == syntax.KindMember {
		alternative = c.typeExpression(callee.Left)
		if alternative != nil {
			if alternative.Kind == "contract" {
				c.error(e.Pos, "resolution", c.interfaceTypeMember(alternative))
				return i
			}
			var ok bool
			cs, ok = caseOf(alternative, callee.Text)
			if !ok {
				c.error(e.Pos, "resolution", "unknown alternative case "+callee.Text+" of "+alternative.Name+"; cases: "+list(caseNames(alternative), 8))
				return i
			}
		}
	}
	if callee.Kind == syntax.KindName && c.scope.binding(callee.Text) == nil && c.names[callee.Text] == nil {
		alternative, cs = c.findCase(callee.Text, callee.Pos)
	}
	if alternative != nil {
		if len(cs.Fields) == 0 {
			c.error(e.Pos, "type", "nullary cases omit call parentheses; write "+cs.Name+" instead of "+cs.Name+"()")
		}
		i.Arguments = constructorArguments(e.Args, cs.Fields)
		alternative = c.instantiate(alternative, cs.Fields, i.Arguments, expected, e.Pos)
		cs, _ = caseOf(alternative, cs.Name)
		i.NoReturn = c.argumentsFor(cs.Name, e.Pos, i.Arguments, cs.Fields)
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
			context := &callInferenceContext{result: signature.Result, expected: expected, pos: e.Pos}
			if !explicit {
				sub := map[string]*Type{}
				c.inferArguments(positionalArguments(functionArguments(e.Args, signature.Params), signature.Params), signature.Params, s.Variables, sub, context)
				for _, v := range s.Variables {
					supplied = append(supplied, sub[v.ID])
				}
			}
			signature = c.specialize(signature, s.Variables, supplied, e.Pos, calleeName(callee))
			if context.conflict {
				signature.Result = primitive("<invalid>")
			}
			i.TypeArgs = supplied
		} else if explicit && len(supplied) > 0 {
			c.error(e.Pos, "type", "nongeneric function cannot take type arguments; remove the [...] after "+s.Name)
		}
		callable = &Info{Type: signature, Symbol: s}
		c.Expressions[callee] = callable
	} else {
		callable = c.nativeCallable(callee)
		if callable != nil {
			if callable.Type.ID == "<invalid>" {
				for _, arg := range e.Args {
					c.expression(arg.Value, nil)
				}
				return callable
			}
			c.specializeNativeCall(e, callable, expected)
		} else {
			callable = c.expression(callee, nil)
		}
		signature = callable.Type
		i.Method = callable.Method
		i.Native = callable.Native
	}
	if signature == nil || signature.Kind != "function" {
		c.notCallable(e, signature)
		return i
	}
	i.Arguments = functionArguments(e.Args, signature.Params)
	i.NoReturn = callable.NoReturn || c.argumentsFor(calleeName(callee), e.Pos, i.Arguments, signature.Params, signature.Defaults)
	i.Type = signature.Result
	if invalidType(i.Type) {
		i.Type = primitive("<invalid>")
	}
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

// positionalArguments labels unlabeled arguments by position when the count
// matches, so inference can proceed while the missing labels are reported once.
func positionalArguments(args []syntax.Argument, params []Param) []syntax.Argument {
	if len(args) != len(params) {
		return args
	}
	resolved := append([]syntax.Argument(nil), args...)
	for index := range resolved {
		if resolved[index].Name == "" {
			resolved[index].Name = params[index].Name
		}
	}
	return resolved
}

// argumentSource returns the source text of the argument starting at pos.
func (c *checker) argumentSource(pos syntax.Position) string {
	source := c.module.Source
	start := pos.Offset
	if start < 0 || start >= len(source) {
		return ""
	}
	depth, quote := 0, false
	for i := start; i < len(source); i++ {
		ch := source[i]
		switch {
		case quote:
			if ch == '\\' {
				i++
			} else if ch == '"' {
				quote = false
			}
		case ch == '"':
			quote = true
		case ch == '(' || ch == '[' || ch == '{':
			depth++
		case ch == ')' || ch == ']' || ch == '}':
			if depth == 0 {
				return strings.TrimSpace(source[start:i])
			}
			depth--
		case ch == ',' && depth == 0, ch == '\n':
			return strings.TrimSpace(source[start:i])
		}
	}
	return strings.TrimSpace(source[start:])
}

// missingLabels explains every unlabeled argument of one call at once.
func (c *checker) missingLabels(callName string, args []syntax.Argument, params []Param) string {
	message := "argument labels are required for this call"
	var parts []string
	for index, arg := range args {
		if index >= len(params) {
			return message
		}
		text := c.argumentSource(arg.Pos)
		switch {
		case arg.Name == "":
			if text == "" {
				text = "..."
			}
			parts = append(parts, params[index].Name+": "+text)
		case text != "" && !strings.HasPrefix(text, arg.Name+":") && text != arg.Name:
			parts = append(parts, arg.Name+": "+text)
		case text != "":
			parts = append(parts, text)
		default:
			parts = append(parts, arg.Name+": ...")
		}
	}
	if callName == "" {
		return message + "; write " + strings.Join(parts, ", ")
	}
	return message + "; write " + callName + "(" + strings.Join(parts, ", ") + ")"
}

// argumentsFor checks a call to the named callable. A missing argument is
// reported at the call, not at the module start, and names the callee.
func (c *checker) argumentsFor(name string, pos syntax.Position, args []syntax.Argument, params []Param, defaults ...map[string]bool) bool {
	c.callName, c.callPos = name, pos
	return c.arguments(args, params, defaults...)
}

func calleeName(e *syntax.Expression) string {
	switch e.Kind {
	case syntax.KindName:
		return e.Text
	case syntax.KindMember:
		if left := calleeName(e.Left); left != "" {
			return left + "." + e.Text
		}
		return e.Text
	case syntax.KindApply:
		return calleeName(e.Left)
	}
	return ""
}

func caseNames(t *Type) []string {
	var names []string
	for _, cs := range Cases(t) {
		names = append(names, cs.Name)
	}
	return names
}

const conflictingInference = "conflicting generic inference; arguments imply different types for one type parameter, so make them the same type or give type arguments explicitly, e.g. f[Int](...)"

// notCallable reports a call whose callee has no function type. An invalid
// callee was already reported where it was written.
func (c *checker) notCallable(e *syntax.Expression, t *Type) {
	if t == nil && e.Left.Kind == syntax.KindName && c.scope.binding(e.Left.Text) == nil && c.names[e.Left.Text] == nil {
		return
	}
	if t != nil && strings.Contains(t.String(), "<invalid>") {
		return
	}
	c.unknownType = true
	message := "callee is not a function"
	if name := calleeName(e.Left); name != "" {
		message = name + " is not a function"
	}
	if t != nil {
		message += " (it has type " + t.String() + ")"
	}
	c.error(e.Pos, "type", message+"; only functions and methods can be called, so remove the (...) or call a function instead")
}

func (c *checker) arguments(args []syntax.Argument, params []Param, defaults ...map[string]bool) bool {
	callName, callPos := c.callName, c.callPos
	c.callName, c.callPos = "", syntax.Position{}
	seen := map[string]bool{}
	noReturn := false
	reportedLabels := false
	for index, arg := range args {
		if arg.Name == "" {
			if index < len(params) {
				seen[params[index].Name] = true
			}
			if !reportedLabels {
				reportedLabels = true
				c.error(arg.Pos, "type", c.missingLabels(callName, args, params))
			}
			v := c.expression(arg.Value, nil)
			noReturn = noReturn || v.NoReturn
			continue
		}
		if seen[arg.Name] {
			c.error(arg.Pos, "type", "duplicate argument "+arg.Name+"; pass each argument once")
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
			c.error(arg.Pos, "type", "unknown argument "+arg.Name+unknownArgumentHint(arg.Name, callName, params))
		}
		v := c.argumentExpression(arg.Value, expected)
		noReturn = noReturn || v.NoReturn
	}
	for _, param := range params {
		if !seen[param.Name] && (len(defaults) == 0 || !defaults[0][param.Name]) {
			pos := callPos
			if pos.File == "" {
				pos = c.modulePosition()
				if len(args) > 0 {
					pos = args[0].Pos
				}
			}
			c.error(pos, "type", "missing argument "+param.Name+missingArgumentHint(param, callName))
		}
	}
	return noReturn
}
func (c *checker) modulePosition() syntax.Position {
	return syntax.Position{File: c.module.File, Line: 1, Column: 1}
}
func (c *checker) specialize(t *Type, vars, args []*Type, pos syntax.Position, name string) *Type {
	sub := map[string]*Type{}
	if len(vars) != len(args) {
		c.error(pos, "type", fmt.Sprintf("generic arity mismatch; expected %d type arguments, found %d", len(vars), len(args)))
	}
	for index, v := range vars {
		var a *Type
		if index < len(args) {
			a = args[index]
		}
		if a == nil {
			c.error(pos, "type", missingTypeArgumentHint(name, v.Name, vars, args))
			a = primitive("<invalid>")
		}
		sub[v.ID] = a
	}
	for _, v := range vars {
		for _, bound := range v.Bounds {
			if !invalidType(sub[v.ID]) && !c.satisfies(sub[v.ID], Sub(bound, sub)) {
				c.error(pos, "type", fmt.Sprintf("%s does not satisfy %s; add 'impl %s for %s:' or pass a type that already implements it", sub[v.ID], Sub(bound, sub), Sub(bound, sub), sub[v.ID]))
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
			if sub[v.ID] == nil && (inferenceTypeKnown(expected.Args[index], c.inferenceVariables) || invalidType(expected.Args[index])) {
				sub[v.ID] = expected.Args[index]
			}
		}
	}
	inferredFields := make([]Param, len(fields))
	for index, field := range fields {
		inferredFields[index] = Param{field.Name, Sub(field.Type, sub)}
	}
	c.inferArguments(args, inferredFields, vars, sub, nil)
	actualArgs := []*Type{}
	for _, v := range vars {
		a := sub[v.ID]
		if a == nil {
			c.error(pos, "type", "cannot infer constructor type argument "+v.Name+"; write the type arguments, e.g. Box[Int](...), or annotate the binding")
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
	checked := c.checkedArguments[e]
	info := checked.info
	if e.Kind == syntax.KindLambda && info != nil && !Same(info.Type, callbackContext(expected)) {
		info = nil // Later inference changed the callback's required signature.
	}
	if info != nil {
		c.Diagnostics = append(c.Diagnostics, checked.diagnostics...)
	}
	if !std(expected, "Optional") || len(expected.Args) != 1 {
		if info != nil {
			return c.checkExpression(e, info, expected)
		}
		return c.expression(e, expected)
	}
	checkpoint := len(c.Diagnostics)
	if info == nil {
		info = c.infer(e, expected)
	}
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
			// A prior failed argument supplies no constraint on later evidence.
			if !invalidType(value) {
				trial[key] = value
			}
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
	if c.checkedArguments != nil {
		c.checkedArguments[e] = checkedArgument{info: info}
	}
	return info
}

func unknownArgumentHint(name, callee string, params []Param) string {
	hint := didYouMean(name, paramNames(params))
	if hint != "" {
		return hint
	}
	in := ""
	if callee != "" {
		in = " of " + callee
	}
	if len(params) == 0 {
		return "; this call takes no arguments"
	}
	return "; parameters" + in + ": " + list(paramNames(params), 12)
}

func missingArgumentHint(param Param, callee string) string {
	in := ""
	if callee != "" {
		in = " in call to " + callee
	}
	return ": " + param.Type.String() + in + "; add '" + param.Name + ": <" + param.Type.String() + ">'"
}

// Constructor shorthand is limited to exactly one declared payload.
func constructorArguments(args []syntax.Argument, params []Param) []syntax.Argument {
	if len(params) == 1 {
		return functionArguments(args, params)
	}
	return args
}
