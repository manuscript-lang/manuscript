package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLibrarySourceCommandsDiscoverExportsAndErrors(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	root := t.TempDir()
	write := func(name, text string) {
		t.Helper()
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(text), 0600); err != nil {
			t.Fatal(err)
		}
	}
	write("ms.toml", "[project]\nname = \"library\"\nsource = \"src\"\n")
	write("src/value.ms", "export fn value() Int: return 3\n")
	write("src/other.ms", "export fn other() Int: return 4\n")
	write("tests/value_test.ms", "test \"value\":\n    return unit\n")
	manifest := filepath.Join(root, "ms.toml")
	for _, command := range []string{"check", "lint", "inspect", "diagram"} {
		status, output, errs := invoke(t, command, manifest)
		if status != 0 || errs != "" {
			t.Fatalf("%s: %d %s %s", command, status, output, errs)
		}
	}
	write("src/other.ms", "export fn other() Int: return \"bad\"\n")
	for _, command := range []string{"check", "lint"} {
		status, _, errs := invoke(t, command, manifest)
		if status != 1 || !strings.Contains(errs, "other.ms:1:") {
			t.Fatalf("%s skipped unimported error: %d %s", command, status, errs)
		}
	}
	if _, err := os.Stat(filepath.Join(root, ".ms-cache")); !os.IsNotExist(err) {
		t.Fatal("source commands built native artifacts:", err)
	}
}
