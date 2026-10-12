package checker

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"

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
var standardOperationVariables = map[string][]*Type{}

type standardBindings struct {
	NativeTypes        map[string]string `json:"native_types"`
	Functions          map[string]string `json:"functions"`
	IntrinsicReceivers map[string]string `json:"intrinsic_receivers"`
	Implementations    map[string]string `json:"implementations"`
}

func init() {
	if err := loadStandardSources(); err != nil {
		panic(err)
	}
}
func loadStandardSources() error {
	standardSymbols = map[string]*Symbol{}
	standardModules = map[string]map[string]*Symbol{}
	intrinsicOperations = map[string]*Type{}
	standardImplementations = nil
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
	for _, file := range files {
		if !strings.HasSuffix(file.Name(), ".ms") {
			continue
		}
		data, err := stdlib.Sources.ReadFile(file.Name())
		if err != nil {
			return err
		}
		module, err := parser.ParseLibrary("@std/"+file.Name(), string(data))
		if err != nil {
			return err
		}
		standardSources = append(standardSources, module)
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
	c := &checker{standardDeclarations: true, Program: &Program{TypeReferences: map[*syntax.Type]*Type{}}, captures: map[int]map[*Binding]bool{}}
	scopeModule := func(module *syntax.Module) {
		c.module = module
		c.names = map[string]*Symbol{}
		c.scope = newScope(nil)
		for _, name := range strings.Fields("Bool Int Float String Unit Never") {
			c.names[name] = &Symbol{Name: name, ID: name, Kind: syntax.KindType, Type: primitive(name), Export: true}
		}
		// Prelude equality names refer to the source-backed interfaces.
		for _, name := range []string{"Equal", "Hashable"} {
			symbol := standardSymbols[name]
			imported := false
			for _, item := range module.Imports {
				if item.Name == name {
					imported = true
				}
			}
			if !imported && symbol.Module != module.File {
				c.names[name] = symbol
			}
		}
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
	// Native adapters implement one omission value: Optional.none. Keep this
	// source contract explicit instead of inferring defaults from field names.
	for _, module := range standardSources {
		for _, declaration := range module.Declarations {
			parameters := append(append([]syntax.Parameter{}, declaration.Params...), declaration.Fields...)
			for _, method := range declaration.Methods {
				parameters = append(parameters, method.Params...)
			}
			for _, parameter := range parameters {
				if parameter.Default == nil {
					continue
				}
				if parameter.Type.Name != "Optional" || parameter.Default.Kind != syntax.KindName || parameter.Default.Text != "none" {
					return fmt.Errorf("native defaults must be Optional.none: %s", parameter.Pos)
				}
			}
		}
	}
	used := map[string]bool{}
	for _, module := range standardSources {
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
	return nil
}

// StandardModules exposes canonical declarations and their source positions to
// tooling. Callers must not mutate the returned checked declarations.
func StandardModules() []*syntax.Module { return append([]*syntax.Module{}, standardSources...) }

// StandardTypeReferences exposes resolved types in canonical standard signatures.
// Callers may change the returned map, but must not mutate the shared types.
func StandardTypeReferences() map[*syntax.Type]*Type {
	out := make(map[*syntax.Type]*Type, len(standardTypeReferences))
	for ref, typ := range standardTypeReferences {
		out[ref] = typ
	}
	return out
}

func StandardExports(module string) map[string]*Symbol {
	out := map[string]*Symbol{}
	for name, symbol := range standardModules[module] {
		if symbol.Export {
			out[name] = symbol
		}
	}
	return out
}
func StandardModuleNames() []string {
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
