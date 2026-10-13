package e2e_test

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestWideNumericStandalone(t *testing.T)    { numericStandalone(t, "wide-numbers.ms", 5) }
func TestDefaultNumericStandalone(t *testing.T) { numericStandalone(t, "default-numbers.ms", 4) }
func numericStandalone(t *testing.T, fixture string, tests int) {
	t.Helper()
	result := compiler.CompileFile(filepath.Join("testdata/accept", fixture), compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	source, err := compiler.Standalone(result.Source)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(source, "github.com/manuscript-lang/manuscript/pkg/runtime") {
		t.Fatal("runtime import survived standalone assembly")
	}
	executable := filepath.Join(t.TempDir(), "numeric-standalone")
	if err := compiler.Build(source, executable); err != nil {
		t.Fatal(err)
	}
	if data, err := commandOutput(t, executable); err != nil || !strings.Contains(string(data), fmt.Sprintf("%d tests, 0 failed", tests)) {
		t.Fatalf("standalone transcript %q, error %v", data, err)
	}
}

func TestWideNumericSourceFaults(t *testing.T) {
	for name, body := range map[string]string{
		"add":              "let value: Int64 = 9223372036854775807\n    let invalid = value + 1",
		"subtract":         "let value: Int64 = -9223372036854775808\n    let invalid = value - 1",
		"multiply":         "let value: Int64 = 9223372036854775807\n    let invalid = value * 2",
		"minimum division": "let value: Int64 = -9223372036854775808\n    let invalid = value / -1",
		"zero division":    "let value: Int64 = 3\n    let invalid = value / 0",
		"zero remainder":   "let value: Int64 = 3\n    let invalid = value % 0",
		"minimum negation": "let value: Int64 = -9223372036854775808\n    let invalid = -value",
	} {
		t.Run(name, func(t *testing.T) {
			source := fmt.Sprintf("export fn main() -> Int:\n    %s\n    return 0\n", body)
			result := compiler.CompileSource("wide-fault.ms", source, compiler.Options{Entry: true})
			data, err := execute(t, result)
			if err == nil || !strings.Contains(string(data), "Int64") || !strings.Contains(string(data), "wide-fault.ms:3:") {
				t.Fatalf("missing wide numeric source fault: %v\n%s", err, data)
			}
		})
	}
}
