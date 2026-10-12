package tooling

import (
	"github.com/manuscript-lang/manuscript/checker"
	"github.com/manuscript-lang/manuscript/syntax"
)

// Navigation supplies hover text and a source-addressable definition for an
// editor/LSP adapter. Source offsets use the same byte coordinates as diagnostics.
type Navigation struct {
	Hover      string `json:"hover"`
	Definition Span   `json:"definition"`
}

func NavigationAt(program *checker.Program, file string, offset int) (Navigation, bool) {
	modules := append([]*syntax.Module{}, program.Modules...)
	modules = append(modules, checker.StandardModules()...)
	sourceModule := func(name string) *syntax.Module {
		for _, module := range modules {
			if module.File == name {
				return module
			}
		}
		return nil
	}
	result := func(hover string, pos syntax.Position) (Navigation, bool) {
		module := sourceModule(pos.File)
		if module == nil {
			return Navigation{}, false
		}
		return Navigation{Hover: hover, Definition: sourceSpan(module, pos)}, true
	}
	matchName := func(pos syntax.Position, name string) bool {
		return pos.File == file && offset >= pos.Offset && offset < pos.Offset+len(name)
	}
	for _, module := range program.Modules {
		if module.File != file {
			continue
		}
		for _, imp := range module.Imports {
			start := imp.NamePos.Offset
			if offset >= start && offset < start+len(imp.Name) {
				symbol := program.Symbols[file][imp.Name]
				if symbol != nil && symbol.Decl != nil {
					return result(symbol.Name+": "+symbol.Type.String(), symbol.Decl.Pos)
				}
			}
		}
	}
	for ref, typ := range program.TypeReferences {
		if matchName(ref.Pos, ref.Name) && typ.Def != nil && typ.Def.Symbol != nil && typ.Def.Symbol.Decl != nil {
			return result(typ.String(), typ.Def.Symbol.Decl.Pos)
		}
	}
	for expression, info := range program.Expressions {
		if expression.Kind == "name" && matchName(expression.Pos, expression.Text) && info.Symbol != nil && info.Symbol.Decl != nil {
			return result(info.Symbol.Name+": "+info.Type.String(), info.Symbol.Decl.Pos)
		}
		if expression.Kind == "member" && matchName(expression.Pos, expression.Text) {
			if info.Method != nil && info.Method.Decl != nil {
				return result(expression.Text+": "+info.Type.String(), info.Method.Decl.Pos)
			}
			if receiver := program.Expressions[expression.Left]; receiver != nil && receiver.Type != nil && receiver.Type.Def != nil {
				symbol := receiver.Type.Def.Symbol
				if symbol != nil && symbol.Decl != nil {
					for _, field := range symbol.Decl.Fields {
						if field.Name == expression.Text {
							return result(expression.Text+": "+info.Type.String(), field.Pos)
						}
					}
					for _, cs := range symbol.Decl.Cases {
						if cs.Name == expression.Text {
							return result(expression.Text+": "+info.Type.String(), cs.Pos)
						}
					}
				}
			}
		}
	}
	return Navigation{}, false
}
