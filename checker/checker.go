package checker

import (
	"encoding/hex"
	"fmt"
	msruntime "github.com/manuscript-lang/manuscript/runtime"
	"github.com/manuscript-lang/manuscript/syntax"
	"math"
	"strconv"
	"strings"
)

type scope struct {
	parent   *scope
	bindings map[string]*Binding
	types    map[string]*Type
}

func newScope(parent *scope) *scope {
	return &scope{parent: parent, bindings: map[string]*Binding{}, types: map[string]*Type{}}
}
func (s *scope) binding(name string) *Binding {
	for ; s != nil; s = s.parent {
		if b := s.bindings[name]; b != nil {
			return b
		}
	}
	return nil
}
func (s *scope) typ(name string) *Type {
	for ; s != nil; s = s.parent {
		if s.bindings[name] != nil {
			return nil
		}
		if t := s.types[name]; t != nil {
			return t
		}
	}
	return nil
}

type checker struct {
	scopeMarker          string
	standardDeclarations bool
	*Program
	module                  *syntax.Module
	names                   map[string]*Symbol
	scope                   *scope
	result                  *Type
	function, serial, loops int
	captures                map[int]map[*Binding]bool
}

func Check(modules []*syntax.Module, imports map[*syntax.Import]string) *Program {
	return CheckWithOptions(modules, imports, CheckOptions{})
}
func CheckWithOptions(modules []*syntax.Module, imports map[*syntax.Import]string, options CheckOptions) *Program {
	p := &Program{Flow: map[*syntax.Statement]Flow{}, TypeReferences: map[*syntax.Type]*Type{}, Scopes: map[*syntax.Expression]ScopeState{}, Cleanups: map[*syntax.Statement]*Method{}, Modules: modules, Symbols: map[string]map[string]*Symbol{}, Expressions: map[*syntax.Expression]*Info{}, Bindings: map[*syntax.Pattern]*Binding{}, LoopBindings: map[*syntax.Statement]*Binding{}, ArmBindings: map[*syntax.Arm][]*Binding{}, Parameters: map[*syntax.Declaration][]*Binding{}, LambdaParameters: map[*syntax.Expression][]*Binding{}, Assignments: map[*syntax.Expression]*Binding{}, Self: map[*syntax.Declaration]*Binding{}}
	c := &checker{scopeMarker: options.ScopeMarker, Program: p, captures: map[int]map[*Binding]bool{}}
	p.Methods = append(p.Methods, standardImplementations...)
	p.ContractPatterns = map[*syntax.Arm]*Type{}
	for _, module := range modules {
		c.module = module
		c.names = map[string]*Symbol{}
		p.Symbols[module.File] = c.names
		c.scope = newScope(nil)
		for _, name := range strings.Fields("Bool Int Float String Unit Never Equal Hashable") {
			c.names[name] = &Symbol{Name: name, ID: name, Kind: "type", Type: primitive(name), Export: true}
		}
		for _, item := range module.Imports {
			var found *Symbol
			if strings.HasPrefix(item.Path, "@std/") {
				found = standardModules[item.Path][item.Name]
			} else {
				found = p.Symbols[imports[item]][item.Name]
			}
			if found == nil || !found.Export {
				c.error(item.NamePos, "resolution", "module does not export "+item.Name)
				continue
			}
			c.addSymbol(item.Name, found, item.NamePos)
		}
		for _, d := range module.Declarations {
			if d.Kind == "impl" || d.Kind == "test" {
				continue
			}
			s := &Symbol{Name: d.Name, ID: c.unique("symbol"), Kind: "fn", Module: module.File, Export: d.Export, Decl: d}
			if d.Kind != "fn" {
				s.Kind = "type"
				kind := d.Kind
				if kind == "interface" {
					kind = "contract"
				}
				def := &Definition{Symbol: s, Kind: kind}
				s.Type = &Type{Name: d.Name, ID: "module/" + hex.EncodeToString([]byte(module.File)) + "#" + d.Name, Kind: kind, Def: def}
			}
			c.addSymbol(d.Name, s, d.Pos)
		}
		for _, d := range module.Declarations {
			if d.Kind == "impl" || d.Kind == "test" {
				continue
			}
			s := c.names[d.Name]
			if s.Decl != d {
				continue
			}
			old := c.scope
			c.scope = newScope(nil)
			s.Variables = c.typeVariables(d.TypeParams)
			if s.Kind == "type" {
				s.Type.Def.Variables = s.Variables
				s.Type.Args = s.Variables
			}
			c.scope = old
		}
		for _, d := range module.Declarations {
			if d.Kind == "impl" || d.Kind == "test" {
				continue
			}
			s := c.names[d.Name]
			if s.Decl != d {
				continue
			}
			old := c.scope
			c.scope = c.variableScope(s.Variables)
			if s.Kind == "fn" {
				s.Type = c.signature(d.Params, d.Result)
			} else {
				def := s.Type.Def
				def.Fields = c.params(d.Fields)
				seen := map[string]bool{}
				for _, cs := range d.Cases {
					if seen[cs.Name] {
						c.error(cs.Pos, "type", "duplicate case "+cs.Name)
					}
					seen[cs.Name] = true
					def.Cases = append(def.Cases, Case{cs.Name, c.params(cs.Fields)})
				}
				seen = map[string]bool{}
				for _, m := range d.Methods {
					if seen[m.Name] {
						c.error(m.Pos, "type", "duplicate operation "+m.Name)
					}
					seen[m.Name] = true
					def.Operations = append(def.Operations, Param{m.Name, c.signature(m.Params, m.Result)})
				}
			}
			c.scope = old
		}
		for _, d := range module.Declarations {
			if d.Kind == "impl" {
				c.implementation(d)
			}
		}
		for _, d := range module.Declarations {
			if d.Kind == "fn" {
				s := c.names[d.Name]
				if s.Decl == d {
					c.checkFunction(d, s.Type, s.Variables, nil)
				}
			}
			if d.Kind == "test" {
				c.checkFunction(d, function(nil, primitive("Unit")), nil, nil)
			}
		}
		for _, m := range c.Methods {
			if m.Decl != nil && m.Module == module.File {
				c.checkFunction(m.Decl, m.Type, m.Variables, m.Receiver)
			}
		}
		c.declarationChecks(module)
	}
	c.finiteApplications()
	if len(c.Diagnostics) == 0 {
		c.effectSummaries()
	}
	return p
}
func (c *checker) unique(prefix string) string {
	c.serial++
	return fmt.Sprintf("%s%d", prefix, c.serial)
}
func (c *checker) error(pos syntax.Position, phase, message string) {
	c.Diagnostics = append(c.Diagnostics, syntax.Diagnostic{Position: pos, Phase: phase, Message: message})
}
func (c *checker) addSymbol(name string, s *Symbol, pos syntax.Position) {
	if c.names[name] != nil {
		c.error(pos, "resolution", "duplicate or intrinsic name "+name)
		return
	}
	c.names[name] = s
}
func (c *checker) variableScope(vars []*Type) *scope {
	s := newScope(nil)
	for _, v := range vars {
		s.types[v.Name] = v
	}
	return s
}
func (c *checker) typeVariables(params []syntax.TypeParameter) []*Type {
	var vars []*Type
	for _, p := range params {
		if c.names[p.Name] != nil && c.names[p.Name].Module == "" || c.scope.types[p.Name] != nil {
			c.error(p.Pos, "resolution", "duplicate or intrinsic type parameter "+p.Name)
		}
		v := &Type{Name: p.Name, ID: c.unique("typevar"), Kind: "variable"}
		vars = append(vars, v)
		c.scope.types[p.Name] = v
	}
	for i, p := range params {
		for _, b := range p.Bounds {
			t := c.resolve(b, true)
			if t.Kind != "contract" && t.ID != "Equal" && t.ID != "Hashable" {
				c.error(b.Pos, "type", "a bound must be a compiler bound or operation contract")
			}
			vars[i].Bounds = append(vars[i].Bounds, t)
		}
	}
	return vars
}
func (c *checker) resolve(t *syntax.Type, bound bool) *Type {
	if t == nil {
		return primitive("<invalid>")
	}
	if t.Name == "fn" {
		return c.signature(t.Params, t.Result)
	}
	var base *Type
	if c.scope.binding(t.Name) != nil {
		c.error(t.Pos, "resolution", "a value shadows type "+t.Name)
		return primitive("<invalid>")
	}
	if v := c.scope.typ(t.Name); v != nil {
		base = v
	} else if s := c.names[t.Name]; s != nil && s.Kind == "type" {
		base = s.Type
	} else {
		c.error(t.Pos, "resolution", "unknown type "+t.Name)
		return primitive("<invalid>")
	}
	if !bound && (base.ID == "Equal" || base.ID == "Hashable") {
		c.error(t.Pos, "type", t.Name+" is a bound, not a value type")
	}
	r := *base
	r.Args = nil
	for _, a := range t.Args {
		r.Args = append(r.Args, c.resolve(a, false))
	}
	arity := 0
	if base.Def != nil {
		arity = len(base.Def.Variables)
	}
	if len(r.Args) != arity {
		c.error(t.Pos, "type", fmt.Sprintf("%s requires %d type arguments", base.Name, arity))
	}
	c.TypeReferences[t] = &r
	return &r
}
func (c *checker) params(params []syntax.Parameter) []Param {
	var result []Param
	seen := map[string]bool{}
	for _, p := range params {
		if seen[p.Name] {
			c.error(p.Pos, "type", "duplicate parameter or field "+p.Name)
		}
		seen[p.Name] = true
		result = append(result, Param{p.Name, c.resolve(p.Type, false)})
	}
	return result
}
func (c *checker) signature(params []syntax.Parameter, result *syntax.Type) *Type {
	return function(c.params(params), c.resolve(result, false))
}
func (c *checker) bind(name string, t *Type, mutable bool, pos syntax.Position) *Binding {
	if c.scope.bindings[name] != nil || c.scope.types[name] != nil {
		c.error(pos, "type", "duplicate local binding "+name)
	}
	b := &Binding{Name: name, ID: c.unique("local") + "_" + name, Type: t, Mutable: mutable, Function: c.function}
	c.scope.bindings[name] = b
	return b
}
func (c *checker) checkFunction(d *syntax.Declaration, t *Type, vars []*Type, receiver *Type) {
	oldScope, oldResult, oldFunction, oldLoops := c.scope, c.result, c.function, c.loops
	c.scope = c.variableScope(vars)
	c.result = t.Result
	c.function = c.serial + 1
	c.serial++
	c.loops = 0
	if receiver != nil {
		c.Self[d] = c.bind("self", receiver, false, d.Pos)
	}
	for i, p := range t.Params {
		pos := d.Pos
		if i < len(d.Params) {
			pos = d.Params[i].Pos
		}
		c.Parameters[d] = append(c.Parameters[d], c.bind(p.Name, p.Type, false, pos))
	}
	fall, _ := c.block(d.Body, false)
	if fall && t.Result.ID != "Unit" {
		c.error(d.Pos, "type", "reachable fallthrough in function returning "+t.Result.String())
	}
	c.scope, c.result, c.function, c.loops = oldScope, oldResult, oldFunction, oldLoops
}
func (c *checker) block(body []*syntax.Statement, nested bool) (fall, breaks bool) {
	old := c.scope
	if nested {
		c.scope = newScope(old)
	}
	fall = true
	for _, s := range body {
		normal, br := c.statement(s)
		if fall {
			breaks = breaks || br
			fall = normal
		}
	}
	c.scope = old
	return
}
func (c *checker) statement(s *syntax.Statement) (fall, breaks bool) {
	defer func() { c.Flow[s] = Flow{fall} }()
	return c.checkStatement(s)
}
func (c *checker) checkStatement(s *syntax.Statement) (bool, bool) {
	switch s.Kind {
	case "bind":
		var expected *Type
		if s.Type != nil {
			expected = c.resolve(s.Type, false)
			c.wellFormed(expected, s.Type.Pos, map[string]bool{})
		}
		info := c.expression(s.Value, expected)
		c.pattern(s.Pattern, info.Type, s.Mutable, s.Value)
		return !info.NoReturn, false
	case "assign":
		b := c.scope.binding(s.Name)
		if b == nil {
			c.error(s.Pos, "resolution", "unknown binding "+s.Name)
			c.expression(s.Value, nil)
			return true, false
		}
		c.Assignments[s.Value] = b
		if !b.Mutable {
			c.error(s.Pos, "type", "cannot assign immutable binding "+s.Name)
		}
		if b.Function != c.function {
			c.error(s.Pos, "type", "cannot assign a captured binding")
		}
		i := c.expression(s.Value, b.Type)
		return !i.NoReturn, false
	case "return":
		if s.Value == nil {
			if c.result.ID != "Unit" {
				c.error(s.Pos, "type", "bare return requires Unit")
			}
		} else {
			c.expression(s.Value, c.result)
		}
		return false, false
	case "call":
		i := c.expression(s.Value, nil)
		return !i.NoReturn, false
	case "break", "continue":
		if c.loops == 0 {
			c.error(s.Pos, "type", s.Kind+" requires an enclosing loop")
		}
		return false, s.Kind == "break"
	case "if":
		i := c.expression(s.Value, primitive("Bool"))
		a, ab := c.block(s.Body, true)
		b, bb := true, false
		if len(s.Else) > 0 {
			b, bb = c.block(s.Else, true)
		}
		return !i.NoReturn && (a || b), ab || bb
	case "while":
		i := c.expression(s.Value, primitive("Bool"))
		c.loops++
		_, br := c.block(s.Body, true)
		c.loops--
		literalTrue := s.Value.Kind == "bool" && s.Value.Text == "true"
		return !i.NoReturn && (!literalTrue || br), false
	case "for":
		i := c.expression(s.Value, nil)
		element := primitive("<invalid>")
		if std(i.Type, "List") || std(i.Type, "Set") {
			if len(i.Type.Args) > 0 {
				element = i.Type.Args[0]
			}
		} else if std(i.Type, "Map") {
			if len(i.Type.Args) == 2 {
				element = standard("MapEntry", i.Type.Args...)
			}
		} else {
			c.error(s.Pos, "type", "for requires List, Set, or Map")
		}
		old := c.scope
		c.scope = newScope(old)
		c.LoopBindings[s] = c.bind(s.Name, element, false, s.Pos)
		c.loops++
		c.block(s.Body, false)
		c.loops--
		c.scope = old
		return !i.NoReturn, false
	case "with":
		i := c.expression(s.Value, nil)
		if !c.closeable(i.Type) {
			c.error(s.Pos, "type", "with requires an explicit Closeable implementation or a contract declaring close() -> Unit")
		}
		methods := c.methods(i.Type, "close")
		var candidates []*Method
		for _, method := range methods {
			if len(method.Type.Params) == 0 && method.Type.Result.ID == "Unit" {
				if method.Contract != nil && std(method.Contract, "Closeable") {
					candidates = []*Method{method}
					break
				}
				candidates = append(candidates, method)
			}
		}
		if len(candidates) == 1 {
			c.Cleanups[s] = candidates[0]
		} else if len(candidates) > 1 {
			c.error(s.Pos, "type", "with cleanup operation is ambiguous; construct an explicit contract view")
		}
		old := c.scope
		c.scope = newScope(old)
		c.LoopBindings[s] = c.bind(s.Name, i.Type, false, s.Pos)
		fall, br := c.block(s.Body, false)
		c.scope = old
		return !i.NoReturn && fall, br
	case "match":
		return c.match(s)
	}
	return true, false
}
func (c *checker) pattern(p *syntax.Pattern, t *Type, mutable bool, source *syntax.Expression) {
	switch p.Kind {
	case "name":
		c.Bindings[p] = c.bind(p.Name, t, mutable, p.Pos)
	case "record":
		if t.Kind != "record" {
			c.error(p.Pos, "type", "record binding requires a record")
			return
		}
		fields := Fields(t)
		seen := map[string]bool{}
		for _, f := range p.Fields {
			if seen[f.Name] {
				c.error(f.Pos, "type", "duplicate record field "+f.Name)
			}
			seen[f.Name] = true
			found := false
			for _, field := range fields {
				if field.Name == f.Name {
					c.pattern(f.Pattern, field.Type, mutable, nil)
					found = true
				}
			}
			if !found {
				c.error(f.Pos, "type", "unknown record field "+f.Name)
			}
		}
	case "list":
		if std(t, "List") && len(t.Args) == 1 {
			if source != nil && source.Kind == "list" && len(source.Elements) != len(p.Elements) {
				c.error(p.Pos, "type", "statically known list length does not match binding")
			}
			for _, child := range p.Elements {
				c.pattern(child, t.Args[0], mutable, nil)
			}
		} else if t.Kind == "pack" {
			if len(t.Args) != len(p.Elements) {
				c.error(p.Pos, "type", "pack binding arity mismatch")
				return
			}
			for i, child := range p.Elements {
				c.pattern(child, t.Args[i], mutable, nil)
			}
		} else {
			c.error(p.Pos, "type", "positional binding requires a list or result pack")
		}
	}
}
func (c *checker) match(s *syntax.Statement) (bool, bool) {
	info := c.expression(s.Value, nil)
	if info.Type.Kind == "contract" {
		return c.matchContract(s, info)
	}
	if info.Type.Kind != "alternative" {
		c.error(s.Pos, "type", "match requires an alternative or contract view")
		return true, false
	}
	cases := Cases(info.Type)
	seen := map[string]bool{}
	fall, breaks := false, false
	wildcard := false
	for index := range s.Arms {
		arm := &s.Arms[index]
		name := arm.Path.Text
		fields := []Param{}
		if name == "_" {
			if wildcard || index != len(s.Arms)-1 || len(seen) == len(cases) {
				c.error(arm.Pos, "type", "unreachable wildcard or wildcard is not last")
			}
			wildcard = true
		} else {
			if arm.Path.Kind == "member" {
				qualified := c.typeExpression(arm.Path.Left)
				if qualified == nil || !Same(qualified, info.Type) {
					c.error(arm.Pos, "type", "pattern belongs to a different alternative")
				}
			}
			found := false
			for _, cs := range cases {
				if cs.Name == name {
					fields = cs.Fields
					found = true
				}
			}
			if !found {
				c.error(arm.Pos, "resolution", "unknown case "+name)
			}
			if seen[name] || wildcard {
				c.error(arm.Pos, "type", "duplicate or unreachable case "+name)
			}
			seen[name] = true
			if len(fields) != len(arm.Names) {
				c.error(arm.Pos, "type", "case payload arity mismatch")
			}
		}
		old := c.scope
		c.scope = newScope(old)
		for i, name := range arm.Names {
			var b *Binding
			if name != "_" && i < len(fields) {
				b = c.bind(name, fields[i].Type, false, arm.Pos)
			}
			c.ArmBindings[arm] = append(c.ArmBindings[arm], b)
		}
		a, br := c.block(arm.Body, false)
		fall = fall || a
		breaks = breaks || br
		c.scope = old
	}
	if !wildcard && len(seen) != len(cases) {
		c.error(s.Pos, "type", "non-exhaustive match")
	}
	return !info.NoReturn && fall, breaks
}

func (c *checker) matchContract(s *syntax.Statement, info *Info) (bool, bool) {
	contract := *info.Type
	seen := map[string]bool{}
	wildcard, fall, breaks := false, false, false
	for index := range s.Arms {
		arm := &s.Arms[index]
		var target *Type
		if arm.Path.Text == "_" {
			if wildcard || index != len(s.Arms)-1 {
				c.error(arm.Pos, "type", "wildcard must appear once and be last")
			}
			wildcard = true
		} else {
			target = c.typeExpression(arm.Path)
			if target == nil || (target.Kind != "record" && target.Kind != "alternative") {
				c.error(arm.Pos, "type", "contract pattern requires a concrete record or alternative type")
				target = nil
			} else {
				if len(target.Def.Variables) > 0 && arm.Path.Kind != "apply" {
					c.error(arm.Pos, "type", "concrete type pattern requires explicit type arguments")
				}
				c.wellFormed(target, arm.Pos, map[string]bool{})
				if !c.implements(target, &contract) {
					c.error(arm.Pos, "type", target.String()+" does not implement "+contract.String())
				}
				key := TypeKey(target)
				if seen[key] || wildcard {
					c.error(arm.Pos, "type", "duplicate or unreachable concrete type pattern")
				}
				seen[key] = true
				c.ContractPatterns[arm] = target
				name := arm.Path
				if name.Kind == "apply" {
					name = name.Left
				}
				c.Expressions[name] = &Info{Type: target, Symbol: target.Def.Symbol}
			}
			if len(arm.Names) != 1 {
				c.error(arm.Pos, "type", "concrete type pattern requires exactly one receiver binding")
			}
		}
		old := c.scope
		c.scope = newScope(old)
		for _, name := range arm.Names {
			var binding *Binding
			if name != "_" && target != nil {
				binding = c.bind(name, target, false, arm.Pos)
			}
			c.ArmBindings[arm] = append(c.ArmBindings[arm], binding)
		}
		a, br := c.block(arm.Body, false)
		fall, breaks = fall || a, breaks || br
		c.scope = old
	}
	if !wildcard {
		c.error(s.Pos, "type", "contract match requires a final wildcard for other implementations")
	}
	return !info.NoReturn && fall, breaks
}
func (c *checker) expression(e *syntax.Expression, expected *Type) *Info {
	i := c.infer(e, expected)
	if i.Type == nil {
		i.Type = primitive("<invalid>")
	}
	if i.Type.ID == "Never" {
		i.NoReturn = true
	}
	if expected != nil && !compatible(i.Type, expected) {
		c.error(e.Pos, "type", formatMismatch(i.Type, expected))
	}
	c.Expressions[e] = i
	return i
}
func (c *checker) infer(e *syntax.Expression, expected *Type) *Info {
	c.captureScope(e)
	i := &Info{}
	if e == nil {
		i.Type = primitive("Unit")
		return i
	}
	switch e.Kind {
	case "number":
		name := "Int"
		if strings.HasSuffix(e.Text, "d") {
			name = "Decimal"
			if s := c.names[name]; s == nil || s != standardSymbols[name] {
				c.error(e.Pos, "resolution", "Decimal literal requires the canonical Decimal import")
			}
			i.Type = standard("Decimal")
			if !msruntime.ValidateDecimalLiteral(e.Text) {
				c.error(e.Pos, "type", "Decimal literal is outside the exact 34-digit representable grid")
			}
		} else if strings.ContainsAny(e.Text, ".eE") {
			name = "Float"
			n, err := strconv.ParseFloat(e.Text, 64)
			if err != nil || math.IsInf(n, 0) {
				c.error(e.Pos, "type", "Float literal is outside finite binary64 range")
			}
			i.Type = primitive(name)
		} else {
			if _, err := strconv.ParseInt(e.Text, 10, 64); err != nil {
				c.error(e.Pos, "type", "Int literal is outside signed 64-bit range")
			}
			i.Type = primitive(name)
		}
	case "bool":
		i.Type = primitive("Bool")
	case "unit":
		i.Type = primitive("Unit")
	case "text":
		i.Type = primitive("String")
		for _, part := range e.Parts {
			if part.Value != nil {
				p := c.expression(part.Value, nil)
				i.NoReturn = i.NoReturn || p.NoReturn
				if !strings.Contains("|String|Bool|Unit|Int|Float|", "|"+p.Type.ID+"|") && !std(p.Type, "Decimal") && p.Type.ID != "Never" {
					c.error(part.Value.Pos, "type", "interpolation requires a formattable scalar")
				}
			}
		}
	case "name":
		if b := c.scope.binding(e.Text); b != nil {
			i.Type = b.Type
			i.Binding = b
			if b.Function != c.function {
				if c.captures[c.function] != nil {
					c.captures[c.function][b] = true
				}
			}
			return i
		}
		if s := c.names[e.Text]; s != nil {
			if s.Kind == "type" {
				c.error(e.Pos, "type", "type name requires a constructor call")
				i.Type = primitive("<invalid>")
			} else {
				i.Type = s.Type
				i.Symbol = s
				if len(s.Variables) > 0 {
					c.error(e.Pos, "type", "a generic function value requires explicit specialization")
				}
				if s.Native == "parallel" {
					c.error(e.Pos, "type", "concurrency binding requires a direct call")
				}
			}
			return i
		}
		typ, cs := c.findCase(e.Text, e.Pos)
		if typ != nil && len(cs.Fields) == 0 {
			i.Constructor = c.instantiate(typ, nil, nil, expected, e.Pos)
			i.Case = cs.Name
			i.Type = i.Constructor
		} else {
			c.error(e.Pos, "resolution", "unknown binding "+e.Text)
		}
	case "apply":
		if callable := c.nativeCallable(e); callable != nil {
			*i = *callable
			i.Type = c.specialize(callable.Type, callable.Method.Variables, c.resolveArguments(e.Types), e.Pos)
			c.Expressions[e.Left] = i
			return i
		}
		if s := c.functionSymbol(e.Left); s != nil {
			args := c.resolveArguments(e.Types)
			i.Symbol = s
			i.Type = c.specialize(s.Type, s.Variables, args, e.Pos)
			i.TypeArgs = args
		} else {
			typ := c.typeExpression(e)
			if typ != nil {
				c.error(e.Pos, "type", "type application requires construction")
				i.Type = typ
			} else {
				c.error(e.Pos, "resolution", "unknown generic declaration")
			}
		}
	case "member":
		if typ := c.typeExpression(e.Left); typ != nil {
			cs, ok := caseOf(typ, e.Text)
			if ok && len(cs.Fields) == 0 {
				i.Constructor = c.instantiate(typ, nil, nil, expected, e.Pos)
				i.Type = i.Constructor
				i.Case = e.Text
				return i
			}
			c.error(e.Pos, "resolution", "unknown or non-nullary alternative case "+e.Text)
			i.Type = primitive("<invalid>")
			return i
		}
		receiver := c.expression(e.Left, nil)
		i.NoReturn = receiver.NoReturn
		for _, f := range Fields(receiver.Type) {
			if receiver.Type.Kind == "record" && f.Name == e.Text {
				i.Type = f.Type
				return i
			}
		}
		if receiver.Type.ID == "Int" && (e.Text == "seconds" || e.Text == "milliseconds" || e.Text == "minutes") {
			i.Type = standard("Duration")
			i.Native = e.Text
			return i
		}
		methods := c.methods(receiver.Type, e.Text)
		if len(methods) != 1 {
			c.error(e.Pos, "resolution", "unknown or ambiguous member "+e.Text)
			return i
		}
		i.Method = methods[0]
		i.Type = methods[0].Type
		i.Native = methods[0].Native
		if methods[0].Native != "" && methods[0].Native != "contract" && len(methods[0].Variables) > 0 {
			c.error(e.Pos, "type", "a generic method value requires explicit specialization")
		}
	case "call":
		return c.call(e, expected)
	case "lambda":
		c.LambdaParameters[e] = nil
		t := c.signature(e.Params, e.Result)
		oldScope, oldResult, oldFunction, oldLoops := c.scope, c.result, c.function, c.loops
		c.scope = newScope(oldScope)
		c.result = t.Result
		c.function = c.serial + 1
		c.serial++
		c.loops = 0
		c.captures[c.function] = map[*Binding]bool{}
		for index, param := range t.Params {
			c.LambdaParameters[e] = append(c.LambdaParameters[e], c.bind(param.Name, param.Type, false, e.Params[index].Pos))
		}
		fall, _ := c.block(e.Body, false)
		if fall && t.Result.ID != "Unit" {
			c.error(e.Pos, "type", "reachable fallthrough in anonymous function")
		}
		i.Type = t
		for b := range c.captures[c.function] {
			i.Captures = append(i.Captures, b)
			if oldFunction != b.Function && c.captures[oldFunction] != nil {
				c.captures[oldFunction][b] = true
			}
		}
		c.scope, c.result, c.function, c.loops = oldScope, oldResult, oldFunction, oldLoops
	case "list":
		if s := c.names["List"]; s == nil || s != standardSymbols["List"] {
			c.error(e.Pos, "resolution", "list literal requires the canonical List import")
		}
		var element *Type
		if std(expected, "List") && len(expected.Args) == 1 {
			element = expected.Args[0]
		}
		if element == nil {
			for _, item := range e.Elements {
				if !c.contextual(item) {
					v := c.expression(item, nil)
					if element == nil && v.Type.ID != "Never" {
						element = v.Type
					}
				}
			}
		}
		if element == nil {
			c.error(e.Pos, "type", "cannot infer list element type")
			element = primitive("<invalid>")
		}
		for _, item := range e.Elements {
			v := c.expression(item, element)
			i.NoReturn = i.NoReturn || v.NoReturn
		}
		i.Type = standard("List", element)
	case "unary":
		if e.Text == "-" && e.Right.Kind == "number" && e.Right.Text == "9223372036854775808" {
			i.Type = primitive("Int")
			c.Expressions[e.Right] = &Info{Type: i.Type}
			return i
		}
		v := c.expression(e.Right, nil)
		i.NoReturn = v.NoReturn
		if e.Text == "not" {
			if !compatible(v.Type, primitive("Bool")) {
				c.error(e.Pos, "type", "not requires Bool")
			}
			i.Type = primitive("Bool")
		} else if e.Text == "try" {
			if !std(v.Type, "Result") || len(v.Type.Args) != 2 {
				c.error(e.Pos, "type", "try requires Result")
			} else {
				if !std(c.result, "Result") || len(c.result.Args) != 2 || !Same(c.result.Args[1], v.Type.Args[1]) {
					c.error(e.Pos, "type", "try requires an enclosing Result with the same error type")
				}
				i.Type = v.Type.Args[0]
			}
		} else {
			if !numeric(v.Type) {
				c.error(e.Pos, "type", "numeric sign requires an independently known numeric operand")
			}
			i.Type = v.Type
		}
	case "binary":
		a := c.expression(e.Left, nil)
		b := c.expression(e.Right, nil)
		i.NoReturn = a.NoReturn || (e.Text != "and" && e.Text != "or" && b.NoReturn)
		if e.Text == "and" || e.Text == "or" {
			i.Type = primitive("Bool")
			if !compatible(a.Type, i.Type) || !compatible(b.Type, i.Type) {
				c.error(e.Pos, "type", "logical operands require Bool")
			}
			return i
		}
		if (e.Text == "+" || e.Text == "-") && (std(a.Type, "Duration") || std(a.Type, "Instant") || std(b.Type, "Duration") || std(b.Type, "Instant")) {
			rows := []struct{ op, left, right, result string }{{"+", "Duration", "Duration", "Duration"}, {"-", "Duration", "Duration", "Duration"}, {"+", "Instant", "Duration", "Instant"}, {"-", "Instant", "Duration", "Instant"}, {"-", "Instant", "Instant", "Duration"}}
			matches := 0
			for _, row := range rows {
				if row.op == e.Text && compatible(a.Type, standard(row.left)) && compatible(b.Type, standard(row.right)) {
					i.Type = standard(row.result)
					matches++
				}
			}
			if matches != 1 {
				c.error(e.Pos, "type", "known operands must select exactly one time arithmetic operation")
			}
			return i
		}
		common := a.Type
		if common.ID == "Never" {
			common = b.Type
		}
		if common.ID == "Never" || !compatible(a.Type, common) || !compatible(b.Type, common) {
			c.error(e.Pos, "type", "operator operands require the same independently known type")
		}
		if e.Text == "==" || e.Text == "!=" {
			i.Type = primitive("Bool")
			if !c.property(common, "Equal", nil) {
				c.error(e.Pos, "type", "equality requires Equal operands")
			}
		} else if strings.Contains("|<|<=|>|>=|", "|"+e.Text+"|") {
			i.Type = primitive("Bool")
			if !numeric(common) && !std(common, "Duration") && !std(common, "Instant") {
				c.error(e.Pos, "type", "ordering requires numeric or time operands")
			}
		} else {
			i.Type = common
			if !numeric(common) && !(std(common, "Duration") && (e.Text == "+" || e.Text == "-")) {
				c.error(e.Pos, "type", "arithmetic requires numeric operands")
			}
			if e.Text == "%" && common.ID != "Int" {
				c.error(e.Pos, "type", "remainder requires Int operands")
			}
		}
	default:
		c.error(e.Pos, "type", "unsupported expression "+e.Kind)
	}
	if i.Type != nil && i.Type.ID == "Never" {
		i.NoReturn = true
	}
	return i
}
func numeric(t *Type) bool {
	return t != nil && (t.ID == "Int" || t.ID == "Float" || std(t, "Decimal"))
}
func (c *checker) resolveArguments(args []*syntax.Type) []*Type {
	var result []*Type
	for _, a := range args {
		t := c.resolve(a, false)
		c.wellFormed(t, a.Pos, map[string]bool{})
		result = append(result, t)
	}
	return result
}
func (c *checker) functionSymbol(e *syntax.Expression) *Symbol {
	if e.Kind == "name" && c.scope.binding(e.Text) == nil {
		if s := c.names[e.Text]; s != nil && s.Kind == "fn" {
			return s
		}
	}
	return nil
}
func (c *checker) typeExpression(e *syntax.Expression) *Type {
	if e == nil {
		return nil
	}
	if e.Kind == "name" && c.scope.binding(e.Text) == nil {
		if v := c.scope.typ(e.Text); v != nil {
			return v
		}
		if s := c.names[e.Text]; s != nil && s.Kind == "type" {
			return s.Type
		}
	}
	if e.Kind == "apply" {
		t := c.typeExpression(e.Left)
		if t != nil {
			r := *t
			r.Args = c.resolveArguments(e.Types)
			if r.Def == nil || len(r.Args) != len(r.Def.Variables) {
				c.error(e.Pos, "type", "generic type arity mismatch")
			}
			return &r
		}
	}
	return nil
}
func caseOf(t *Type, name string) (Case, bool) {
	for _, cs := range Cases(t) {
		if cs.Name == name {
			return cs, true
		}
	}
	return Case{}, false
}
func (c *checker) findCase(name string, pos syntax.Position) (*Type, Case) {
	var found *Type
	var cs Case
	for _, s := range c.names {
		if s.Kind == "type" && s.Type.Kind == "alternative" {
			if candidate, ok := caseOf(s.Type, name); ok {
				if found != nil {
					c.error(pos, "resolution", "ambiguous alternative case "+name)
					return nil, Case{}
				}
				found = s.Type
				cs = candidate
			}
		}
	}
	return found, cs
}
func (c *checker) contextual(e *syntax.Expression) bool {
	if e.Kind == "list" {
		if len(e.Elements) == 0 {
			return true
		}
		for _, a := range e.Elements {
			if !c.contextual(a) {
				return false
			}
		}
		return true
	}
	if e.Kind == "name" {
		return c.scope.binding(e.Text) == nil && c.names[e.Text] == nil
	}
	if e.Kind == "call" {
		if e.Left.Kind == "name" && (e.Left.Text == "ok" || e.Left.Text == "error") {
			return c.names[e.Left.Text] == nil && c.scope.binding(e.Left.Text) == nil
		}
	}
	return false
}
