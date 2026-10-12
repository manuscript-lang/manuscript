package checker

import (
	_ "embed"
	"go/ast"
	"go/parser"
	"go/token"
	"sort"
	"strconv"
)

//go:embed contracts.go
var nativeMethodSource string

func nativeDocumentationNames() []string {
	file, err := parser.ParseFile(token.NewFileSet(), "contracts.go", nativeMethodSource, 0)
	if err != nil {
		panic(err)
	} // Embedded Go source was compiled into this binary.
	var names []string
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok || fn.Name.Name != "nativeMethod" {
			continue
		}
		ast.Inspect(fn.Body, func(n ast.Node) bool {
			if clause, ok := n.(*ast.CaseClause); ok {
				for _, expr := range clause.List {
					if literal, ok := expr.(*ast.BasicLit); ok && literal.Kind == token.STRING {
						name, err := strconv.Unquote(literal.Value)
						if err == nil {
							names = append(names, name)
						}
					}
				}
			}
			return true
		})
	}
	return names
}

// APIModule is a detached documentation snapshot of an importable module.
type APIModule struct {
	Path         string           `json:"path"`
	Declarations []APIDeclaration `json:"declarations"`
}
type APIDeclaration struct {
	Name       string   `json:"name"`
	Kind       string   `json:"kind"`
	Type       string   `json:"type"`
	Parameters []string `json:"type_parameters,omitempty"`
	Fields     []string `json:"fields,omitempty"`
	Cases      []string `json:"cases,omitempty"`
	Operations []string `json:"operations,omitempty"`
}

// StandardLibrary captures the actual checker definitions, without exposing mutable
// types. Native operation candidates come from the nativeMethod source's case labels.
func StandardLibrary() []APIModule {
	nativeNames := nativeDocumentationNames()
	modules := map[string][]*Symbol{}
	for path, symbols := range standardModules {
		for _, symbol := range symbols {
			modules[path] = append(modules[path], symbol)
		}
	}
	for _, name := range []string{"Bool", "Int", "Float", "String", "Unit", "Never", "Shareable", "Equal", "Hashable"} {
		modules["prelude"] = append(modules["prelude"], &Symbol{Name: name, Kind: "type", Type: primitive(name)})
	}
	var result []APIModule
	for path, symbols := range modules {
		sort.Slice(symbols, func(i, j int) bool { return symbols[i].Name < symbols[j].Name })
		module := APIModule{Path: path}
		for _, symbol := range symbols {
			d := documentSymbol(symbol, nativeNames)
			module.Declarations = append(module.Declarations, d)
		}
		result = append(result, module)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].Path < result[j].Path })
	return result
}

func documentSymbol(symbol *Symbol, nativeNames []string) APIDeclaration {
	d := APIDeclaration{Name: symbol.Name, Kind: symbol.Kind, Type: symbol.Type.String()}
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
			operations[op.Name] = op.Type.String()
		}
	}
	if symbol.Kind == "type" {
		for _, name := range nativeNames {
			if method := nativeMethod(symbol.Type, name); method != nil {
				operations[name] = method.Type.String()
			}
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
				module.Declarations = append(module.Declarations, documentSymbol(symbol, nil))
			}
		}
		sort.Slice(module.Declarations, func(i, j int) bool { return module.Declarations[i].Name < module.Declarations[j].Name })
		modules = append(modules, module)
	}
	sort.Slice(modules, func(i, j int) bool { return modules[i].Path < modules[j].Path })
	return modules
}
