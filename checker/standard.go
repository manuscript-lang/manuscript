package checker

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/parser"
	"github.com/manuscript-lang/manuscript/stdlib"
	"github.com/manuscript-lang/manuscript/syntax"
)

var standardSymbols map[string]*Symbol
var standardModules map[string]map[string]*Symbol
var standardSources []*syntax.Module
var intrinsicOperations map[string]*Type

type standardBindings struct {
	NativeTypes        map[string]string `json:"native_types"`
	Functions          map[string]string `json:"functions"`
	SpecialFunctions   map[string]string `json:"special_functions"`
	IntrinsicReceivers map[string]string `json:"intrinsic_receivers"`
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
			if d.Kind == "test" || d.Kind == "impl" {
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
			s := &Symbol{Name: d.Name, ID: id, Kind: "type", Module: module.File, Export: d.Export, Native: native, Decl: d}
			if d.Kind == "fn" {
				native = bindings.Functions[module.File+"/"+d.Name]
				if native == "" {
					return fmt.Errorf("missing native function binding: %s", d.Pos)
				}
				s.Kind = "fn"
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
	c := &checker{Program: &Program{TypeReferences: map[*syntax.Type]*Type{}}, captures: map[int]map[*Binding]bool{}}
	scopeModule := func(module *syntax.Module) {
		c.module = module
		c.names = map[string]*Symbol{}
		c.scope = newScope(nil)
		for _, name := range strings.Fields("Bool Int Float String Unit Never Shareable Equal Hashable") {
			c.names[name] = &Symbol{Name: name, ID: name, Kind: "type", Type: primitive(name), Export: true}
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
			c.addSymbol(d.Name, standardModules[module.File][d.Name], d.Pos)
		}
	}
	// All nominal identities are declared first, so standard contracts may refer to
	// one another without bootstrapping a second, hidden Go type schema.
	for _, module := range standardSources {
		scopeModule(module)
		for _, d := range module.Declarations {
			s := standardModules[module.File][d.Name]
			c.scope = newScope(nil)
			for _, p := range d.TypeParams {
				v := &Type{Name: p.Name, ID: s.ID + "/" + p.Name, Kind: "variable"}
				s.Variables = append(s.Variables, v)
				c.scope.types[p.Name] = v
			}
			if s.Kind == "type" {
				s.Type.Args = s.Variables
				s.Type.Def.Variables = s.Variables
			}
		}
	}
	for _, module := range standardSources {
		scopeModule(module)
		for _, d := range module.Declarations {
			s := standardModules[module.File][d.Name]
			c.scope = c.variableScope(s.Variables)
			for i, p := range d.TypeParams {
				for _, bound := range p.Bounds {
					s.Variables[i].Bounds = append(s.Variables[i].Bounds, c.resolve(bound, true))
				}
			}
			if s.Kind == "fn" {
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
				def.Operations = append(def.Operations, Param{method.Name, c.signature(method.Params, method.Result)})
			}
		}
	}
	if len(c.Diagnostics) > 0 {
		return fmt.Errorf("invalid standard declarations: %v", c.Diagnostics)
	}
	for path, native := range bindings.SpecialFunctions {
		at := strings.LastIndexByte(path, '/')
		module, name := path[:at], path[at+1:]
		var source *syntax.Module
		for _, m := range standardSources {
			if m.File == module {
				source = m
				break
			}
		}
		if source == nil {
			return fmt.Errorf("missing special binding source %s", path)
		}
		marker := "# compiler binding: " + name
		offset := strings.Index(source.Source, marker)
		if offset < 0 {
			return fmt.Errorf("missing compiler binding marker %s", path)
		}
		line := strings.Count(source.Source[:offset], "\n") + 1
		decl := &syntax.Declaration{Pos: syntax.Position{File: module, Line: line, Column: 1, Offset: offset}, Kind: "fn", Name: name, Export: true}
		standardModules[module][name] = &Symbol{Name: name, ID: "@std/" + native, Kind: "fn", Module: module, Export: true, Native: native, Decl: decl, Type: function(nil, nil)}
	}
	for receiver, name := range bindings.IntrinsicReceivers {
		typ := standardSymbols[name]
		if typ == nil {
			return fmt.Errorf("missing intrinsic receiver declaration %s", name)
		}
		intrinsicOperations[receiver] = typ.Type
	}
	return validateStandardNativeBindings()
}

// StandardModules exposes canonical declarations and their source positions to
// tooling. Callers must not mutate the returned checked declarations.
func StandardModules() []*syntax.Module { return append([]*syntax.Module{}, standardSources...) }
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
