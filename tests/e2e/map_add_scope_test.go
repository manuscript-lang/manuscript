package e2e_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// The accepted behavior is testdata/projects/map_add_scope. Merely loading both
// implementation modules must not select either contract for a raw key use in
// the importing module.
func TestMapAddRawKeyDoesNotSeeLocalHashable(t *testing.T) {
	raw := copyProject(t, "testdata/projects/map_add_scope", "conformance_test.ms", `import Key from "./domain.ms"
fn invalid() Unit:
    let m=Map[Key,Int]()
    m.add(Key(-1.0),1)
`)
	if r := compiler.CompileFile(raw, compiler.Options{AnalyzeOnly: true}); r.Success() {
		t.Fatal("local Hashable implementation leaked")
	}
}

// copyProject copies a fixture project to a temporary directory, appends extra to
// the named entry file, and returns the path of that file.
func copyProject(t *testing.T, directory, entry, extra string) string {
	t.Helper()
	root := t.TempDir()
	files, err := os.ReadDir(directory)
	if err != nil {
		t.Fatal(err)
	}
	for _, file := range files {
		data, err := os.ReadFile(filepath.Join(directory, file.Name()))
		if err != nil {
			t.Fatal(err)
		}
		if file.Name() == entry {
			data = append(data, extra...)
		}
		if err := os.WriteFile(filepath.Join(root, file.Name()), data, 0600); err != nil {
			t.Fatal(err)
		}
	}
	return filepath.Join(root, entry)
}
