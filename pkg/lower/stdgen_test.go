package lower

import (
	"os"
	"path/filepath"
	"testing"
)

// The runtime's standard declarations are generated from the @std sources; a
// stale checked-in copy means `make stdgen` was not run.
func TestGeneratedRuntimeIsFresh(t *testing.T) {
	files, err := StandardRuntime()
	if err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join("..", "runtime")
	for name, want := range files {
		got, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil || string(got) != want {
			t.Errorf("%s is stale; run make stdgen", name)
		}
	}
	existing, _ := filepath.Glob(filepath.Join(dir, "std_*_gen.go"))
	for _, path := range existing {
		if _, ok := files[filepath.Base(path)]; !ok {
			t.Errorf("%s is no longer generated; run make stdgen", filepath.Base(path))
		}
	}
}
