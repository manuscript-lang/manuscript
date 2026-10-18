package checker

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"sync"

	"github.com/manuscript-lang/manuscript/internal/nativeabi"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

var standardSymbols map[string]*Symbol
var standardModules map[string]map[string]*Symbol
var standardSources []*syntax.Module
var intrinsicOperations map[string]*Type
var standardImplementations []*Method
var standardSourceModules = map[string]*syntax.Module{}

// Bundled source modules are checked lazily, once per process, the first time a
// program (or tool) needs them. The annotated trees, symbols, and methods are
// then shared by every later program instead of being checked again.
var standardMu sync.Mutex
var standardDone = map[string]*standardResult{}
var standardChecking = map[string]bool{}

type standardResult struct {
	symbols map[string]*Symbol
	exports map[string]*Symbol
	methods []*Method
}

var standardOperationVariables = map[string][]*Type{}
var standardReceiverBindings map[string]string
var standardReceiverRequirements map[string][]receiverRequirement

type receiverRequirement struct {
	Variable, Constraint *Type
}

type standardBindings struct {
	NativeTypes        map[string]string `json:"native_types"`
	FunctionOverrides  map[string]string `json:"function_overrides"`
	IntrinsicReceivers map[string]string `json:"intrinsic_receivers"`
	// ContractMethods names the native identity shared by every standard
	// implementation of a contract method, keyed Contract/method.
	ContractMethods      map[string]string            `json:"contract_methods"`
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
	standardDone = map[string]*standardResult{}
	standardSymbols = map[string]*Symbol{}
	standardModules = map[string]map[string]*Symbol{}
	intrinsicOperations = map[string]*Type{}
	standardImplementations = nil
	standardReceiverBindings = map[string]string{}
	standardReceiverRequirements = map[string][]receiverRequirement{}
	bindings, err := readStandardBindings()
	if err != nil {
		return err
	}
	modules, err := parseStandardSources()
	if err != nil {
		return err
	}
	l := &standardLoader{bindings: bindings, c: &checker{standardDeclarations: true, Program: newProgram(nil), captures: map[int]map[*Binding]bool{}}}
	for _, module := range modules {
		if err := l.register(module); err != nil {
			return err
		}
	}
	l.declareIdentities()
	l.resolveDeclarations()
	for _, step := range []func() error{l.bindImplementations, l.bindReceivers, l.checkDefaults} {
		if err := step(); err != nil {
			return err
		}
	}
	return nil
}

// standardLoader builds the native standard declarations in phases.
type standardLoader struct {
	bindings standardBindings
	c        *checker
}

func readStandardBindings() (standardBindings, error) {
	var bindings standardBindings
	data, err := stdlib.Sources.ReadFile("bindings.json")
	if err != nil {
		return bindings, err
	}
	if err = json.Unmarshal(data, &bindings); err != nil {
		return bindings, err
	}
	return bindings, nil
}

// parseStandardSources parses the bundled declarations concurrently and
// returns them in file order.
func parseStandardSources() ([]*syntax.Module, error) {
	files, err := stdlib.Sources.ReadDir(".")
	if err != nil {
		return nil, err
	}
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
	modules := make([]*syntax.Module, len(results))
	for i, result := range results {
		if result.err != nil {
			return nil, result.err
		}
		modules[i] = result.module
		if err := foldInherentImpls(result.module); err != nil {
			return nil, err
		}
	}
	return modules, nil
}

// foldInherentImpls moves the methods of each `impl Type:` block into the
// declaration of Type in the same module. Bundled receiver operations are
// bound to native code by type and method name, so they keep one record per
// type regardless of how the source spells them.
func foldInherentImpls(module *syntax.Module) error {
	types := map[string]*syntax.Declaration{}
	for _, d := range module.Declarations {
		if d.Kind != syntax.KindImpl && d.Kind != syntax.KindTest && d.Kind != syntax.KindFn {
			types[d.Name] = d
		}
	}
	kept := module.Declarations[:0]
	for _, d := range module.Declarations {
		if d.Kind != syntax.KindImpl || d.Contract != nil {
			kept = append(kept, d)
			continue
		}
		target := types[d.Receiver.Name]
		if target == nil || target.Kind == syntax.KindInterface {
			return fmt.Errorf("inherent impl must name a type declared in the same module: %s", d.Pos)
		}
		if len(d.Receiver.Args) != len(target.TypeParams) {
			return fmt.Errorf("inherent impl must repeat the type parameters of %s: %s", target.Name, d.Pos)
		}
		for i, argument := range d.Receiver.Args {
			if argument.Name != target.TypeParams[i].Name || len(argument.Args) > 0 {
				return fmt.Errorf("inherent impl must repeat the type parameters of %s: %s", target.Name, d.Pos)
			}
		}
		target.Methods = append(target.Methods, d.Methods...)
	}
	module.Declarations = kept
	return nil
}

// register records one bundled module: a source module is checked later, on
// demand; a native module contributes its declarations now.
func (l *standardLoader) register(module *syntax.Module) error {
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
		return nil
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
			// Identities are module/name unless bindings.json overrides them.
			native = strings.TrimSuffix(strings.TrimPrefix(module.File, "@std/"), ".ms") + "/" + d.Name
			if override := l.bindings.FunctionOverrides[module.File+"/"+d.Name]; override != "" {
				native = override
			}
			s.Kind = syntax.KindFn
			s.Native = native
			s.ID = "@std/" + native
		} else {
			if nativeKind := l.bindings.NativeTypes[module.File+"/"+d.Name]; nativeKind != "" {
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

	return nil
}

// scopeModule opens the declaration scope of a native module: primitives, the
// prelude, its imports, and its own declarations.
func (l *standardLoader) scopeModule(module *syntax.Module) {
	c := l.c
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
		if isPreludeSymbol(found) {
			c.redundantPreludeImport(module, item)
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

// declareIdentities declares every native nominal identity before any is resolved.
func (l *standardLoader) declareIdentities() {
	c := l.c
	// All nominal identities are declared first, so standard contracts may refer to
	// one another without bootstrapping a second, hidden Go type schema.
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			continue
		}
		l.scopeModule(module)
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
}

// resolveDeclarations fills in native type variables, fields, cases, and
// operation signatures.
func (l *standardLoader) resolveDeclarations() {
	c := l.c
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			continue
		}
		l.scopeModule(module)
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
			c.typeDefaults(d.TypeParams, s.Variables)
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
				c.typeDefaults(method.TypeParams, variables)
				standardOperationVariables[s.ID+"/"+method.Name] = variables
				def.Operations = append(def.Operations, Operation{Name: method.Name, Type: c.signature(method.Params, method.Result), Decl: method})
			}
		}
	}
}

// bindImplementations checks native impl blocks and ties each to its binding.
func (l *standardLoader) bindImplementations() error {
	c := l.c
	used := map[string]bool{}
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			continue
		}
		l.scopeModule(module)
		for _, d := range module.Declarations {
			if d.Kind != syntax.KindImpl {
				continue
			}
			start := len(c.Methods)
			c.implementation(d)
			for _, method := range c.Methods[start:] {
				key := module.File + "/" + d.Receiver.Name + "/" + d.Contract.Name + "/" + method.Decl.Name
				method.ID = key
				contract := d.Contract.Name + "/" + method.Decl.Name
				method.Native = l.bindings.ContractMethods[contract]
				if method.Native == "" {
					return fmt.Errorf("missing native implementation binding for %s: %s", contract, method.Decl.Pos)
				}
				used[contract] = true
			}
		}
	}
	for contract := range l.bindings.ContractMethods {
		if !used[contract] {
			return fmt.Errorf("unused native implementation binding: %s", contract)
		}
	}
	standardImplementations = append([]*Method{}, c.Methods...)
	if len(c.Diagnostics) > 0 {
		return fmt.Errorf("invalid standard declarations: %v", c.Diagnostics)
	}
	for receiver, name := range l.bindings.IntrinsicReceivers {
		typ := standardSymbols[name]
		if typ == nil {
			return fmt.Errorf("missing intrinsic receiver declaration %s", name)
		}
		intrinsicOperations[receiver] = typ.Type
	}
	return nil
}

// bindReceivers attaches native receiver bindings and their requirements.
func (l *standardLoader) bindReceivers() error {
	c := l.c
	intrinsicNames := map[string]string{}
	for receiver, name := range l.bindings.IntrinsicReceivers {
		intrinsicNames[name] = receiver
	}
	bound := map[string]bool{}
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			continue
		}
		l.scopeModule(module)
		for _, declaration := range module.Declarations {
			if declaration.Kind == syntax.KindImpl {
				continue
			}
			symbol := standardModules[module.File][declaration.Name]
			receiver := declaration.Name
			if name, ok := intrinsicNames[receiver]; ok {
				receiver = name
			}
			for _, method := range declaration.Methods {
				key := module.File + "/" + declaration.Name + "/" + method.Name
				if native := nativeabi.ReceiverBindings[receiver][method.Name]; native != "" {
					standardReceiverBindings[symbol.ID+"/"+method.Name] = native
					bound[receiver+"."+method.Name] = true
				}
				for name, constraint := range l.bindings.ReceiverRequirements[key] {
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
				delete(l.bindings.ReceiverRequirements, key)
			}
		}
	}
	for receiver, operations := range nativeabi.ReceiverBindings {
		for name := range operations {
			if !bound[receiver+"."+name] {
				return fmt.Errorf("unused native receiver binding: %s.%s", receiver, name)
			}
		}
	}
	for key := range l.bindings.ReceiverRequirements {
		return fmt.Errorf("unused native receiver requirement: %s", key)
	}
	return nil
}

// checkDefaults checks native default expressions and folds their constants.
func (l *standardLoader) checkDefaults() error {
	c := l.c
	// Check native default expressions with the ordinary expression checker.
	// Lowering prepares concrete slots before native dispatch; the runtime does
	// not own a second default-expression schema.
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			continue
		}
		l.scopeModule(module)
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
	var nativeModules []*syntax.Module
	for _, module := range standardSources {
		if standardSourceModules[module.File] == nil {
			nativeModules = append(nativeModules, module)
		}
	}
	finishModules(nativeModules)
	if len(c.Diagnostics) > 0 {
		return fmt.Errorf("invalid standard defaults: %v", c.Diagnostics)
	}
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
	if len(variables) != 0 && !closedLiteralDefaults(params) {
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
		info := infoOf(e)
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
			info := infoOf(e.Left)
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

// standardSource checks a bundled source module and the bundled modules it
// imports, once. The caller holds standardMu.
func standardSource(module *syntax.Module) *standardResult {
	if r := standardDone[module.File]; r != nil || standardChecking[module.File] {
		return r
	}
	standardChecking[module.File] = true
	defer delete(standardChecking, module.File)
	for _, item := range module.Imports {
		if dependency := standardSourceModules[item.Path]; dependency != nil {
			standardSource(dependency)
		}
	}
	program := check([]*syntax.Module{module}, nil, CheckOptions{bundled: module})
	if len(program.Diagnostics) > 0 {
		panic(fmt.Errorf("invalid standard implementation %s: %v", module.File, program.Diagnostics))
	}
	r := &standardResult{symbols: program.symbols[module.File], exports: map[string]*Symbol{}}
	for name, symbol := range r.symbols {
		if symbol.Module == module.File {
			r.exports[name] = symbol
		}
	}
	for _, m := range program.Methods {
		if m.Module == module.File {
			r.methods = append(r.methods, m)
		}
	}
	standardDone[module.File] = r
	return r
}

func ensureStandardSource(module *syntax.Module) *standardResult {
	standardMu.Lock()
	defer standardMu.Unlock()
	return standardSource(module)
}

// ensureStandardSources checks every bundled source module, for tools that
// describe the whole library.
func ensureStandardSources() {
	ensureStandard()
	standardMu.Lock()
	defer standardMu.Unlock()
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			standardSource(module)
		}
	}
}

// standardExports returns a standard module's declarations, checking a bundled
// source module on first use.
func standardExports(path string) map[string]*Symbol {
	if module := standardSourceModules[path]; module != nil {
		return ensureStandardSource(module).exports
	}
	return standardModules[path]
}

// allStandardExports describes every standard module; it checks them all.
func allStandardExports() map[string]map[string]*Symbol {
	ensureStandardSources()
	out := map[string]map[string]*Symbol{}
	for path, exports := range standardModules {
		out[path] = exports
	}
	for path, r := range standardDone {
		out[path] = r.exports
	}
	return out
}

// standardSourceMethods lists the methods of every bundled source module.
func standardSourceMethods() []*Method {
	ensureStandardSources()
	var out []*Method
	for _, module := range standardSources {
		if r := standardDone[module.File]; r != nil {
			out = append(out, r.methods...)
		}
	}
	return out
}

// StandardImports lists the modules each standard module imports.
func StandardImports() map[string][]string {
	ensureStandard()
	imports := map[string][]string{}
	for _, module := range standardSources {
		for _, item := range module.Imports {
			imports[module.File] = append(imports[module.File], item.Path)
		}
	}
	return imports
}

// StandardModules exposes canonical declarations and their source positions to
// tooling, with every bundled module checked. Callers must not mutate the
// returned checked declarations.
func StandardModules() []*syntax.Module {
	ensureStandardSources()
	return append([]*syntax.Module{}, standardSources...)
}

func StandardExports(module string) map[string]*Symbol {
	ensureStandard()
	out := map[string]*Symbol{}
	for name, symbol := range standardExports(module) {
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
	for name := range standardSourceModules {
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

// closedLiteralDefaults reports whether every expression default is a literal,
// which does not depend on the declaration's type variables.
func closedLiteralDefaults(params []syntax.Parameter) bool {
	for _, p := range params {
		if p.Default == nil {
			continue
		}
		switch p.Default.Kind {
		case syntax.KindBool, syntax.KindNumber, syntax.KindUnit:
		case syntax.KindName:
			if p.Default.Text != "none" {
				return false
			}
		default:
			return false
		}
	}
	return true
}
