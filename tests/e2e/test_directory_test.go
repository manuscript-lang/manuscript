package e2e_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// ms test runs in the project directory (or beside a single test file), so
// fixture paths do not depend on where the caller invoked ms.
func TestTestsRunInProjectDirectory(t *testing.T) {
	root := t.TempDir()
	write := func(name, content string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(filepath.Join(root, name)), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(root, name), []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write("ms.toml", "[project]\nname = \"fixtures\"\nsource = \"./src\"\nentry = \"./src/main.ms\"\n")
	write("src/main.ms", "export fn main() Int:\n    return 0\n")
	write("golden/input.txt", "fixture")
	write("test.ms", `import filesystem from "@std/fs.ms"
import {expect_true, fail} from "@std/testing.ms"

test "fixture next to the manifest":
    match filesystem().read_file(path: "golden/input.txt", max_bytes: 1024):
        ok(data):
            if data.length() != 7:
                return fail("wrong fixture size")
        error(_):
            return fail("fixture not found")
`)
	elsewhere := t.TempDir()
	for _, target := range []string{filepath.Join(root, "ms.toml"), filepath.Join(root, "test.ms")} {
		command := exec.Command(cliBinary, "test", target)
		command.Dir = elsewhere
		output, err := command.CombinedOutput()
		if err != nil || !strings.Contains(string(output), "1 tests, 0 failed") {
			t.Fatalf("ms test %s from another directory: %v\n%s", target, err, output)
		}
	}
}
