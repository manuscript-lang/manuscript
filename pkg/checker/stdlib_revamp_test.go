package checker

import (
	"github.com/manuscript-lang/manuscript/pkg/parser"
	rt "github.com/manuscript-lang/manuscript/pkg/runtime"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"testing"
)

func TestEqualityInterfacesAndHashConsistency(t *testing.T) {
	for _, name := range []string{"Equal", "Hashable"} {
		if standardSymbols[name].Type.Kind != "contract" || standardSymbols[name].Module != "@std/equality.ms" {
			t.Fatal("equality must be a source interface", name)
		}
	}
	source := `import {Equal} from "@std/equality.ms"
import Map from "@std/collections.ms"
type Key:
    id: Int
impl Equal for Key:
    fn equals(other: Equal) -> Bool: return true
fn keys() -> Map[Key, Int]: return Map[Key, Int]()
`
	module, err := parser.Parse("key.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	if program := Check([]*syntax.Module{module}, nil); len(program.Diagnostics) == 0 {
		t.Fatal("custom equality inherited an incompatible structural hash")
	}
}
func TestOptionalStandardRecordDefaults(t *testing.T) {
	for _, symbol := range standardSymbols {
		typ := symbol.Type
		if typ.Kind != "record" {
			continue
		}
		value, ok := rt.Construct(TypeKey(typ), nil).(rt.Record)
		if !ok {
			continue
		}
		for _, field := range Fields(typ) {
			if field.Type.ID != "@std/Optional" {
				continue
			}
			defaulted := false
			for _, declared := range symbol.Decl.Fields {
				if declared.Name == field.Name && declared.Default != nil {
					defaulted = true
				}
			}
			if !defaulted {
				continue
			}
			option, ok := value.Fields[field.Name].(rt.Alternative)
			if !ok || option.Tag != "none" || option.Type != TypeKey(field.Type) {
				t.Fatalf("%s.%s omitted default: %#v", typ.Name, field.Name, value.Fields[field.Name])
			}
		}
	}
}
func TestReceiverUtilitiesHaveOnePublicSpelling(t *testing.T) {
	for _, module := range standardSources {
		for _, declaration := range module.Declarations {
			if declaration.Kind == syntax.KindFn && !declaration.Export && standardModules[module.File][declaration.Name].Native != "" {
				t.Fatalf("private native function duplicates a receiver declaration: %s", declaration.Pos)
			}
		}
	}
}
