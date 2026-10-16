package compiler_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// A List or Bytes length() call is Go's len on the backing slice, not a runtime call.
func TestLengthLowersToGoLen(t *testing.T) {
	source := "import Bytes from \"@std/bytes.ms\"\nfn count(items: List[Int], data: Bytes) -> Int:\n    return items.length() + data.length()\n"
	result := compiler.CompileSource("length.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatalf("diagnostics: %v", result.Diagnostics)
	}
	for _, want := range []string{"int64(len(items.Items))", "int64(len(data.Data))"} {
		if !strings.Contains(result.Source, want) {
			t.Errorf("generated Go lacks %s:\n%s", want, result.Source)
		}
	}
	for _, unwanted := range []string{"List_Length", "Bytes_Length"} {
		if strings.Contains(result.Source, unwanted) {
			t.Errorf("generated Go still calls %s", unwanted)
		}
	}
}
