package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestInterfaceOverPrivateRecordEncapsulates(t *testing.T) {
	result := compiler.CompileFile("testdata/projects/encapsulation/main.ms", compiler.Options{Tests: true})
	data, err := execute(t, result)
	if err != nil || !strings.HasSuffix(strings.TrimSpace(string(data)), "2 tests, 0 failed") {
		t.Fatalf("encapsulated counter: %v\n%s", err, data)
	}
	rejected(t, compiler.CompileFile("testdata/projects/encapsulation/forge_field.ms", compiler.Options{}), "resolution", "unknown or ambiguous member count on Counter")
	rejected(t, compiler.CompileFile("testdata/projects/encapsulation/forge_construct.ms", compiler.Options{}), "resolution", "unknown binding CounterState")
}
