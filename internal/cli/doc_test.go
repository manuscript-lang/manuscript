package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/checker"
)

func TestDocOutsideRepository(t *testing.T) {
	directory := t.TempDir()
	t.Chdir(directory)
	t.Setenv("MANUSCRIPT_GO", filepath.Join(directory, "no-go-toolchain"))
	for _, args := range [][]string{
		{"doc", "--stdlib", "-o", "stdlib.md"},
		{"doc", "--stdlib", "--json", "-o", "stdlib.json"},
	} {
		if code := Run(args); code != 0 {
			t.Fatalf("%v exited %d", args, code)
		}
	}
	markdown, err := os.ReadFile("stdlib.md")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"```manuscript\n", "fn to_bytes() -> Bytes", "fn start(operation: fn() -> Result[Unit, String]) -> Result[OperationId, StartError]", "history_limit", "# @std/http.ms"} {
		if !strings.Contains(string(markdown), want) {
			t.Errorf("missing %q", want)
		}
	}
	data, err := os.ReadFile("stdlib.json")
	if err != nil {
		t.Fatal(err)
	}
	var reference struct {
		Format  int
		Modules []checker.APIModule
	}
	if err := json.Unmarshal(data, &reference); err != nil {
		t.Fatal(err)
	}
	if reference.Format != 1 || len(reference.Modules) != len(checker.StandardLibrary()) {
		t.Fatalf("invalid snapshot: %+v", reference)
	}
}

func TestDocPublicDeclarationsAndFailures(t *testing.T) {
	directory := t.TempDir()
	source := filepath.Join(directory, "library.ms")
	code := `import arguments from "@std/cli.ms"
export type Item:
    value: Int

export fn create(value: Int = 7) -> Item:
    return Item(value: value)

fn private_helper() -> Int:
    return 1
`
	if err := os.WriteFile(source, []byte(code), 0644); err != nil {
		t.Fatal(err)
	}
	output := filepath.Join(directory, "api.md")
	if status := Run([]string{"doc", source, "-o", output}); status != 0 {
		t.Fatalf("doc exited %d", status)
	}
	data, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"```manuscript\n", "## Item", "type Item:\n    value: Int", "## create", "fn create(value: Int = 7) -> Item"} {
		if !strings.Contains(string(data), want) {
			t.Errorf("missing %q in %s", want, data)
		}
	}
	for _, private := range []string{"private_helper", "## arguments", "return Item", "field value:", "create: fn("} {
		if strings.Contains(string(data), private) {
			t.Errorf("included non-public declaration %q", private)
		}
	}
	// Invalid inputs must fail without replacing an existing output artifact.
	if err := os.WriteFile(source, []byte("export fn broken() -> Int:\n    return unknown\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if status := Run([]string{"doc", source, "-o", output}); status != 1 {
		t.Fatalf("invalid source exited %d", status)
	}
	after, _ := os.ReadFile(output)
	if string(after) != string(data) {
		t.Fatal("failed check replaced documentation")
	}
	for _, args := range [][]string{{"doc"}, {"doc", "--stdlib", source}, {"doc", "--stdlib", "--check"}, {"doc", "--stdlib", "-o"}} {
		if status := Run(args); status != 2 {
			t.Errorf("%v exited %d, want 2", args, status)
		}
	}
}
