package e2e_test

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestStandaloneRunCache(t *testing.T) {
	root := t.TempDir()
	t.Setenv("MANUSCRIPT_CACHE_DIR", filepath.Join(root, "user-cache"))
	source := filepath.Join(root, "main.ms")
	write := func(code string) {
		t.Helper()
		if err := os.WriteFile(source, []byte(code), 0600); err != nil {
			t.Fatal(err)
		}
	}
	run := func(want int) {
		t.Helper()
		data, err := commandOutput(t, cliBinary, "run", source)
		if want == 0 && err != nil {
			t.Fatalf("run: %v: %s", err, data)
		}
		if want != 0 {
			if err == nil {
				t.Fatal("changed source was not executed")
			}
			if e, ok := err.(interface{ ExitCode() int }); !ok || e.ExitCode() != want {
				t.Fatalf("exit: %v: %s", err, data)
			}
		}
	}
	cache, err := compiler.DefaultBuildCacheDir()
	if err != nil {
		t.Fatal(err)
	}
	binaries := func() []string {
		t.Helper()
		files, err := filepath.Glob(filepath.Join(cache, "*.bin"))
		if err != nil {
			t.Fatal(err)
		}
		return files
	}
	write("export fn main() -> Int:\n    return 0\n")
	run(0)
	first := binaries()
	if len(first) != 1 {
		t.Fatalf("missing standalone cache: %v", first)
	}
	info, err := os.Stat(first[0])
	if err != nil {
		t.Fatal(err)
	}
	run(0)
	reused, err := os.Stat(first[0])
	if err != nil || !reused.ModTime().Equal(info.ModTime()) || !reflect.DeepEqual(binaries(), first) {
		t.Fatal("unchanged run rewrote its cache", err)
	}
	// Replace the artifact so corruption does not require writing an inode
	// the OS may still hold as an executable after the preceding run.
	corrupt := filepath.Join(cache, "corrupt.tmp")
	if err := os.WriteFile(corrupt, []byte("corrupt"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(corrupt, first[0]); err != nil {
		t.Fatal(err)
	}
	run(0)
	restored, err := os.ReadFile(first[0])
	if err != nil || string(restored) == "corrupt" {
		t.Fatal("corrupt cache was not rebuilt", err)
	}
	write("export fn main() -> Int:\n    return 7\n")
	run(7)
	if len(binaries()) != 2 {
		t.Fatal("source edit reused old artifact")
	}
	write("export fn main() -> Int:\n    return missing\n")
	if data, err := commandOutput(t, cliBinary, "run", source); err == nil {
		t.Fatalf("invalid source ran cached code: %s", data)
	}
	if len(binaries()) != 2 {
		t.Fatal("invalid source published an artifact")
	}
	if _, err := os.Stat(filepath.Join(root, ".ms-cache")); !os.IsNotExist(err) {
		t.Fatal("standalone run wrote into its source directory", err)
	}
}
