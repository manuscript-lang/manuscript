package tooling

import (
	"github.com/manuscript-lang/manuscript/checker"
)

// StandardDeclarations indexes the same source declarations that the checker
// uses. It includes contract/native members, fields and alternative cases.
func StandardDeclarations() Inspection {
	out := Inspection{Format: 1, Sources: []Source{}, Entities: []Entity{}, Calls: []CallSite{}, Statements: []Span{}}
	for _, module := range checker.StandardModules() {
		out.Sources = append(out.Sources, Source{module.File, hash(module.Source)})
		exports := checker.StandardExports(module.File)
		for _, d := range module.Declarations {
			symbol := exports[d.Name]
			if symbol == nil {
				continue
			}
			id := module.File + "#" + symbol.Kind + "#" + symbol.Name
			out.Entities = append(out.Entities, Entity{ID: id, GoID: symbol.ID, Kind: symbol.Kind, Name: symbol.Name, Type: symbol.Type.String(), Span: sourceSpan(module, d.Pos), Exported: true})
			for _, field := range d.Fields {
				out.Entities = append(out.Entities, Entity{ID: id + "#field#" + field.Name, Kind: "field", Name: d.Name + "." + field.Name, Span: sourceSpan(module, field.Pos), Exported: true})
			}
			for _, cs := range d.Cases {
				out.Entities = append(out.Entities, Entity{ID: id + "#case#" + cs.Name, Kind: "case", Name: d.Name + "." + cs.Name, Span: sourceSpan(module, cs.Pos), Exported: true})
			}
			for _, method := range d.Methods {
				out.Entities = append(out.Entities, Entity{ID: id + "#operation#" + method.Name, Kind: "operation", Name: d.Name + "." + method.Name, Span: sourceSpan(module, method.Pos), Exported: true})
			}
		}
	}
	return out
}
