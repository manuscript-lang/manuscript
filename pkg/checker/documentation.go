package checker

import (
	"sort"
	"strings"
)

// APIModule is a detached documentation snapshot of an importable module.
type APIModule struct {
	Path         string           `json:"path"`
	Declarations []APIDeclaration `json:"declarations"`
}
type APIDeclaration struct {
	// Declaration is a source-syntax excerpt for human documentation. The JSON
	// snapshot retains its existing machine-readable type and member contracts.
	Declaration                string   `json:"-"`
	Name                       string   `json:"name"`
	Kind                       string   `json:"kind"`
	Type                       string   `json:"type"`
	Parameters                 []string `json:"type_parameters,omitempty"`
	Fields                     []string `json:"fields,omitempty"`
	Cases                      []string `json:"cases,omitempty"`
	Operations                 []string `json:"operations,omitempty"`
	Implements                 []string `json:"implements,omitempty"`
	ImplementationDeclarations []string `json:"-"`
}

// StandardLibrary captures the actual checker definitions, without exposing mutable
// types. Types and operations are loaded from the bundled standard .ms sources.
func StandardLibrary() []APIModule {
	modules := map[string][]*Symbol{}
	sources := map[string]string{}
	for _, source := range standardSources {
		sources[source.File] = source.Source
	}
	for path, symbols := range standardModules {
		for _, symbol := range symbols {
			if symbol.Export {
				modules[path] = append(modules[path], symbol)
			}
		}
	}
	for _, name := range []string{"Bool", "Int", "Float", "String", "Unit", "Never"} {
		modules["prelude"] = append(modules["prelude"], &Symbol{Name: name, Kind: "type", Type: primitive(name)})
	}
	var result []APIModule
	for path, symbols := range modules {
		sort.Slice(symbols, func(i, j int) bool { return symbols[i].Name < symbols[j].Name })
		module := APIModule{Path: path}
		for _, symbol := range symbols {
			d := documentSymbol(symbol, sources[symbol.Module])
			documentImplementations(&d, symbol, standardImplementations)
			module.Declarations = append(module.Declarations, d)
		}
		result = append(result, module)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].Path < result[j].Path })
	return result
}

func documentImplementations(d *APIDeclaration, symbol *Symbol, methods []*Method) {
	contracts := map[string]bool{}
	operations := map[string]bool{}
	for _, method := range methods {
		if method.Receiver.ID != symbol.Type.ID {
			continue
		}
		contracts[method.Contract.String()] = true
		d.ImplementationDeclarations = append(d.ImplementationDeclarations, "impl "+method.Contract.String()+" for "+method.Receiver.String()+":\n    "+documentDeclaration(method.Decl, "fn", method.Decl.Name))
		operation := method.Decl.Name + ": " + method.Type.String()
		if !operations[operation] {
			d.Operations = append(d.Operations, operation)
			operations[operation] = true
		}
	}
	for contract := range contracts {
		d.Implements = append(d.Implements, contract)
	}
	sort.Strings(d.Implements)
	sort.Strings(d.Operations)
}

func documentSymbol(symbol *Symbol, source string) APIDeclaration {
	d := APIDeclaration{Name: symbol.Name, Kind: symbol.Kind, Type: symbol.Type.String()}
	if decl := symbol.Decl; decl != nil {
		keyword := "type"
		if strings.HasPrefix(source[decl.Pos.Offset:], "interface") {
			keyword = "interface"
		}
		d.Declaration = documentDeclaration(decl, keyword, decl.Name, source)
	} else if intrinsic := intrinsicOperations[symbol.Type.ID]; intrinsic != nil {
		d.Declaration = documentDeclaration(intrinsic.Def.Symbol.Decl, "type", symbol.Name)
	} else {
		d.Declaration = "type " + symbol.Name + ":\n"
	}
	for _, v := range symbol.Variables {
		parameter := v.Name
		for i, b := range v.Bounds {
			if i == 0 {
				parameter += ": "
			} else {
				parameter += " & "
			}
			parameter += b.String()
		}
		d.Parameters = append(d.Parameters, parameter)
	}
	operations := map[string]string{}
	if def := symbol.Type.Def; def != nil {
		d.Kind = def.Kind
		if symbol.Decl != nil && symbol.Decl.Kind == "interface" {
			d.Kind = "interface"
		}
		for _, f := range def.Fields {
			d.Fields = append(d.Fields, f.Name+": "+f.Type.String())
		}
		for _, c := range def.Cases {
			value := c.Name
			if len(c.Fields) > 0 {
				value += "("
				for i, f := range c.Fields {
					if i > 0 {
						value += ", "
					}
					value += f.Name + ": " + f.Type.String()
				}
				value += ")"
			}
			d.Cases = append(d.Cases, value)
		}
		for _, op := range def.Operations {
			operations[documentOperationName(symbol.Type, op.Name)] = op.Type.String()
		}
	}
	if intrinsic := intrinsicOperations[symbol.Type.ID]; intrinsic != nil {
		for _, op := range intrinsic.Def.Operations {
			operations[op.Name] = op.Type.String()
		}
	}
	for name, signature := range operations {
		d.Operations = append(d.Operations, name+": "+signature)
	}
	sort.Strings(d.Operations)
	return d
}

// ModuleDocumentation captures only exports declared by each checked source module.
// Imported symbols and private declarations do not become public documentation.
func ModuleDocumentation(program *Program) []APIModule {
	var modules []APIModule
	for _, source := range program.Modules {
		module := APIModule{Path: source.File, Declarations: []APIDeclaration{}}
		for _, decl := range source.Declarations {
			if !decl.Export || decl.Kind == "impl" || decl.Kind == "test" {
				continue
			}
			symbol := program.Symbols[source.File][decl.Name]
			if symbol != nil && symbol.Decl == decl {
				d := documentSymbol(symbol, source.Source)
				documentImplementations(&d, symbol, program.Methods)
				module.Declarations = append(module.Declarations, d)
			}
		}
		sort.Slice(module.Declarations, func(i, j int) bool { return module.Declarations[i].Name < module.Declarations[j].Name })
		modules = append(modules, module)
	}
	sort.Slice(modules, func(i, j int) bool { return modules[i].Path < modules[j].Path })
	return modules
}

func documentOperationName(receiver *Type, name string) string {
	variables := standardOperationVariables[receiver.ID+"/"+name]
	if len(variables) == 0 {
		return name
	}
	var params []string
	for _, v := range variables {
		parameter := v.Name
		for i, b := range v.Bounds {
			if i == 0 {
				parameter += ": "
			} else {
				parameter += " & "
			}
			parameter += b.String()
		}
		params = append(params, parameter)
	}
	return name + "[" + strings.Join(params, ", ") + "]"
}
