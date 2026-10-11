package compiler

import (
	"fmt"
	rt "github.com/manuscript-lang/manuscript/runtime"
	"testing"
)

func TestAllLibraryFunctionsAreImportable(t *testing.T) {
	for _, spec := range rt.Library {
		t.Run(spec.Module+"/"+spec.Name, func(t *testing.T) {
			source := fmt.Sprintf("import %s from \"@std/%s.ms\"\n", spec.Name, spec.Module)
			result := CompileSource("imports.ms", source, Options{})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}
func TestOpaqueLibraryTypesCannotBeConstructed(t *testing.T) {
	for _, spec := range []struct{ module, name string }{{"bigint", "BigInt"}, {"regex", "Regex"}, {"time", "Timestamp"}} {
		source := fmt.Sprintf("import %s from \"@std/%s.ms\"\ntest \"reject\":\n    let value = %s()\n", spec.name, spec.module, spec.name)
		if result := CompileSource("opaque.ms", source, Options{}); result.Success() {
			t.Fatal("accepted native constructor", spec.name)
		}
	}
}
