package checker

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"sync"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

var standardSymbols map[string]*Symbol
var standardModules map[string]map[string]*Symbol
var standardSources []*syntax.Module
var standardTypeReferences map[*syntax.Type]*Type
var intrinsicOperations map[string]*Type
var standardImplementations []*Method
var standardSourceModules = map[string]*syntax.Module{}
var standardSourceMethods []*Method
var standardOperationVariables = map[string][]*Type{}
var standardReceiverBindings map[string]string
var standardReceiverRequirements map[string][]receiverRequirement
var standardDefaults *Program

type receiverRequirement struct {
	Variable, Constraint *Type
}

type standardBindings struct {
	NativeTypes          map[string]string            `json:"native_types"`
	Functions            map[string]string            `json:"functions"`
	IntrinsicReceivers   map[string]string            `json:"intrinsic_receivers"`
	Implementations      map[string]string            `json:"implementations"`
	Receivers            map[string]string            `json:"receivers"`
	ReceiverRequirements map[string]map[string]string `json:"receiver_requirements"`
}

// Standard declarations load on first use rather than at package
// initialization, so commands that never check source start immediately and
// callers can overlap other startup work with loading.
var standardLoad sync.Once

func ensureStandard() {
	standardLoad.Do(func() {
		if err := loadStandardSources(); err != nil {
			panic(err)
		}
	})
}
func loadStandardSources() error {
	standardSources = nil
	standardSourceModules = map[string]*syntax.Module{}
	standardSymbols = map[string]*Symbol{}
	standardModules = map[string]map[string]*Symbol{}
	intrinsicOperations = map[string]*Type{}
	standardImplementations = nil
	standardReceiverBindings = map[string]string{}
	standardReceiverRequirements = map[string][]receiverRequirement{}
	data, err := stdlib.Sources.ReadFile("bindings.json")
	if err != nil {
		return err
	}
	var bindings standardBindings
	if err = json.Unmarshal(data, &bindings); err != nil {
		return err
	}
	files, err := stdlib.Sources.ReadDir(".")
	if err != nil {
		return err
	}
	// Parse declarations concurrently; registration below keeps file order.
	type parsed struct {
		module *syntax.Module
		err    error
	}
	var names []string
	for _, file := range files {
		if strings.HasSuffix(file.Name(), ".ms") {
			names = append(names, file.Name())
		}
	}
	results := make([]parsed, len(names))
	var group sync.WaitGroup
	for i, name := range names {
		group.Add(1)
		go func() {
			defer group.Done()
			data, err := stdlib.Sources.ReadFile(name)
			if err != nil {
				results[i].err = err
				return
			}
			results[i].module, results[i].err = parser.Parse("@std/"+name, string(data))
		}()
	}
	group.Wait()
	for _, result := range results {
		if result.err != nil {
			return result.err
		}
		module := result.module
		standardSources = append(standardSources, module)
		sourceImplementation := false
		for _, d := range module.Declarations {
			if len(d.Body) > 0 {
				sourceImplementation = true
			}
			for _, method := range d.Methods {
				if len(method.Body) > 0 {
					sourceImplementation = true
				}
			}
		}
		if sourceImplementation {
			// Source modules use the ordinary parser and checker, including body,
			// import visibility, default argument, and implementation rules.
			standardSourceModules[module.File] = module
			continue
		}
		standardModules[module.File] = map[string]*Symbol{}
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindImpl {
				for _, method := range d.Methods {
					if len(method.Body) > 0 {
						return fmt.Errorf("native implementations must not have bodies: %s", method.Pos)
					}
				}
				continue
			}
			if d.Kind == syntax.KindTest {
				return fmt.Errorf("standard declarations cannot contain implementation bodies: %s", d.Pos)
			}
			if len(d.Body) > 0 {
				return fmt.Errorf("native declarations must not have bodies: %s", d.Pos)
			}
			for _, method := range d.Methods {
				if len(method.Body) > 0 {
					return fmt.Errorf("native receiver operations must have empty bodies: %s", method.Pos)
				}
			}
			kind := d.Kind
			if kind == "interface" {
				kind = "contract"
			}
			native := d.Name
			id := "@std/" + d.Name
			s := &Symbol{Name: d.Name, ID: id, Kind: syntax.KindType, Module: module.File, Export: d.Export, Native: native, Decl: d}
			if d.Kind == syntax.KindFn {
				native = bindings.Functions[module.File+"/"+d.Name]
				if native == "" {
					return fmt.Errorf("missing native function binding: %s", d.Pos)
				}
				s.Kind = syntax.KindFn
				s.Native = native
				s.ID = "@std/" + native
			} else {
				if nativeKind := bindings.NativeTypes[module.File+"/"+d.Name]; nativeKind != "" {
					kind = nativeKind
				} else if kind == "native" {
					return fmt.Errorf("opaque declaration needs a native binding: %s", d.Pos)
				}
				def := &Definition{Symbol: s, Kind: kind}
				s.Type = &Type{Name: d.Name, ID: s.ID, Kind: kind, Def: def}
				if standardSymbols[d.Name] != nil {
					return fmt.Errorf("duplicate standard type %s", d.Name)
				}
				standardSymbols[d.Name] = s
			}
			if standardModules[module.File][d.Name] != nil {
				return fmt.Errorf("duplicate standard declaration %s", d.Pos)
			}
			standardModules[module.File][d.Name] = s
		}
	}
	c := &checker{standardDeclarations: true, Program: newProgram(nil), captures: map[int]map[*Binding]bool{}}
	scopeModule := func(module *syntax.Module) {
		c.module = module
		c.names = map[string]*Symbol{}
		c.scope = newScope(nil)
		for _, name := range strings.Fields("Bool Int Float String Unit Never") {
			c.names[name] = &Symbol{Name: name, ID: name, Kind: syntax.KindType, Type: primitive(name), Export: true}
		}
		c.addStandardPrelude()
		for _, item := range module.Imports {
			found := standardModules[item.Path][item.Name]
			if found == nil || !found.Export {
				c.error(item.NamePos, "resolution", "standard module does not export "+item.Name)
				continue
			}
			c.addSymbol(item.Name, found, item.NamePos)
		}
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindImpl {
				continue
			}
			c.addSymbol(d.Name, standardModules[module.File][d.Name], d.Pos)
		}
	}
	// All nominal identities are declared first, so standard contracts may refer to
	// one another without bootstrapping a second, hidden Go type schema.
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			continue
		}
		scopeModule(module)
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindImpl {
				continue
			}
			s := standardModules[module.File][d.Name]
			c.scope = newScope(nil)
			for _, p := range d.TypeParams {
				v := &Type{Name: p.Name, ID: s.ID + "/" + p.Name, Kind: "variable"}
				s.Variables = append(s.Variables, v)
				c.scope.types[p.Name] = v
			}
			if s.Kind == syntax.KindType {
				s.Type.Args = s.Variables
				s.Type.Def.Variables = s.Variables
			}
		}
	}
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			continue
		}
		scopeModule(module)
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindImpl {
				continue
			}
			s := standardModules[module.File][d.Name]
			c.scope = c.variableScope(s.Variables)
			for i, p := range d.TypeParams {
				for _, bound := range p.Bounds {
					s.Variables[i].Bounds = append(s.Variables[i].Bounds, c.resolve(bound, true))
				}
			}
			if s.Kind == syntax.KindFn {
				s.Type = c.signature(d.Params, d.Result)
				continue
			}
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
			for _, method := range d.Methods {
				if seen[method.Name] {
					c.error(method.Pos, "type", "duplicate operation "+method.Name)
				}
				seen[method.Name] = true
				c.scope = c.variableScope(s.Variables)
				var variables []*Type
				for _, param := range method.TypeParams {
					if c.scope.types[param.Name] != nil {
						c.error(param.Pos, "type", "native method variable shadows receiver variable")
					}
					variable := &Type{Name: param.Name, ID: s.ID + "/" + method.Name + "/" + param.Name, Kind: "variable"}
					variables = append(variables, variable)
					c.scope.types[param.Name] = variable
				}
				for i, param := range method.TypeParams {
					for _, bound := range param.Bounds {
						variables[i].Bounds = append(variables[i].Bounds, c.resolve(bound, true))
					}
				}
				standardOperationVariables[s.ID+"/"+method.Name] = variables
				def.Operations = append(def.Operations, Param{method.Name, c.signature(method.Params, method.Result)})
			}
		}
	}
	used := map[string]bool{}
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			continue
		}
		scopeModule(module)
		for _, d := range module.Declarations {
			if d.Kind != syntax.KindImpl {
				continue
			}
			start := len(c.Methods)
			c.implementation(d)
			for _, method := range c.Methods[start:] {
				key := module.File + "/" + d.Receiver.Name + "/" + d.Contract.Name + "/" + method.Decl.Name
				method.ID = key
				method.Native = bindings.Implementations[key]
				if method.Native == "" {
					return fmt.Errorf("missing native implementation binding: %s", method.Decl.Pos)
				}
				used[key] = true
			}
		}
	}
	for key := range bindings.Implementations {
		if !used[key] {
			return fmt.Errorf("unused native implementation binding: %s", key)
		}
	}
	standardImplementations = append([]*Method{}, c.Methods...)
	if len(c.Diagnostics) > 0 {
		return fmt.Errorf("invalid standard declarations: %v", c.Diagnostics)
	}
	standardTypeReferences = c.TypeReferences
	for receiver, name := range bindings.IntrinsicReceivers {
		typ := standardSymbols[name]
		if typ == nil {
			return fmt.Errorf("missing intrinsic receiver declaration %s", name)
		}
		intrinsicOperations[receiver] = typ.Type
	}
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			continue
		}
		scopeModule(module)
		for _, declaration := range module.Declarations {
			if declaration.Kind == syntax.KindImpl {
				continue
			}
			symbol := standardModules[module.File][declaration.Name]
			for _, method := range declaration.Methods {
				key := module.File + "/" + declaration.Name + "/" + method.Name
				if native := bindings.Receivers[key]; native != "" {
					standardReceiverBindings[symbol.ID+"/"+method.Name] = native
					delete(bindings.Receivers, key)
				}
				for name, constraint := range bindings.ReceiverRequirements[key] {
					if standardReceiverBindings[symbol.ID+"/"+method.Name] == "" {
						return fmt.Errorf("receiver requirement needs a native binding: %s", key)
					}
					var variable *Type
					for _, candidate := range symbol.Variables {
						if candidate.Name == name {
							variable = candidate
						}
					}
					if variable == nil {
						return fmt.Errorf("unknown receiver variable %s in %s", name, key)
					}
					required := c.names[constraint]
					if required == nil || required.Kind != syntax.KindType {
						return fmt.Errorf("unknown receiver requirement %s in %s", constraint, key)
					}
					standardReceiverRequirements[symbol.ID+"/"+method.Name] = append(standardReceiverRequirements[symbol.ID+"/"+method.Name], receiverRequirement{variable, required.Type})
				}
				delete(bindings.ReceiverRequirements, key)
			}
		}
	}
	for key := range bindings.Receivers {
		return fmt.Errorf("unused native receiver binding: %s", key)
	}
	for key := range bindings.ReceiverRequirements {
		return fmt.Errorf("unused native receiver requirement: %s", key)
	}
	// Check native default expressions with the ordinary expression checker.
	// Lowering prepares concrete slots before native dispatch; the runtime does
	// not own a second default-expression schema.
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			continue
		}
		scopeModule(module)
		for _, declaration := range module.Declarations {
			if declaration.Kind == syntax.KindImpl {
				continue
			}
			symbol := standardModules[module.File][declaration.Name]
			if symbol.Kind == syntax.KindFn {
				c.checkNativeDefaults(declaration, declaration.Params, symbol.Type, symbol.Variables)
			} else {
				c.checkNativeDefaults(declaration, declaration.Fields, ConstructorSignature(symbol.Type), symbol.Variables)
				for _, operation := range symbol.Type.Def.Operations {
					method := standardMethodDeclaration(symbol.Type, operation.Name)
					variables := append(append([]*Type{}, symbol.Variables...), standardOperationVariables[symbol.ID+"/"+operation.Name]...)
					c.checkNativeDefaults(method, method.Params, operation.Type, variables, symbol.Type.Kind == "contract")
				}
			}
		}
	}
	standardDefaults = c.Program
	if len(c.Diagnostics) > 0 {
		return fmt.Errorf("invalid standard defaults: %v", c.Diagnostics)
	}
	// Check all bundled source implementations once to publish documentation and
	// editor symbols. Each application checks its reachable modules afresh so
	// generated identities and mutable analysis maps remain program-local.
	var sourceModules []*syntax.Module
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			sourceModules = append(sourceModules, module)
		}
	}
	program := check(sourceModules, nil, CheckOptions{})
	if len(program.Diagnostics) > 0 {
		return fmt.Errorf("invalid standard implementations: %v", program.Diagnostics)
	}
	for _, module := range program.Modules {
		standardModules[module.File] = map[string]*Symbol{}
		for name, symbol := range program.Symbols[module.File] {
			if symbol.Module == module.File {
				standardModules[module.File][name] = symbol
			}
		}
	}
	for ref, typ := range program.TypeReferences {
		standardTypeReferences[ref] = typ
	}
	standardSourceMethods = program.Methods[len(standardImplementations):]
	return nil
}

func (c *checker) checkNativeDefaults(d *syntax.Declaration, params []syntax.Parameter, t *Type, variables []*Type, contract ...bool) {
	if !hasExtendedDefaults(params) {
		// Existing Optional.none adapters retain their allocation-free path.
		for _, parameter := range params {
			if parameter.Default != nil && parameter.Type.Name != "Optional" {
				c.error(parameter.Pos, "type", "none default requires Optional; use a value matching the declared type")
			}
		}
		return
	}
	// Keep this first native-default slice bounded. Source generic defaults and
	// generic calls through nongeneric standard contracts retain their existing
	// rules; native generic expression defaults need a substitution design.
	if len(variables) != 0 {
		c.error(d.Pos, "type", "native generic expression defaults are not supported; keep '= none' on Optional parameters or use a source wrapper")
		return
	}
	if d.Kind == syntax.KindRecord && t.Result.Kind != syntax.KindRecord {
		c.error(d.Pos, "type", "native opaque constructor expression defaults need a delivery/disposal design; keep Optional.none defaults or use a source wrapper")
		return
	}
	oldScope, oldResult, oldFunction := c.scope, c.result, c.function
	c.scope = c.variableScope(variables)
	c.result = t.Result
	c.serial++
	c.function = c.serial
	c.checkParameters(d, params, t.Params)
	if len(contract) > 0 && contract[0] {
		// Inherited preparation precedes an implementation's own defaults.
		// Keep this bounded interface slice independent and free of effects;
		// combining dependent/effectful defaults needs one ordered prologue.
		for _, parameter := range params {
			if e := parameter.Default; e != nil && !c.closedInterfaceDefault(e) {
				c.error(parameter.Pos, "type", "standard interface expression defaults must be closed literals or bytes from literal text; use a source wrapper for dependent or effectful defaults")
			}
		}
	}
	c.scope, c.result, c.function = oldScope, oldResult, oldFunction
}

func (c *checker) closedInterfaceDefault(e *syntax.Expression) bool {
	switch e.Kind {
	case syntax.KindBool, syntax.KindNumber, syntax.KindUnit:
		return true
	case syntax.KindName:
		info := c.Expressions[e]
		return e.Text == "none" && info != nil && info.Binding == nil && info.Constructor != nil && info.Constructor.ID == "@std/Optional" && info.Case == "none"
	case syntax.KindText:
		for _, part := range e.Parts {
			if part.Value != nil {
				return false
			}
		}
		return true
	case syntax.KindCall:
		if e.Left.Kind == syntax.KindMember && len(e.Args) == 0 {
			info := c.Expressions[e.Left]
			return info != nil && info.Method != nil && info.Method.Native == "to_bytes" && info.Method.Receiver.ID == "String" && c.closedInterfaceDefault(e.Left.Left)
		}
	}
	return false
}

// Extended defaults need source preparation rather than the native none adapter.
func hasExtendedDefaults(params []syntax.Parameter) bool {
	for _, parameter := range params {
		if e := parameter.Default; e != nil && (e.Kind != syntax.KindName || e.Text != "none") {
			return true
		}
	}
	return false
}

// sourceStandardDependencies adds reachable bundled implementations in dependency
// order. Native declarations stay in the immutable standard registry.
func sourceStandardDependencies(modules []*syntax.Module) ([]*syntax.Module, []syntax.Diagnostic) {
	var ordered []*syntax.Module
	var diagnostics []syntax.Diagnostic
	state := map[string]int{}
	var visit func(*syntax.Module)
	visit = func(module *syntax.Module) {
		if state[module.File] == 2 {
			return
		}
		if state[module.File] == 1 {
			diagnostics = append(diagnostics, syntax.Diagnostic{Position: syntax.Position{File: module.File, Line: 1, Column: 1}, Phase: "resolution", Message: "cyclic standard source dependency"})
			return
		}
		state[module.File] = 1
		for _, item := range module.Imports {
			if dependency := standardSourceModules[item.Path]; dependency != nil {
				visit(dependency)
			}
		}
		state[module.File] = 2
		ordered = append(ordered, module)
	}
	for _, module := range modules {
		visit(module)
	}
	return ordered, diagnostics
}

// StandardModules exposes canonical declarations and their source positions to
// tooling. Callers must not mutate the returned checked declarations.
func StandardModules() []*syntax.Module {
	ensureStandard()
	return append([]*syntax.Module{}, standardSources...)
}

// StandardTypeReferences exposes resolved types in canonical standard signatures.
// Callers may change the returned map, but must not mutate the shared types.
func StandardTypeReferences() map[*syntax.Type]*Type {
	ensureStandard()
	out := make(map[*syntax.Type]*Type, len(standardTypeReferences))
	for ref, typ := range standardTypeReferences {
		out[ref] = typ
	}
	return out
}

func StandardExports(module string) map[string]*Symbol {
	ensureStandard()
	out := map[string]*Symbol{}
	for name, symbol := range standardModules[module] {
		if symbol.Export {
			out[name] = symbol
		}
	}
	return out
}
func StandardModuleNames() []string {
	ensureStandard()
	names := []string{}
	for name := range standardModules {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}
func standardMethodDeclaration(t *Type, name string) *syntax.Declaration {
	if t == nil || t.Def == nil || t.Def.Symbol == nil || t.Def.Symbol.Decl == nil {
		return nil
	}
	for _, m := range t.Def.Symbol.Decl.Methods {
		if m.Name == name {
			return m
		}
	}
	return nil
}
