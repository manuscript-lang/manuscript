package e2e_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestCLIProjectCheck(t *testing.T) {
	root := t.TempDir()
	if err := os.CopyFS(root, os.DirFS("testdata/projects/project_check")); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(filepath.Join(root, "src/main.ms")), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "src/main.ms"), []byte(`import panic from "@std/faults.ms"

export fn main() Int:
    return panic("check must not execute main")
`), 0600); err != nil {
		t.Fatal(err)
	}

	if err := os.MkdirAll(filepath.Dir(filepath.Join(root, "tests/report_test.ms")), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "tests/report_test.ms"), []byte(`import panic from "@std/faults.ms"

test "check must not execute tests":
    return panic("check must not execute tests")
`), 0600); err != nil {
		t.Fatal(err)
	}

	t.Setenv("PATH", t.TempDir())
	manifest := filepath.Join(root, "ms.toml")
	output, err := commandOutput(t, cliBinary, "check", manifest, "--json")
	var report struct {
		Diagnostics []syntax.Diagnostic `json:"diagnostics"`
	}
	if err == nil || json.Unmarshal(output, &report) != nil || len(report.Diagnostics) != 2 {
		t.Fatalf("unimported errors not reported: %v\n%s", err, output)
	}
	for _, issue := range report.Diagnostics {
		if issue.Position.File != "src/report.ms" || issue.Phase != "type" {
			t.Fatalf("wrong diagnostic: %+v", issue)
		}
	}
	output, err = commandOutput(t, cliBinary, "check", filepath.Join(root, "src/main.ms"))
	if err != nil || !strings.Contains(string(output), "Checked") {
		t.Fatalf("file check: %v\n%s", err, output)
	}
	if err := os.WriteFile(filepath.Join(root, "src/report.ms"), []byte("fn number() Int: return 1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	output, err = commandOutput(t, cliBinary, "check", manifest)
	if err != nil || !strings.Contains(string(output), "(3 modules)") {
		t.Fatalf("project check executed source or missed files: %v\n%s", err, output)
	}
	if _, err := os.Stat(filepath.Join(root, ".ms-cache")); !os.IsNotExist(err) {
		t.Fatalf("check created native artifacts: %v", err)
	}
}
