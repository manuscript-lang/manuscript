package e2e_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestFileSystemRemoveProtectsWorkingDirectory(t *testing.T) {
	// The native executable runs only in a disposable directory. Never run this
	// regression in the source checkout: on an unfixed runtime it deletes cwd.
	source := `import {filesystem, FileSystemError} from "@std/fs.ms"

export fn main() Int:
    let fs = filesystem()
    let invalid: Result[Unit, FileSystemError] = error(FileSystemError.InvalidInput)
    if fs.remove(path: "", recursive: true) != invalid: return 1
    if fs.remove(path: ".", recursive: true) != invalid: return 2
    if fs.remove(path: "child/..", recursive: true) != invalid: return 3
    match fs.canonicalize("."):
        error(_): return 8
        ok(base):
            if fs.remove(path: base, recursive: true) != invalid: return 4
    if fs.rename(source: "", destination: "moved") != invalid: return 5
    if fs.rename(source: "sentinel", destination: "") != invalid: return 6
    match fs.remove(path: "child", recursive: true):
        error(_): return 7
        ok(_): return 0
`
	result := compiler.CompileSource("remove.ms", source, compiler.Options{Entry: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	executable := filepath.Join(t.TempDir(), "remove-test")
	if runtime.GOOS == "windows" {
		executable += ".exe"
	}
	if err := build.Build(result.Source, executable); err != nil {
		t.Fatal(err)
	}
	directory := t.TempDir()
	if err := os.Mkdir(filepath.Join(directory, "child"), 0700); err != nil {
		t.Fatal(err)
	}
	fixtures := map[string]string{"sentinel": "untouched", "remove.ms": source, "child/data": "delete me"}
	for path, data := range fixtures {
		if err := os.WriteFile(filepath.Join(directory, path), []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
	}
	command := exec.Command(executable)
	command.Dir = directory
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("native removal regression: %v\n%s", err, output)
	}
	for _, path := range []string{"sentinel", "remove.ms"} {
		if data, err := os.ReadFile(filepath.Join(directory, path)); err != nil || string(data) != fixtures[path] {
			t.Fatalf("%s changed: %v", path, err)
		}
	}
	if _, err := os.Stat(filepath.Join(directory, "child")); !os.IsNotExist(err) {
		t.Fatal("explicit descendant not removed", err)
	}
}
