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
	Declaration                string      `json:"-"`
	Name                       string      `json:"name"`
	Doc                        string      `json:"doc,omitempty"`
	Kind                       string      `json:"kind"`
	Type                       string      `json:"type"`
	Parameters                 []string    `json:"type_parameters,omitempty"`
	Fields                     []string    `json:"fields,omitempty"`
	Cases                      []string    `json:"cases,omitempty"`
	Operations                 []string    `json:"operations,omitempty"`
	Members                    []APIMember `json:"members,omitempty"`
	Implements                 []string    `json:"implements,omitempty"`
	ImplementationDeclarations []string    `json:"-"`
}

// APIMember adds source descriptions without changing the legacy member arrays.
// Empty Doc values remain visible to documentation coverage consumers.
type APIMember struct {
	Name      string `json:"name"`
	Kind      string `json:"kind"`
	Signature string `json:"signature"`
	Doc       string `json:"doc"`
	Contract  string `json:"contract,omitempty"`
}

// StandardLibrary captures the actual checker definitions, without exposing mutable
// types. Types and operations are loaded from the bundled standard .ms sources.
func StandardLibrary() []APIModule {
	ensureStandard()
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
	for _, name := range []string{"Bool", "Int", "Int64", "Float", "Float64", "String", "Unit", "Never"} {
		modules["prelude"] = append(modules["prelude"], &Symbol{Name: name, Kind: "type", Type: primitive(name)})
	}
	for _, name := range standardPreludeNames {
		modules["prelude"] = append(modules["prelude"], standardSymbols[name])
	}
	var result []APIModule
	for path, symbols := range modules {
		sort.Slice(symbols, func(i, j int) bool { return symbols[i].Name < symbols[j].Name })
		module := APIModule{Path: path}
		for _, symbol := range symbols {
			d := documentSymbol(symbol, sources)
			documentImplementations(&d, symbol, append(append([]*Method{}, standardImplementations...), standardSourceMethods...), sources)
			module.Declarations = append(module.Declarations, d)
		}
		result = append(result, module)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].Path < result[j].Path })
	return result
}

func documentImplementations(d *APIDeclaration, symbol *Symbol, methods []*Method, sources map[string]string) {
	contracts := map[string]bool{}
	operations := map[string]bool{}
	for _, method := range methods {
		if method.Receiver.ID != symbol.Type.ID {
			continue
		}
		contracts[method.Contract.String()] = true
		d.ImplementationDeclarations = append(d.ImplementationDeclarations, "impl "+method.Contract.String()+" for "+method.Receiver.String()+":\n    "+documentDeclaration(method.Decl, "fn", method.Decl.Name))
		operation := method.Decl.Name + ": " + method.Type.String()
		d.Members = append(d.Members, APIMember{Name: method.Decl.Name, Kind: "operation", Signature: strings.TrimSpace(documentDeclaration(method.Decl, "fn", method.Decl.Name, sources[method.Decl.Pos.File])), Doc: leadingComment(sources[method.Decl.Pos.File], method.Decl.Pos.Offset), Contract: method.Contract.String()})
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
	sortAPIMembers(d.Members)
}

func documentSymbol(symbol *Symbol, sources map[string]string) APIDeclaration {
	source := sources[symbol.Module]
	d := APIDeclaration{Name: symbol.Name, Kind: symbol.Kind, Type: symbol.Type.String()}
	if decl := symbol.Decl; decl != nil {
		keyword := "type"
		if strings.HasPrefix(source[decl.Pos.Offset:], "interface") {
			keyword = "interface"
		}
		d.Declaration = documentDeclaration(decl, keyword, decl.Name, source)
		d.Doc = leadingComment(source, decl.Pos.Offset)
		d.Members = documentMembers(decl, source, symbol.Type)
	} else if intrinsic := intrinsicOperations[symbol.Type.ID]; intrinsic != nil {
		d.Declaration = documentDeclaration(intrinsic.Def.Symbol.Decl, "type", symbol.Name)
		decl := intrinsic.Def.Symbol.Decl
		d.Members = documentMembers(decl, sources[decl.Pos.File], symbol.Type)
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
	sources := map[string]string{}
	for _, source := range program.Modules {
		sources[source.File] = source.Source
	}
	for _, source := range program.Modules {
		module := APIModule{Path: source.File, Declarations: []APIDeclaration{}}
		for _, decl := range source.Declarations {
			if !decl.Export || decl.Kind == "impl" || decl.Kind == "test" {
				continue
			}
			symbol := program.Symbols[source.File][decl.Name]
			if symbol != nil && symbol.Decl == decl {
				d := documentSymbol(symbol, sources)
				documentImplementations(&d, symbol, program.Methods, sources)
				module.Declarations = append(module.Declarations, d)
			}
		}
		sort.Slice(module.Declarations, func(i, j int) bool { return module.Declarations[i].Name < module.Declarations[j].Name })
		modules = append(modules, module)
	}
	sort.Slice(modules, func(i, j int) bool { return modules[i].Path < modules[j].Path })
	return modules
}

func sortAPIMembers(members []APIMember) {
	sort.Slice(members, func(i, j int) bool {
		a, b := members[i], members[j]
		if a.Kind != b.Kind {
			return a.Kind < b.Kind
		}
		if a.Name != b.Name {
			return a.Name < b.Name
		}
		return a.Contract < b.Contract
	})
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

// leadingComment returns the contiguous block of '#' comment lines that ends on
// the line directly above the declaration containing offset. A blank line
// detaches the block. Markers are removed; text is otherwise preserved.
func leadingComment(source string, offset int) string {
	if offset < 0 || offset > len(source) {
		return ""
	}
	lines := strings.Split(source[:offset], "\n")
	ownLine := lines[len(lines)-1]
	// Names of cases and operations follow their keyword; inline payload fields
	// do not begin a declaration line and must not inherit a case description.
	switch strings.TrimSpace(ownLine) {
	case "", "export", "fn", "case":
	default:
		return ""
	}
	indent := len(ownLine) - len(strings.TrimLeft(ownLine, " \t"))
	// The final element is the part of the declaration's own line before it.
	lines = lines[:len(lines)-1]
	var block []string
	for i := len(lines) - 1; i >= 0; i-- {
		if len(lines[i])-len(strings.TrimLeft(lines[i], " \t")) != indent {
			break
		}
		line := strings.TrimSpace(lines[i])
		if !strings.HasPrefix(line, "#") {
			break
		}
		line = strings.TrimPrefix(line, "#")
		block = append([]string{strings.TrimPrefix(line, " ")}, block...)
	}
	return strings.Join(block, "\n")
}
