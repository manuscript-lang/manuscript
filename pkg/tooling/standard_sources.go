package tooling

import (
	"fmt"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

// StandardDeclarations indexes the same source declarations that the checker
// uses. It includes contract/native members, fields and alternative cases.
func StandardDeclarations() Inspection {
	out := Inspection{Format: 2, Sources: []Source{}, Entities: []Entity{}, Calls: []CallSite{}, Statements: []Span{}}
	for _, module := range checker.StandardModules() {
		out.Sources = append(out.Sources, Source{module.File, hash(module.Source)})
		exports := checker.StandardExports(module.File)
		for _, d := range module.Declarations {
			if d.Kind == "impl" {
				if receiver := exports[d.Receiver.Name]; receiver != nil {
					for _, method := range d.Methods {
						kind := "operation"
						if method.Accessor {
							kind = "accessor"
						}
						id := module.File + "#impl#" + d.Receiver.Name + "#" + d.Contract.Name + "#" + kind + "#" + method.Name
						out.Entities = append(out.Entities, Entity{ID: id, Kind: kind, Name: d.Receiver.Name + "." + method.Name, Span: sourceSpan(module, method.Pos), Exported: true})
					}
				}
				continue
			}
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
			accessorTypes := map[string]string{}
			if symbol.Type.Def != nil {
				for _, operation := range symbol.Type.Def.Operations {
					if operation.Accessor {
						accessorTypes[operation.Name] = operation.Type.Result.String()
					}
				}
			}
			for _, method := range d.Methods {
				kind := "operation"
				memberID := id + "#" + kind + "#" + method.Name
				typ := ""
				if method.Accessor {
					kind = "accessor"
					memberID = fmt.Sprintf("%s#accessor#%d", module.File, method.Pos.Offset)
					typ = accessorTypes[method.Name]
				}
				out.Entities = append(out.Entities, Entity{ID: memberID, Kind: kind, Name: d.Name + "." + method.Name, Type: typ, Span: sourceSpan(module, method.Pos), Exported: true})
			}
		}
	}
	return out
}
