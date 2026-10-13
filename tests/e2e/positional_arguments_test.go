package e2e_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestPositionalArgumentStopsLaterEvaluation(t *testing.T) {
	for _, call := range []string{
		"outer(fail(), later())",
		"outer(second: fail(), later())",
		"outer(fail())",
		"Pair(second: fail(), later())",
	} {
		t.Run(call, func(t *testing.T) {
			source := `import panic from "@std/faults.ms"
fn fail() -> Int: panic("first supplied argument")
fn later() -> Int: panic("later argument or default")
fn outer(first: Int, second: Int = later()) -> Int: panic("outer body")
type Pair:
    first: Int
    second: Int
export fn main() -> Int:
    let ignored = ` + call + `
    return 0
`
			output, err := execute(t, compiler.CompileSource("positional.ms", source, compiler.Options{Entry: true}))
			if err == nil || !strings.Contains(string(output), "first supplied argument") || strings.Contains(string(output), "later argument or default") || strings.Contains(string(output), "outer body") {
				t.Fatalf("%v: %s", err, output)
			}
		})
	}
}

func TestPositionalDiagnosticsJSON(t *testing.T) {
	for _, tc := range []struct{ call, message string }{
		{"f(1, 2, 3)", "too many positional arguments"},
		{"f(1)", "missing argument second"},
		{"f(1, first: 2, second: 3)", "duplicate argument first"},
	} {
		source := "fn f(first: Int, second: Int) -> Int: first\nexport fn main() -> Int:\n    return " + tc.call + "\n"
		file := filepath.Join(t.TempDir(), "arguments.ms")
		if err := os.WriteFile(file, []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
		output, err := commandOutput(t, cliBinary, "check", file, "--json")
		if err == nil {
			t.Fatal("accepted invalid call")
		}
		var result struct {
			Diagnostics []struct {
				Code, Message string
				Position      struct{ Line int }
			}
		}
		if err := json.Unmarshal(output, &result); err != nil {
			t.Fatal(err, string(output))
		}
		if len(result.Diagnostics) != 1 || !strings.Contains(result.Diagnostics[0].Message, tc.message) || result.Diagnostics[0].Position.Line != 3 || result.Diagnostics[0].Code == "" {
			t.Fatal(string(output))
		}
	}
}
