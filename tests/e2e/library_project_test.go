package e2e_test

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLibraryProjectCommandsAndCache(t *testing.T) {
	root := t.TempDir()
	t.Setenv("MANUSCRIPT_CACHE_DIR", filepath.Join(t.TempDir(), "user-cache"))
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
	manifest := filepath.Join(root, "ms.toml")
	configuration := "# library\n[project]\nname = \"library\"\nsource = \"src\"\n[aliases]\n\"@lib\" = \"src\"\n"
	write("ms.toml", configuration)
	write("src/value.ms", "export fn value() -> Int: return 3\n")
	write("src/other.ms", "import panic from \"@std/faults.ms\"\nexport fn other() -> Int: return 4\ntest \"unimported\":\n    if other() != 4: return panic(\"bad other\")\n")
	write("golden/input.txt", "fixture")
	write("test.ms", `import value from "@lib/value.ms"
import filesystem from "@std/fs.ms"
import panic from "@std/faults.ms"
test "root":
    if value() != 3: return panic("bad value")
    match filesystem().read_file(path: "golden/input.txt", max_bytes: 1024):
    ok(data):
        if data.length() != 7: return panic("wrong fixture size")
    error(_):
        return panic("fixture not found from project directory")
`)
	write("tests/value_test.ms", "test \"nested\":\n    return unit\n")
	// Invoke from an unrelated directory: module and lock paths remain manifest-relative.
	run := func(args ...string) (string, error) {
		t.Helper()
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		c := exec.CommandContext(ctx, cliBinary, args...)
		c.Dir = t.TempDir()
		data, err := c.CombinedOutput()
		return string(data), err
	}
	for _, command := range []string{"check", "lint"} {
		data, err := run(command, manifest)
		if err != nil {
			t.Fatalf("%s: %v %s", command, err, data)
		}
	}
	for range 2 {
		data, err := run("test", manifest)
		if err != nil || !strings.Contains(data, "3 tests, 0 failed") || !strings.Contains(data, "src/other.ms::unimported") {
			t.Fatalf("library tests: %v %s", err, data)
		}
	}
	// Editing an unimported source module must invalidate native test artifacts.
	write("src/other.ms", "import panic from \"@std/faults.ms\"\nexport fn other() -> Int: return 4\ntest \"unimported\":\n    return panic(\"changed unimported test\")\n")
	data, err := run("test", manifest)
	if err == nil || !strings.Contains(data, "changed unimported test") || !strings.Contains(data, "1 failed") {
		t.Fatalf("stale library test executable: %v %s", err, data)
	}
	for _, command := range []string{"run", "build", "emit", "debug", "profile"} {
		data, err := run(command, manifest)
		if err == nil || !strings.Contains(data, "ms.toml:2:1: resolution: library project has no executable entry") || !strings.Contains(data, "add entry =") {
			t.Fatalf("%s accepted a library: %v %s", command, err, data)
		}
	}
	write("src/other.ms", "export fn other() -> Int: return 4\n")
	write("ms.toml", strings.Replace(configuration, "[aliases]", "entry = \"src/missing.ms\"\n[aliases]", 1))
	data, err = run("check", manifest)
	if err == nil || !strings.Contains(data, "ms.toml:5:9:") {
		t.Fatalf("explicit entry treated as library: %v %s", err, data)
	}
	write("src/main.ms", "import value from \"@lib/value.ms\"\nexport fn main() -> Int: return value() - 3\n")
	write("src/other.ms", "export fn other() -> Int: return \"bad\"\n")
	write("ms.toml", strings.Replace(configuration, "[aliases]", "entry = \"src/main.ms\"\n[aliases]", 1))
	data, err = run("run", manifest)
	if err != nil {
		t.Fatalf("explicit executable discovery changed: %v %s", err, data)
	}
	data, err = run("check", manifest)
	if err == nil || !strings.Contains(data, "other.ms") {
		t.Fatalf("project check stopped discovering: %v %s", err, data)
	}
}
