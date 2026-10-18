package e2e_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestActionableDiagnosticsCLI(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "money.ms"), []byte("export type MoneyError:\n    case Invalid\nexport fn parse_cents() -> Int: 0\nexport fn format_cents() -> String: \"0\"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ name, source, token, code, hint string }{
		{"string-match", "fn f(command: String) -> Int:\n    match command:\n    \"réport\": return 1\n    return 0\n", "\"réport\"", "MS1000", "compare strings with 'if"},
		{"import", "import money from \"./money.ms\"\n", "money", "MS2002", "exports: MoneyError, format_cents, parse_cents; namespace imports are unsupported"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := strings.ReplaceAll(tc.source, "\n", "\r\n")
			file := filepath.Join(root, tc.name+".ms")
			if err := os.WriteFile(file, []byte(source), 0600); err != nil {
				t.Fatal(err)
			}
			output, err := commandOutput(t, cliBinary, "check", file, "--json")
			if err == nil {
				t.Fatal("accepted unsupported source")
			}
			var result struct {
				Format      int `json:"format"`
				Diagnostics []struct {
					syntax.Diagnostic
					Code string `json:"code"`
				} `json:"diagnostics"`
			}
			if err := json.Unmarshal(output, &result); err != nil {
				t.Fatalf("%v: %s", err, output)
			}
			if result.Format != 1 || len(result.Diagnostics) != 1 {
				t.Fatalf("%s", output)
			}
			d := result.Diagnostics[0]
			if d.Code != tc.code || !strings.Contains(d.Message, tc.hint) || d.End == nil || source[d.Position.Offset:d.End.Offset] != tc.token {
				t.Fatalf("%s", output)
			}
			if d.Fix != nil {
				t.Fatalf("unexpected fix: %s", output)
			}
			output, err = commandOutput(t, cliBinary, "check", file)
			if err == nil || !strings.Contains(string(output), tc.hint) {
				t.Fatalf("missing text guidance: %v: %s", err, output)
			}
		})
	}
}

func TestCompoundAssignmentRunsNatively(t *testing.T) {
	for _, tc := range []struct {
		op   string
		want string
	}{{"+", "14"}, {"-", "10"}, {"*", "24"}, {"/", "6"}, {"%", "0"}} {
		t.Run(tc.op, func(t *testing.T) {
			source := "export fn main() -> Int:\r\n    var total = 12\r\n    total " + tc.op + "= 2 # preserve\r\n    return total - " + tc.want + "\r\n"
			file := filepath.Join(t.TempDir(), "main.ms")
			if err := os.WriteFile(file, []byte(source), 0600); err != nil {
				t.Fatal(err)
			}
			if output, err := commandOutput(t, cliBinary, "run", file); err != nil {
				t.Fatalf("compound assignment did not execute correctly: %v\n%s", err, output)
			}
		})
	}
}
