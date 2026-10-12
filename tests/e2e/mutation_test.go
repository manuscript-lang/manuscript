package e2e_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/compiler"
)

func TestMutationCLIRejectsInvalidAssignmentsAndHandleClones(t *testing.T) {
	tool := os.Getenv("MANUSCRIPT_GO")
	if tool == "" {
		tool = "go"
	}
	binary := filepath.Join(t.TempDir(), "ms")
	if output, err := exec.Command(tool, "build", "-o", binary, "../../cmd/ms").CombinedOutput(); err != nil {
		t.Fatalf("build CLI: %v\n%s", err, output)
	}
	declarations := `import File from "@std/io.ms"
import Connection from "@std/net.ms"
import Synchronized from "@std/sync.ms"
import SynchronizedGuard from "@std/sync.ms"
type Val:
    val: Int
`
	for _, test := range []struct{ name, source, diagnostic string }{
		{"field type", "fn f(value: Val) -> Unit:\n    value.val = true\n", "expected Int"},
		{"fixed binding", "fn f() -> Unit:\n    let value = Val(val: 0)\n    value = Val(val: 1)\n", "cannot assign immutable binding"},
		{"type assignment", "fn f() -> Unit:\n    Val.val = 1\n", "assignment requires a record field"},
		{"file clone", "fn f(file: File) -> Unit:\n    file.clone()\n", "unknown or ambiguous member clone"},
		{"socket clone", "fn f(socket: Connection) -> Unit:\n    socket.clone()\n", "unknown or ambiguous member clone"},
		{"lock clone", "fn f(lock: Synchronized[Int]) -> Unit:\n    lock.clone()\n", "unknown or ambiguous member clone"},
		{"guard clone", "fn f(guard: SynchronizedGuard[Int]) -> Unit:\n    guard.clone()\n", "unknown or ambiguous member clone"},
	} {
		t.Run(test.name, func(t *testing.T) {
			dir := t.TempDir()
			file := filepath.Join(dir, "invalid.ms")
			if err := os.WriteFile(file, []byte(declarations+test.source), 0600); err != nil {
				t.Fatal(err)
			}
			outputFile := filepath.Join(dir, "generated.go")
			for _, args := range [][]string{{"check", file}, {"emit", file, "-o", outputFile}} {
				output, err := exec.Command(binary, args...).CombinedOutput()
				if err == nil || !strings.Contains(string(output), test.diagnostic) {
					t.Fatalf("%s: expected failed command with %q, got %v\n%s", args[0], test.diagnostic, err, output)
				}
			}
			if _, err := os.Stat(outputFile); !os.IsNotExist(err) {
				t.Fatalf("invalid source produced an output artifact: %v", err)
			}
		})
	}
}

func TestClonedRecordRetainsFileHandleLifetime(t *testing.T) {
	const source = `import files from "@std/io.ms"
import File from "@std/io.ms"
import IoError from "@std/io.ms"
import Optional from "@std/optional.ms"
type Holder:
    file: File
    label: String
export fn main() -> Int:
    match files().open("data.txt"):
        ok(file):
            match file.read(1):
                ok(chunk):
                    match chunk:
                        some(data):
                            if data.to_text() != some(value: "d"):
                                return 5
                        none:
                            return 6
                error(_):
                    return 7
            let original = Holder(file: file, label: "original")
            let copy = original.clone()
            copy.label = "copy"
            if original.label != "original":
                return 1
            copy.file.close()
            match original.file.read(1):
                error(cause):
                    match cause:
                        IoError.Closed:
                            return 0
                        _:
                            return 2
                ok(_):
                    return 3
        error(_):
            return 4
`
	result := compiler.CompileSource("file-clone.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "data.txt"), []byte("data"), 0600); err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(dir, "file-clone")
	if err := compiler.Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	command := exec.Command(binary)
	command.Dir = dir
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("record clone must retain the same file and closed state: %v\n%s", err, output)
	}
}
