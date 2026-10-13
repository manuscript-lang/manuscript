package checker

import (
	"encoding/hex"
	"fmt"
	"github.com/manuscript-lang/manuscript/internal/decimal"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
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
	returnInference         *callbackReturns
	inferenceVariables      map[string]bool
	checkedArguments        map[*syntax.Expression]checkedArgument
	function, serial, loops int
	testFunction            int
	rejectedNames           map[string]bool
	unknownType             bool
	labelMismatch           bool
	reportedImports         map[string]bool
	callName                string
	callPos                 syntax.Position
	captures                map[int]map[*Binding]bool
}

func Check(modules []*syntax.Module, imports map[*syntax.Import]string) *Program {
	return CheckWithOptions(modules, imports, CheckOptions{})
}
func CheckWithOptions(modules []*syntax.Module, imports map[*syntax.Import]string, options CheckOptions) *Program {
	ensureStandard()
	return check(modules, imports, options)
}
func check(modules []*syntax.Module, imports map[*syntax.Import]string, options CheckOptions) *Program {
	modules, dependencyDiagnostics := sourceStandardDependencies(modules)
	p := newProgram(modules)
	p.Diagnostics = dependencyDiagnostics
	if standardDefaults != nil {
		// Immutable checked native defaults are shared; analysis maps themselves
		// remain program-local. Their binding IDs have a separate namespace.
		for e, info := range standardDefaults.Expressions {
			p.Expressions[e] = info
		}
		for d, bindings := range standardDefaults.Parameters {
			p.Parameters[d] = bindings
		}
		for e, bindings := range standardDefaults.LambdaParameters {
			p.LambdaParameters[e] = bindings
		}
		for pattern, binding := range standardDefaults.Bindings {
			p.Bindings[pattern] = binding
		}
		for s, binding := range standardDefaults.LoopBindings {
			p.LoopBindings[s] = binding
		}
		for arm, bindings := range standardDefaults.ArmBindings {
			p.ArmBindings[arm] = bindings
		}
		for arm, typ := range standardDefaults.ContractPatterns {
			p.ContractPatterns[arm] = typ
		}
		for s, method := range standardDefaults.Cleanups {
			p.Cleanups[s] = method
		}
		for s, flow := range standardDefaults.Flow {
			p.Flow[s] = flow
		}
	}
	c := &checker{scopeMarker: options.ScopeMarker, Program: p, captures: map[int]map[*Binding]bool{}}
	for _, module := range modules {
		for _, d := range module.Declarations {
			if d.Kind != syntax.KindInterface && d.Kind != syntax.KindImpl && len(d.Methods) > 0 {
				c.error(d.Pos, "type", "receiver operation declarations require standard-library bindings; move source methods into an explicit 'impl Interface for Type:' block")
			}
		}
	}
	if len(p.Diagnostics) > 0 {
		return p
	}
	p.Methods = append(p.Methods, standardImplementations...)
	for _, module := range modules {
		c.module = module
		c.names = map[string]*Symbol{}
		p.Symbols[module.File] = c.names
		c.scope = newScope(nil)
		for _, name := range strings.Fields("Bool Int Float String Unit Never") {
			c.names[name] = &Symbol{Name: name, ID: name, Kind: syntax.KindType, Type: primitive(name), Export: true}
		}
		c.addStandardPrelude()
		for _, item := range module.Imports {
			var found *Symbol
			if strings.HasPrefix(item.Path, "@std/") {
				if standardSourceModules[item.Path] != nil {
					found = p.Symbols[item.Path][item.Name]
					if found != nil && found.Module != item.Path {
						found = nil
					}
				} else {
					found = standardModules[item.Path][item.Name]
				}
			} else {
				found = p.Symbols[imports[item]][item.Name]
			}
			if found == nil || !found.Export {
				end := item.NamePos
				end.Column += len(item.Name)
				end.Offset += len(item.Name)
				c.Diagnostics = append(c.Diagnostics, syntax.Diagnostic{Position: item.NamePos, End: &end, Phase: "resolution", Message: c.exportMessage(item, imports)})
				continue
			}
			c.addSymbol(item.Name, found, item.NamePos)
		}
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindImpl || d.Kind == syntax.KindTest {
				continue
			}
			s := &Symbol{Name: d.Name, ID: c.unique("symbol"), Kind: syntax.KindFn, Module: module.File, Export: d.Export, Decl: d}
			if d.Kind != syntax.KindFn {
				s.Kind = syntax.KindType
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
			if d.Kind == syntax.KindImpl || d.Kind == syntax.KindTest {
				continue
			}
			s := c.names[d.Name]
			if s.Decl != d {
				continue
			}
			old := c.scope
			c.scope = newScope(nil)
			s.Variables = c.typeVariables(d.TypeParams)
			if s.Kind == syntax.KindType {
				s.Type.Def.Variables = s.Variables
				s.Type.Args = s.Variables
			}
			c.scope = old
		}
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindImpl || d.Kind == syntax.KindTest {
				continue
			}
			s := c.names[d.Name]
			if s.Decl != d {
				continue
			}
			old := c.scope
			c.scope = c.variableScope(s.Variables)
			if s.Kind == syntax.KindFn {
				s.Type = c.signature(d.Params, d.Result)
			} else {
				def := s.Type.Def
				def.Fields = c.params(d.Fields)
				seen := map[string]bool{}
				for _, cs := range d.Cases {
					if seen[cs.Name] {
						c.error(cs.Pos, "type", "duplicate case "+cs.Name+"; rename or remove one of them")
					}
					seen[cs.Name] = true
					def.Cases = append(def.Cases, Case{cs.Name, c.params(cs.Fields)})
				}
				seen = map[string]bool{}
				for _, m := range d.Methods {
					if seen[m.Name] {
						c.error(m.Pos, "type", "duplicate operation "+m.Name+"; rename or remove one of them")
					}
					seen[m.Name] = true
					def.Operations = append(def.Operations, Param{m.Name, c.signature(m.Params, m.Result)})
				}
			}
			c.scope = old
		}
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindImpl {
				c.implementation(d)
			}
		}
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindRecord {
				s := c.names[d.Name]
				if s.Decl == d {
					c.checkFieldDefaults(d, s)
				}
			}
			if d.Kind == syntax.KindInterface {
				for _, method := range d.Methods {
					for _, param := range method.Params {
						if param.Default == nil {
							continue
						}
						old := c.scope
						c.scope = c.variableScope(c.names[d.Name].Variables)
						typ := c.resolve(param.Type, false)
						c.expression(param.Default, typ)
						if typ.ID != "@std/Optional" || param.Default.Kind != syntax.KindName || param.Default.Text != "none" {
							c.error(param.Pos, "type", "interface defaults must be Optional.none; write '= none' or remove the default")
						}
						c.scope = old
					}
				}
			}
		}
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindFn {
				s := c.names[d.Name]
				if s.Decl == d {
					c.checkFunction(d, s.Type, s.Variables, nil)
				}
			}
			if d.Kind == syntax.KindTest {
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
	c.finiteTypeApplications()
	c.finiteApplications()
	c.Diagnostics = uniqueDiagnostics(c.Diagnostics)
	if len(c.Diagnostics) == 0 {
		c.effectSummaries()
	}
	return p
}

func newProgram(modules []*syntax.Module) *Program {
	return &Program{Flow: map[*syntax.Statement]Flow{}, TypeReferences: map[*syntax.Type]*Type{}, Scopes: map[*syntax.Expression]ScopeState{}, Cleanups: map[*syntax.Statement]*Method{}, Modules: modules, Symbols: map[string]map[string]*Symbol{}, Expressions: map[*syntax.Expression]*Info{}, Bindings: map[*syntax.Pattern]*Binding{}, LoopBindings: map[*syntax.Statement]*Binding{}, ArmBindings: map[*syntax.Arm][]*Binding{}, ContractPatterns: map[*syntax.Arm]*Type{}, ArmNameConflicts: map[*syntax.Arm][]*Info{}, Parameters: map[*syntax.Declaration][]*Binding{}, LambdaParameters: map[*syntax.Expression][]*Binding{}, Assignments: map[*syntax.Expression]*Binding{}, Self: map[*syntax.Declaration]*Binding{}}
}
func (c *checker) unique(prefix string) string {
	c.serial++
	if c.standardDeclarations {
		prefix = "standard_" + prefix
	}
	return fmt.Sprintf("%s%d", prefix, c.serial)
}

// importReported records that an import hint for name was given, returning
// whether it had already been given in this check.
func (c *checker) importReported(name string) bool {
	if c.module != nil {
		name = c.module.File + "\x00" + name
	}
	if c.reportedImports[name] {
		return true
	}
	if c.reportedImports == nil {
		c.reportedImports = map[string]bool{}
	}
	c.reportedImports[name] = true
	return false
}
func (c *checker) error(pos syntax.Position, phase, message string) {
	// One missing import is reported once per file: later uses of the same
	// name only repeat the fix already given.
	if _, rest, ok := strings.Cut(message, "; add: import "); ok && phase == "resolution" {
		name, _, _ := strings.Cut(rest, " from ")
		if c.importReported(name) {
			return
		}
	}
	// An unresolved type is already reported where it is written; later
	// diagnostics that only restate its placeholder are noise.
	if c.unknownType && phase != "resolution" && strings.Contains(message, "<invalid>") {
		return
	}
	c.Diagnostics = append(c.Diagnostics, syntax.Diagnostic{Position: pos, Phase: phase, Message: message})
}
func (c *checker) addSymbol(name string, s *Symbol, pos syntax.Position) {
	if c.names[name] != nil {
		c.error(pos, "resolution", "duplicate or intrinsic name "+name+"; this name is already declared, imported, or built in, so rename one of them")
		if c.rejectedNames == nil {
			c.rejectedNames = map[string]bool{}
		}
		c.rejectedNames[name] = true
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
		if c.names[p.Name] != nil && c.names[p.Name].Module == "" || c.scope.types[p.Name] != nil || p.Name == "Equal" || p.Name == "Hashable" {
			c.error(p.Pos, "resolution", "duplicate or intrinsic type parameter "+p.Name+"; choose a different type parameter name")
		}
		v := &Type{Name: p.Name, ID: c.unique("typevar"), Kind: "variable"}
		vars = append(vars, v)
		c.scope.types[p.Name] = v
	}
	for i, p := range params {
		for _, b := range p.Bounds {
			t := c.resolve(b, true)
			if t.Kind != "contract" {
				if t.Kind == "variable" {
					c.error(b.Pos, "type", "a bound must be an interface, but "+b.Name+" resolves to a type parameter; rename the type parameter or name an interface")
				} else if t.ID != "<invalid>" {
					c.error(b.Pos, "type", "a bound must be an interface; write T: SomeInterface where SomeInterface is declared with 'interface'")
				}
				// Invalid bounds cannot supply operations or implementation evidence.
				// Retaining a variable here can create cycles during substitution.
				continue
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
		c.error(t.Pos, "resolution", "a value shadows type "+t.Name+"; rename the local binding so the type name is usable here")
		return primitive("<invalid>")
	}
	if v := c.scope.typ(t.Name); v != nil {
		base = v
	} else if s := c.names[t.Name]; s != nil && s.Kind == syntax.KindType {
		base = s.Type
	} else {
		c.error(t.Pos, "resolution", c.unknownTypeMessage(t.Name))
		c.unknownType = true
		return primitive("<invalid>")
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
		c.error(t.Pos, "type", fmt.Sprintf("%s requires %d type arguments, found %d; write %s", base.Name, arity, len(r.Args), typeSketch(base.Name, arity)))
	}
	c.TypeReferences[t] = &r
	return &r
}
func (c *checker) params(params []syntax.Parameter) []Param {
	var result []Param
	seen := map[string]bool{}
	for _, p := range params {
		if seen[p.Name] {
			c.error(p.Pos, "type", "duplicate parameter or field "+p.Name+"; each name may appear once, so rename one")
		}
		seen[p.Name] = true
		result = append(result, Param{p.Name, c.resolve(p.Type, false)})
	}
	return result
}
func (c *checker) signature(params []syntax.Parameter, result *syntax.Type) *Type {
	t := function(c.params(params), c.resolve(result, false))
	for _, p := range params {
		if p.Default != nil {
			if t.Defaults == nil {
				t.Defaults = map[string]bool{}
			}
			t.Defaults[p.Name] = true
		}
	}
	return t
}
func (c *checker) bind(name string, t *Type, mutable bool, pos syntax.Position) *Binding {
	if c.scope.bindings[name] != nil || c.scope.types[name] != nil {
		c.error(pos, "type", "duplicate local binding "+name+"; this scope already has that name, so choose another name or assign to the existing 'var'")
	}
	if mutable {
		t = requiredType(t)
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
	oldTest := c.testFunction
	c.testFunction = 0
	if d.Kind == syntax.KindTest {
		c.testFunction = c.function
	}
	if receiver != nil {
		c.Self[d] = c.bind("self", receiver, false, d.Pos)
	}
	c.checkParameters(d, d.Params, t.Params)
	fall, _ := c.block(d.Body, false)
	if fall && t.Result.ID != "Unit" && t.Result.ID != "<invalid>" {
		c.error(d.Pos, "type", "reachable fallthrough in function returning "+t.Result.String()+"; end every path with 'return <"+t.Result.String()+">' (or make the last branch return)")
	}
	c.scope, c.result, c.function, c.loops = oldScope, oldResult, oldFunction, oldLoops
	c.testFunction = oldTest
}

func (c *checker) checkFieldDefaults(d *syntax.Declaration, s *Symbol) {
	hasDefault := false
	for _, field := range d.Fields {
		hasDefault = hasDefault || field.Default != nil
	}
	if !hasDefault {
		return
	}
	oldScope, oldResult, oldFunction, oldLoops := c.scope, c.result, c.function, c.loops
	c.scope = c.variableScope(s.Variables)
	c.result = s.Type
	c.serial++
	c.function = c.serial
	c.loops = 0
	c.checkParameters(d, d.Fields, s.Type.Def.Fields)
	c.scope, c.result, c.function, c.loops = oldScope, oldResult, oldFunction, oldLoops
}

func (c *checker) checkParameters(d *syntax.Declaration, params []syntax.Parameter, types []Param) {
	for i, p := range types {
		pos := d.Pos
		if i < len(params) {
			pos = params[i].Pos
		}
		if i < len(params) && params[i].Default != nil {
			c.expression(params[i].Default, p.Type)
		}
		c.Parameters[d] = append(c.Parameters[d], c.bind(p.Name, p.Type, false, pos))
	}
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
	case syntax.KindBind:
		var expected *Type
		if s.Type != nil {
			expected = c.resolve(s.Type, false)
			c.wellFormed(expected, s.Type.Pos, map[string]bool{})
		}
		before := len(c.Diagnostics)
		info := c.expression(s.Value, expected)
		bound := info.Type
		if expected != nil && len(c.Diagnostics) > before && s.Pattern != nil && s.Pattern.Kind == syntax.KindName {
			// A failed initializer must not retype the annotated binding.
			bound = expected
		}
		c.pattern(s.Pattern, bound, s.Mutable, s.Value)
		return !info.NoReturn, info.Breaks
	case syntax.KindAssign:
		if s.Target != nil {
			target := c.expression(s.Target, nil)
			target.Write = true
			receiver := c.Expressions[s.Target.Left]
			if !opaqueField(receiver, s.Target.Text) && (receiver == nil || receiver.Type == nil || receiver.Type.Kind != syntax.KindRecord || (receiver.Symbol != nil && receiver.Symbol.Kind == syntax.KindType) || target.Method != nil) {
				c.error(s.Target.Pos, "type", "assignment requires a record field; only fields of a record value can be assigned with 'x.field = ...'")
			}
			value := c.expression(s.Value, target.Type)
			return !target.NoReturn && !value.NoReturn, target.Breaks || value.Breaks
		}
		b := c.scope.binding(s.Name)
		if b == nil {
			if symbol := c.names[s.Name]; symbol != nil {
				c.error(s.Pos, "type", "cannot assign to "+c.symbolDescription(symbol)+" "+s.Name+"; assignment targets are 'var' bindings and record fields")
			} else {
				c.error(s.Pos, "resolution", c.unknownName(s.Name))
			}
			c.expression(s.Value, nil)
			return true, false
		}
		c.Assignments[s.Value] = b
		if !b.Mutable {
			c.error(s.Pos, "type", "cannot assign immutable binding "+s.Name+"; declare it with 'var "+s.Name+" = ...' instead of 'let'")
		}
		if b.Function != c.function {
			c.error(s.Pos, "type", "cannot assign a captured binding; closures cannot reassign outer variables, so return the new value or keep state in a record field")
		}
		i := c.expression(s.Value, b.Type)
		return !i.NoReturn, i.Breaks
	case syntax.KindReturn:
		if c.returnInference != nil {
			typ := primitive("Unit")
			breaks := false
			if s.Value != nil {
				info := c.checkExpression(s.Value, c.infer(s.Value, c.returnInference.context), nil)
				typ, breaks = info.Type, info.Breaks
			}
			c.returnInference.add(c, typ, s.Pos)
			return false, breaks
		}
		if s.Value == nil {
			if c.result.ID != "Unit" {
				c.error(s.Pos, "type", "bare return requires Unit; this function returns "+c.result.String()+", so write 'return <value>'")
			}
		} else {
			i := c.expression(s.Value, c.result)
			return false, i.Breaks
		}
		return false, false
	case syntax.KindCall:
		var i *Info
		if s.Value.Kind == syntax.KindMatch {
			// A match used as a statement discards its result, so its arms need
			// not agree on a value.
			c.captureScope(s.Value)
			i = c.checkExpression(s.Value, c.matchExpression(s.Value, nil, true), nil)
		} else {
			i = c.expression(s.Value, nil)
		}
		if s.Value.Kind == syntax.KindUnary && s.Value.Text == "try" && i.Type.ID != "Unit" && i.Type.ID != "<invalid>" {
			c.error(s.Value.Pos, "type", "standalone try requires a Unit success value, found "+i.Type.String()+"; use 'let name = try ...' to keep the value or 'return try ...' to return it")
		}
		return !i.NoReturn, i.Breaks
	case syntax.KindBreak, syntax.KindContinue:
		if c.loops == 0 {
			c.error(s.Pos, "type", s.Kind+" requires an enclosing loop; use it only inside 'for' or 'while' bodies")
		}
		return false, s.Kind == syntax.KindBreak
	case syntax.KindIf:
		i := c.expression(s.Value, primitive("Bool"))
		a, ab := c.block(s.Body, true)
		b, bb := true, false
		if len(s.Else) > 0 {
			b, bb = c.block(s.Else, true)
		}
		return !i.NoReturn && (a || b), i.Breaks || ab || bb
	case syntax.KindWhile:
		i := c.expression(s.Value, primitive("Bool"))
		c.loops++
		_, br := c.block(s.Body, true)
		c.loops--
		literalTrue := s.Value.Kind == syntax.KindBool && s.Value.Text == "true"
		return !i.NoReturn && (!literalTrue || br), i.Breaks
	case syntax.KindFor:
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
			c.error(s.Pos, "type", "for requires List, Set, or Map, found "+i.Type.String()+"; iterate a collection, e.g. a list literal [1, 2, 3]")
		}
		old := c.scope
		c.scope = newScope(old)
		c.LoopBindings[s] = c.bind(s.Name, element, false, s.Pos)
		c.loops++
		c.block(s.Body, false)
		c.loops--
		c.scope = old
		return !i.NoReturn, i.Breaks
	case syntax.KindWith:
		i := c.expression(s.Value, nil)
		if !c.closeable(i.Type) {
			c.error(s.Pos, "type", c.withNotCloseableMessage(i.Type))
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
			c.error(s.Pos, "type", "with cleanup operation is ambiguous; wrap the value in an explicit contract view, e.g. Closeable(value: x)")
		}
		old := c.scope
		c.scope = newScope(old)
		c.LoopBindings[s] = c.bind(s.Name, i.Type, false, s.Pos)
		fall, br := c.block(s.Body, false)
		c.scope = old
		return !i.NoReturn && fall, i.Breaks || br
	}
	return true, false
}
func (c *checker) pattern(p *syntax.Pattern, t *Type, mutable bool, source *syntax.Expression) {
	switch p.Kind {
	case syntax.KindName:
		c.Bindings[p] = c.bind(p.Name, t, mutable, p.Pos)
	case syntax.KindRecord:
		if t.Kind != syntax.KindRecord {
			c.error(p.Pos, "type", "record binding requires a record; destructure only record values, or bind the whole value to one name")
			return
		}
		fields := Fields(t)
		seen := map[string]bool{}
		for _, f := range p.Fields {
			if seen[f.Name] {
				c.error(f.Pos, "type", "duplicate record field "+f.Name+"; bind each field once")
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
				c.error(f.Pos, "type", "unknown record field "+f.Name+"; fields: "+list(paramNames(fields), 12))
			}
		}
	case syntax.KindList:
		if std(t, "List") && len(t.Args) == 1 {
			if source != nil && source.Kind == syntax.KindList && len(source.Elements) != len(p.Elements) {
				c.error(p.Pos, "type", "statically known list length does not match binding; bind exactly as many names as the list has elements")
			}
			for _, child := range p.Elements {
				c.pattern(child, t.Args[0], mutable, nil)
			}
		} else {
			c.error(p.Pos, "type", "positional binding requires a list; use [a, b] patterns only with List values")
		}
	}
}
func (c *checker) match(pos syntax.Position, value *syntax.Expression, arms []syntax.Arm, body func(*syntax.Arm) (bool, bool)) (bool, bool) {
	info := c.expression(value, nil)
	if info.Type.Kind == "contract" {
		return c.matchContract(pos, arms, info, body)
	}
	if info.Type.ID == "<invalid>" {
		return false, false
	}
	if info.Type.Kind != "alternative" {
		c.error(pos, "type", "match requires an alternative or contract view, found "+info.Type.String()+"; match on a type with cases, or use if/else")
		return true, false
	}
	cases := Cases(info.Type)
	seen := map[string]bool{}
	fall, breaks := false, false
	wildcard, unknownCase := false, false
	for index := range arms {
		arm := &arms[index]
		c.ArmBindings[arm] = nil
		name := arm.Path.Text
		fields := []Param{}
		if name == "_" {
			if wildcard || index != len(arms)-1 || len(seen) == len(cases) {
				c.error(arm.Pos, "type", "unreachable wildcard or wildcard is not last; keep one '_' arm at the end, and only when cases remain")
			}
			wildcard = true
		} else {
			if arm.Path.Kind == syntax.KindMember {
				qualified := c.typeExpression(arm.Path.Left)
				if qualified == nil || !Same(qualified, info.Type) {
					c.error(arm.Pos, "type", "pattern belongs to a different alternative; qualify arms with the matched type, "+info.Type.Name+".<case>")
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
				unknownCase = true
				if len(arm.Names) == 0 && name != "" && !(name[0] >= 'A' && name[0] <= 'Z') {
					c.error(arm.Pos, "resolution", "'"+name+"' is not a case of "+info.Type.Name+"; use '_' for a catch-all arm (it cannot bind a name); cases: "+list(caseNames(info.Type), 12))
				} else {
					c.error(arm.Pos, "resolution", "unknown case "+name+" of "+info.Type.Name+"; cases: "+list(caseNames(info.Type), 12))
				}
			}
			if seen[name] || wildcard {
				c.error(arm.Pos, "type", "duplicate or unreachable case "+name+"; each case may be matched once and before any '_' arm")
			}
			seen[name] = true
			if len(fields) != len(arm.Names) {
				c.error(arm.Pos, "type", fmt.Sprintf("case payload arity mismatch; %s has %d payload fields, found %d bindings (use _ to ignore one)", name, len(fields), len(arm.Names)))
			}
		}
		c.matchBindingNames(arm, fields)
		old := c.scope
		c.scope = newScope(old)
		for i, name := range arm.Names {
			var b *Binding
			if name != "_" && i < len(fields) {
				b = c.bind(name, fields[i].Type, false, arm.Pos)
			}
			c.ArmBindings[arm] = append(c.ArmBindings[arm], b)
		}
		a, br := body(arm)
		fall = fall || a
		breaks = breaks || br
		c.scope = old
	}
	if !wildcard && !unknownCase && len(seen) != len(cases) {
		c.error(pos, "type", "non-exhaustive match; missing cases: "+list(missingCases(cases, seen), 12)+", or add a final '_' arm")
	}
	return !info.NoReturn && fall, info.Breaks || breaks
}

func (c *checker) matchContract(pos syntax.Position, arms []syntax.Arm, info *Info, body func(*syntax.Arm) (bool, bool)) (bool, bool) {
	contract := *info.Type
	seen := map[string]bool{}
	wildcard, fall, breaks := false, false, false
	for index := range arms {
		arm := &arms[index]
		c.ArmBindings[arm] = nil
		var target *Type
		if arm.Path.Text == "_" {
			if wildcard || index != len(arms)-1 {
				c.error(arm.Pos, "type", "wildcard must appear once and be last; keep a single '_' arm at the end")
			}
			wildcard = true
		} else {
			target = c.typeExpression(arm.Path)
			if target == nil || (target.Kind != syntax.KindRecord && target.Kind != "alternative") {
				c.error(arm.Pos, "type", "contract pattern requires a concrete record or alternative type; name an implementing type like Circle, or use '_'")
				target = nil
			} else {
				if len(target.Def.Variables) > 0 && arm.Path.Kind != syntax.KindApply {
					c.error(arm.Pos, "type", "concrete type pattern requires explicit type arguments; write e.g. Box[Int]")
				}
				c.wellFormed(target, arm.Pos, map[string]bool{})
				if !c.implements(target, &contract) {
					c.error(arm.Pos, "type", target.String()+" does not implement "+contract.String())
				}
				key := TypeKey(target)
				if seen[key] || wildcard {
					c.error(arm.Pos, "type", "duplicate or unreachable concrete type pattern; match each type once and before '_'")
				}
				seen[key] = true
				c.ContractPatterns[arm] = target
				name := arm.Path
				if name.Kind == syntax.KindApply {
					name = name.Left
				}
				c.Expressions[name] = &Info{Type: target, Symbol: target.Def.Symbol}
			}
			if len(arm.Names) != 1 {
				c.error(arm.Pos, "type", "concrete type pattern requires exactly one receiver binding; write 'Type(name):' or 'Type(_):'")
			}
		}
		c.matchBindingNames(arm, []Param{{Type: target}})
		old := c.scope
		c.scope = newScope(old)
		for _, name := range arm.Names {
			var binding *Binding
			if name != "_" && target != nil {
				binding = c.bind(name, target, false, arm.Pos)
			}
			c.ArmBindings[arm] = append(c.ArmBindings[arm], binding)
		}
		a, br := body(arm)
		fall, breaks = fall || a, breaks || br
		c.scope = old
	}
	if !wildcard {
		c.error(pos, "type", "contract match requires a final wildcard for other implementations; add a last '_' arm")
	}
	return !info.NoReturn && fall, info.Breaks || breaks
}
func (c *checker) expression(e *syntax.Expression, expected *Type) *Info {
	return c.checkExpression(e, c.infer(e, expected), expected)
}

func (c *checker) checkExpression(e *syntax.Expression, i *Info, expected *Type) *Info {
	if i.Type == nil {
		i.Type = primitive("<invalid>")
	}
	if i.Type.ID == "Never" {
		i.NoReturn = true
	}
	if expected != nil && i.Type.ID != "<invalid>" && !compatible(i.Type, expected) {
		if c.errorAssignable(i.Type, expected) {
			i.ErrorSource = i.Type
			cause := i.Type
			if std(cause, "Result") && len(cause.Args) == 2 {
				cause = cause.Args[1]
			}
			i.ScopedError = c.errorNeedsScope(cause)
			i.Type = expected
		} else {
			c.error(e.Pos, "type", c.assignmentMismatch(i.Type, expected))
		}
	}
	if expected != nil && expected.Kind == "function" && Same(i.Type, expected) {
		i.Type = expected
	}
	if e != nil && e.Kind != syntax.KindLambda {
		child := func(value *syntax.Expression) {
			if info := c.Expressions[value]; info != nil {
				i.Breaks = i.Breaks || info.Breaks
			}
		}
		child(e.Left)
		child(e.Right)
		for _, arg := range e.Args {
			child(arg.Value)
		}
		for _, element := range e.Elements {
			child(element)
		}
		for _, part := range e.Parts {
			child(part.Value)
		}
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
	case syntax.KindNumber:
		name := "Int"
		if strings.HasSuffix(e.Text, "d") {
			name = "Decimal"
			if s := c.names[name]; s == nil || s != standardSymbols[name] {
				c.error(e.Pos, "resolution", "Decimal literal requires the canonical Decimal import; add: import Decimal from \"@std/decimal.ms\"")
			}
			i.Type = standard("Decimal")
			if !decimal.Valid(e.Text) {
				c.error(e.Pos, "type", "Decimal literal is outside the exact 34-digit representable grid; shorten it to 34 significant digits")
			}
		} else if strings.ContainsAny(e.Text, ".eE") {
			name = "Float"
			n, err := strconv.ParseFloat(e.Text, 64)
			if err != nil || math.IsInf(n, 0) {
				c.error(e.Pos, "type", "Float literal is outside finite binary64 range; use a smaller magnitude (about 1.8e308 at most)")
			}
			i.Type = primitive(name)
		} else {
			if _, err := strconv.ParseInt(e.Text, 10, 64); err != nil {
				c.error(e.Pos, "type", "Int literal is outside signed 64-bit range; use a value between -9223372036854775808 and 9223372036854775807, or BigInt")
			}
			i.Type = primitive(name)
		}
	case syntax.KindBool:
		i.Type = primitive("Bool")
	case syntax.KindUnit:
		i.Type = primitive("Unit")
	case syntax.KindText:
		i.Type = primitive("String")
		for _, part := range e.Parts {
			if part.Value != nil {
				p := c.expression(part.Value, nil)
				i.NoReturn = i.NoReturn || p.NoReturn
			}
		}
	case syntax.KindName:
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
			if s.Kind == syntax.KindType {
				c.error(e.Pos, "type", "type name requires a constructor call; write "+e.Text+"(field: value, ...) to build a value")
				i.Type = primitive("<invalid>")
			} else {
				i.Type = s.Type
				i.Symbol = s
				if len(s.Variables) > 0 {
					c.error(e.Pos, "type", "a generic function value requires explicit specialization; write "+e.Text+"[Type] or call it with arguments")
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
			c.error(e.Pos, "resolution", c.unknownName(e.Text))
		}
	case syntax.KindIndex:
		return c.index(e)
	case syntax.KindMatch:
		return c.matchExpression(e, expected, false)
	case syntax.KindApply:
		if callable := c.nativeCallable(e); callable != nil {
			*i = *callable
			args := c.resolveArguments(e.Types)
			if callable.Type.ID == "<invalid>" {
				return i
			}
			i.Type = c.specialize(callable.Type, callable.Method.Variables, args, e.Pos, calleeName(e))
			c.Expressions[e.Left] = i
			return i
		}
		if s := c.functionSymbol(e.Left); s != nil {
			args := c.resolveArguments(e.Types)
			i.Symbol = s
			i.Type = c.specialize(s.Type, s.Variables, args, e.Pos, calleeName(e))
			i.TypeArgs = args
		} else {
			typ := c.typeExpression(e)
			if typ != nil {
				c.error(e.Pos, "type", "type application requires construction; add (field: value, ...) after the type arguments")
				i.Type = typ
			} else {
				if e.Right != nil {
					return c.index(e)
				}
				if e.Left.Kind == syntax.KindName && c.scope.binding(e.Left.Text) == nil && c.names[e.Left.Text] == nil {
					c.error(e.Left.Pos, "resolution", c.unknownName(e.Left.Text))
					i.Type = primitive("<invalid>")
					return i
				}
				c.error(e.Pos, "resolution", "brackets require type arguments on a generic declaration or one Int index on a List")
			}
		}
	case syntax.KindMember:
		if typ := c.typeExpression(e.Left); typ != nil {
			if typ.Kind == "contract" {
				c.error(e.Pos, "resolution", c.interfaceTypeMember(typ))
				return i
			}
			cs, ok := caseOf(typ, e.Text)
			if ok && len(cs.Fields) == 0 {
				i.Constructor = c.instantiate(typ, nil, nil, expected, e.Pos)
				i.Type = i.Constructor
				i.Case = e.Text
				return i
			}
			c.error(e.Pos, "resolution", "unknown or non-nullary alternative case "+e.Text+" of "+typ.Name+"; cases: "+list(caseNames(typ), 12)+" (cases with payloads need call syntax)")
			i.Type = primitive("<invalid>")
			return i
		}
		receiver := c.expression(e.Left, nil)
		i.NoReturn = receiver.NoReturn
		if receiver.Type.ID == "<invalid>" {
			return i
		}
		for _, f := range Fields(receiver.Type) {
			if receiver.Type.Kind == syntax.KindRecord && f.Name == e.Text && e.Text != "toString" {
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
			c.error(e.Pos, "resolution", c.unknownMember(receiver.Type, e.Text))
			return i
		}
		i.Method = methods[0]
		i.Type = methods[0].Type
		i.Native = methods[0].Native
		if methods[0].Native != "" && methods[0].Native != "contract" && len(methods[0].Variables) > 0 {
			c.error(e.Pos, "type", "a generic method value requires explicit specialization; write the type arguments or call it with arguments")
		}
	case syntax.KindCall:
		return c.call(e, expected)
	case syntax.KindLambda:
		return c.callback(e, expected)
	case syntax.KindList:
		if s := c.names["List"]; s == nil || s != standardSymbols["List"] {
			c.error(e.Pos, "resolution", "list literal requires the canonical List type; rename the shadowing List declaration or binding")
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
			if !c.unknownType {
				c.error(e.Pos, "type", "cannot infer list element type; add an annotation, e.g. let xs: List[Int] = []")
			}
			element = primitive("<invalid>")
		}
		for _, item := range e.Elements {
			v := c.expression(item, element)
			i.NoReturn = i.NoReturn || v.NoReturn
		}
		i.Type = standard("List", element)
	case syntax.KindMap:
		if s := c.names["Map"]; s == nil || s != standardSymbols["Map"] {
			c.error(e.Pos, "resolution", "map literal requires the canonical Map type; rename the shadowing Map declaration or binding")
		}
		var types [2]*Type
		if std(expected, "Map") && len(expected.Args) == 2 {
			copy(types[:], expected.Args)
		}
		for index := range types {
			if types[index] == nil {
				for at := index; at < len(e.Elements); at += 2 {
					item := e.Elements[at]
					if !c.contextual(item) {
						v := c.expression(item, nil)
						if types[index] == nil && v.Type.ID != "Never" {
							types[index] = v.Type
						}
					}
				}
			}
			if types[index] == nil {
				c.error(e.Pos, "type", "cannot infer map key or value type; add an annotation, e.g. let m: Map[String, Int] = {}")
				types[index] = primitive("<invalid>")
			}
		}
		for at, item := range e.Elements {
			v := c.expression(item, types[at%2])
			i.NoReturn = i.NoReturn || v.NoReturn
		}
		i.Type = standard("Map", types[0], types[1])
		c.wellFormed(i.Type, e.Pos, map[string]bool{})
	case syntax.KindUnary:
		if e.Text == "-" && e.Right.Kind == syntax.KindNumber && e.Right.Text == "9223372036854775808" {
			i.Type = primitive("Int")
			c.Expressions[e.Right] = &Info{Type: i.Type}
			return i
		}
		v := c.expression(e.Right, nil)
		i.NoReturn = v.NoReturn
		if e.Text == "not" {
			if !compatible(v.Type, primitive("Bool")) {
				c.error(e.Pos, "type", "not requires Bool, found "+v.Type.String()+"; compare explicitly, e.g. not (x == 0)")
			}
			i.Type = primitive("Bool")
		} else if e.Text == "try" {
			if !std(v.Type, "Result") || len(v.Type.Args) != 2 {
				c.error(e.Pos, "type", "try requires Result, found "+v.Type.String()+"; apply try only to a call returning Result[T, E]")
			} else {
				if c.returnInference != nil {
					c.returnInference.contextDependent = true
				}
				if !std(c.result, "Result") || len(c.result.Args) != 2 {
					if c.testFunction != 0 && c.function == c.testFunction {
						c.error(e.Pos, "type", "try is not available in a test, which cannot return Result; match the result and end the failing arm with 'return panic(message: ...)'")
					} else {
						c.error(e.Pos, "type", "try requires an enclosing Result; declare this function to return Result[T, E] or handle the error with match")
					}
				} else if !Same(c.result.Args[1], v.Type.Args[1]) {
					if c.errorAssignable(v.Type.Args[1], c.result.Args[1]) {
						i.PropagatedError = v.Type.Args[1]
						i.ScopedPropagation = c.errorNeedsScope(v.Type.Args[1])
					} else {
						c.error(e.Pos, "type", "try requires the same error type or an Error boundary implemented by the specific error; this function returns "+c.result.String()+" but the operand fails with "+v.Type.Args[1].String()+", so change the return error type or implement Error for it")
					}
				}
				i.Type = v.Type.Args[0]
			}
		} else {
			if !numeric(v.Type) {
				c.error(e.Pos, "type", "numeric sign requires an independently known numeric operand, found "+v.Type.String()+"; apply + or - to Int, Float, or Decimal")
			}
			i.Type = v.Type
		}
	case syntax.KindBinary:
		a := c.expression(e.Left, nil)
		b := c.expression(e.Right, nil)
		i.NoReturn = a.NoReturn || (e.Text != "and" && e.Text != "or" && b.NoReturn)
		if e.Text == "and" || e.Text == "or" {
			i.Type = primitive("Bool")
			if !compatible(a.Type, i.Type) || !compatible(b.Type, i.Type) {
				c.error(e.Pos, "type", "logical operands require Bool, found "+a.Type.String()+" and "+b.Type.String()+"; compare explicitly, e.g. x != 0")
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
				c.error(e.Pos, "type", "known operands must select exactly one time arithmetic operation; allowed: Duration±Duration, Instant±Duration, Instant-Instant")
			}
			return i
		}
		common := a.Type
		if common.ID == "Never" {
			common = b.Type
		}
		if common.ID == "Never" || !compatible(a.Type, common) || !compatible(b.Type, common) {
			c.error(e.Pos, "type", fmt.Sprintf("operator operands require the same independently known type, found %s %s %s; convert one side so both have one type (e.g. toString() for text, or an Int/Float conversion)", a.Type, e.Text, b.Type))
			c.unknownType = true // later "<invalid>" diagnostics only restate this one
			i.Type = primitive("<invalid>")
			if e.Text == "==" || e.Text == "!=" || strings.Contains("|<|<=|>|>=|", "|"+e.Text+"|") {
				i.Type = primitive("Bool")
			}
			return i
		}
		if e.Text == "==" || e.Text == "!=" {
			i.Type = primitive("Bool")
			if !c.property(common, "Equal", nil) {
				c.error(e.Pos, "type", "equality requires Equal operands; "+common.String()+" has no equality, so add 'impl Equal for "+common.String()+":' or compare fields")
			}
		} else if strings.Contains("|<|<=|>|>=|", "|"+e.Text+"|") {
			i.Type = primitive("Bool")
			if !numeric(common) && common.ID != "String" && !std(common, "Duration") && !std(common, "Instant") {
				c.error(e.Pos, "type", "ordering requires numeric, String, or time operands, found "+common.String()+"; compare a numeric field or convert first")
			}
		} else {
			i.Type = common
			if !numeric(common) && !(common.ID == "String" && e.Text == "+") && !(std(common, "Duration") && (e.Text == "+" || e.Text == "-")) {
				c.error(e.Pos, "type", "arithmetic requires numeric operands")
			}
			if e.Text == "%" && common.ID != "Int" {
				c.error(e.Pos, "type", "remainder requires Int operands, found "+common.String()+"; convert to Int or use math functions")
			}
		}
	default:
		c.error(e.Pos, "type", "unsupported expression "+e.Kind+"; rewrite it with supported syntax (see documentation/core-language)")
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
	if e.Kind == syntax.KindName && c.scope.binding(e.Text) == nil {
		if s := c.names[e.Text]; s != nil && s.Kind == syntax.KindFn {
			return s
		}
	}
	return nil
}
func (c *checker) typeExpression(e *syntax.Expression) *Type {
	if e == nil {
		return nil
	}
	if e.Kind == syntax.KindName && c.scope.binding(e.Text) == nil {
		if v := c.scope.typ(e.Text); v != nil {
			return v
		}
		if s := c.names[e.Text]; s != nil && s.Kind == syntax.KindType {
			// Constructor and qualified-case names bypass expression inference.
			// Retain their resolved identity for import usage and navigation.
			c.Expressions[e] = &Info{Type: s.Type, Symbol: s}
			return s.Type
		}
	}
	if e.Kind == syntax.KindApply {
		t := c.typeExpression(e.Left)
		if t != nil {
			r := *t
			r.Args = c.resolveArguments(e.Types)
			if r.Def == nil || len(r.Args) != len(r.Def.Variables) {
				c.error(e.Pos, "type", "generic type arity mismatch; supply exactly the type arguments the declaration lists")
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
		if s.Kind == syntax.KindType && s.Type.Kind == "alternative" {
			if candidate, ok := caseOf(s.Type, name); ok {
				if found != nil {
					c.error(pos, "resolution", "ambiguous alternative case "+name+"; qualify it with its type, e.g. Type."+name)
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
	if e.Kind == syntax.KindLambda {
		if e.Result == nil {
			return true
		}
		for _, param := range e.Params {
			if param.Type == nil {
				return true
			}
		}
	}
	if e.Kind == syntax.KindList || e.Kind == syntax.KindMap {
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
	if e.Kind == syntax.KindName {
		return c.scope.binding(e.Text) == nil && c.names[e.Text] == nil
	}
	if e.Kind == syntax.KindCall {
		if e.Left.Kind == syntax.KindName && (e.Left.Text == "ok" || e.Left.Text == "error") {
			return c.names[e.Left.Text] == nil && c.scope.binding(e.Left.Text) == nil
		}
	}
	return false
}

func (c *checker) index(e *syntax.Expression) *Info {
	receiver := c.expression(e.Left, nil)
	if receiver.Type.ID == "<invalid>" && e.Right.Kind == syntax.KindName {
		// An unresolved receiver was reported; its bracket argument is probably a type argument.
		return &Info{Type: primitive("<invalid>"), Native: "index", NoReturn: receiver.NoReturn}
	}
	index := c.expression(e.Right, primitive("Int"))
	info := &Info{Type: primitive("<invalid>"), Native: "index", NoReturn: receiver.NoReturn || index.NoReturn}
	if receiver.Type.ID == "<invalid>" {
		return info
	}
	if !std(receiver.Type, "List") || len(receiver.Type.Args) != 1 {
		c.error(e.Pos, "type", "indexing requires List[T]; use the receiver's lookup method for other types")
	} else {
		info.Type = standard("Optional", receiver.Type.Args[0])
	}
	return info
}

func (c *checker) matchExpression(e *syntax.Expression, expected *Type, statement bool) *Info {
	type armState struct {
		arm            *syntax.Arm
		scope          *scope
		normal, breaks bool
		info           *Info
	}
	var states []*armState
	var resultAt syntax.Position
	c.match(e.Pos, e.Left, e.Arms, func(arm *syntax.Arm) (bool, bool) {
		normal, breaks := c.block(arm.Body, false)
		states = append(states, &armState{arm: arm, scope: c.scope, normal: normal, breaks: breaks})
		return normal, breaks
	})
	outer := c.scope
	defer func() { c.scope = outer }()
	checkpoint := len(c.Diagnostics)
	// A statement match discards its value. Arms that agree keep the common
	// type; arms that do not are checked independently.
	discard := func() *Info {
		fall, breaks := false, false
		for _, state := range states {
			c.scope = state.scope
			normal := state.normal
			breaks = breaks || state.breaks
			if normal && state.arm.Value != nil {
				value := c.expression(state.arm.Value, nil)
				breaks = breaks || value.Breaks
				normal = !value.NoReturn
			}
			fall = fall || normal
		}
		scrutinee := c.Expressions[e.Left]
		return &Info{Type: primitive("Unit"), NoReturn: scrutinee.NoReturn || !fall, Breaks: scrutinee.Breaks || (!scrutinee.NoReturn && breaks)}
	}
	result := expected
	if !inferenceTypeKnown(result, c.inferenceVariables) {
		result = nil
	}
	armValue := func(value *syntax.Expression) *Info {
		if result != nil {
			return c.expression(value, result)
		}
		// Generic callback contexts can supply partial evidence, such as the
		// error type in Result[T, String], without fixing the match result.
		return c.checkExpression(value, c.infer(value, expected), nil)
	}
	// Infer from independently typed, reachable arms before checking contextual
	// values such as none or []. Keep each arm's checked lexical scope.
	for _, state := range states {
		c.scope = state.scope
		if !state.normal {
			continue
		}
		if state.arm.Value == nil {
			if result == nil {
				result = primitive("Unit")
			}
		} else if !c.contextual(state.arm.Value) {
			state.info = armValue(state.arm.Value)
			if result == nil && state.info.Type.ID != "Never" && inferenceTypeKnown(state.info.Type, c.inferenceVariables) {
				result = requiredType(state.info.Type)
				resultAt = state.arm.Value.Pos
			}
		}
	}
	fall, breaks := false, false
	for _, state := range states {
		c.scope = state.scope
		normal := state.normal
		breaks = breaks || state.breaks
		if state.arm.Value != nil {
			if state.info == nil {
				state.info = armValue(state.arm.Value)
			}
			if normal {
				breaks = breaks || state.info.Breaks
				normal = !state.info.NoReturn
			}
		} else if normal && result != nil && !compatible(primitive("Unit"), result) {
			c.error(state.arm.Pos, "type", fmt.Sprintf("match arm requires a final value of type %s, because the arm at line %d ends in an expression and makes this match a value; end every arm with a value, or bind the unused result with 'let ignored = ...' so the match stays a statement", result, resultAt.Line))
		}
		fall = fall || normal
	}
	if result == nil {
		if fall {
			if !c.unknownType {
				c.error(e.Pos, "type", "cannot infer match result type; annotate the binding or give an arm an independently known type")
			}
			result = primitive("<invalid>")
		} else {
			result = primitive("Never")
		}
	}
	if statement && len(c.Diagnostics) > checkpoint {
		c.Diagnostics = c.Diagnostics[:checkpoint]
		return discard()
	}
	scrutinee := c.Expressions[e.Left]
	return &Info{Type: result, NoReturn: scrutinee.NoReturn || !fall, Breaks: scrutinee.Breaks || (!scrutinee.NoReturn && breaks)}
}

// symbolDescription names what a module-level declaration is, for diagnostics
// about using it where a variable is required.
func (c *checker) symbolDescription(s *Symbol) string {
	imported := s.Module != c.module.File
	switch {
	case s.Kind == syntax.KindFn && imported:
		return "imported function"
	case s.Kind == syntax.KindFn:
		return "function"
	case s.Kind == syntax.KindType && imported:
		return "imported type"
	case s.Kind == syntax.KindType:
		return "type"
	}
	return "declaration"
}

// uniqueDiagnostics drops repeats of one message at one position, which
// speculative checks of the same expression can produce.
func uniqueDiagnostics(diagnostics []syntax.Diagnostic) []syntax.Diagnostic {
	type key struct {
		position syntax.Position
		message  string
	}
	seen := map[key]bool{}
	result := diagnostics[:0]
	for _, d := range diagnostics {
		k := key{d.Position, d.Message}
		if !seen[k] {
			seen[k] = true
			result = append(result, d)
		}
	}
	return result
}

// opaqueField reports a declared field of a non-record standard type, whose
// member diagnostic already says the field cannot be reached.
func opaqueField(receiver *Info, name string) bool {
	if receiver == nil || receiver.Type == nil || receiver.Type.Kind == syntax.KindRecord {
		return false
	}
	for _, f := range Fields(receiver.Type) {
		if f.Name == name {
			return true
		}
	}
	return false
}
