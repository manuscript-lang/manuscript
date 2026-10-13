package compiler_test

import (
	"reflect"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// Result's original exported layout remains source-compatible, including
// unkeyed external callers. New build-kind compilation retains no hidden state.
func TestResultLegacyLayout(t *testing.T) {
	typ := reflect.TypeOf(compiler.Result{})
	names := []string{"SourceRoot", "Program", "Source", "Diagnostics", "ProjectRoot", "Configuration"}
	if typ.NumField() != len(names) {
		t.Fatal("Result layout breaks external unkeyed callers")
	}
	for i, name := range names {
		if field := typ.Field(i); field.Name != name || field.PkgPath != "" {
			t.Fatal("Result layout changed", field)
		}
	}
}
