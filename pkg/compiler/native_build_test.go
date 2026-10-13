package compiler

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/internal/gotoolchain"
	"os"
	"os/exec"
	"path/filepath"
	goruntime "runtime"
	"strings"
	"sync"
	"testing"
	"time"
)

// testProgram returns generated source unique to this run, so no cached
// archive can satisfy its compilation.
func testProgram(t *testing.T, label string) string {
	t.Helper()
	result := CompileSource("main.ms", fmt.Sprintf(`import stdout from "@std/io.ms"

export fn main() -> Int:
    match stdout().write(data: %q.to_bytes()):
        ok(_):
            return 0
        error(_):
            return 1
`, fmt.Sprint(label, " ", time.Now().UnixNano())), Options{Entry: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	return result.Source
}

func runProgram(t *testing.T, binary string) string {
	t.Helper()
	output, err := exec.Command(binary).CombinedOutput()
	if err != nil {
		t.Fatal(err, string(output))
	}
	return string(output)
}

func executableName(dir, name string) string {
	if goruntime.GOOS == "windows" {
		name += ".exe"
	}
	return filepath.Join(dir, name)
}

// fakeSDK links the selected SDK's sources beside a go executable path that
// does not exist, so a successful build proves no go command ran.
func fakeSDK(t *testing.T) string {
	t.Helper()
	_, root, _, err := goToolchain()
	if err != nil || root == "" {
		t.Skip("no SDK root available")
	}
	sdk := t.TempDir()
	for _, name := range []string{"VERSION", "src", "pkg"} {
		if err := os.Symlink(filepath.Join(root, name), filepath.Join(sdk, name)); err != nil {
			t.Skip("symbolic links unavailable:", err)
		}
	}
	return filepath.Join(sdk, "bin", "go")
}

func TestNativeBuildRunsNoGoCommand(t *testing.T) {
	t.Setenv("MANUSCRIPT_CACHE_DIR", t.TempDir())
	t.Setenv("MANUSCRIPT_GO", fakeSDK(t))
	t.Setenv("PATH", t.TempDir())
	if _, _, ok := nativeToolchain(); !ok {
		t.Skip("built-in Go tools unavailable: race build or different SDK release")
	}
	toolchain, err := queryToolchain()
	if err != nil || toolchain["GOVERSION"] != gotoolchain.Version() || toolchain["CGO_ENABLED"] != "0" {
		t.Fatalf("toolchain query: %v, %v", toolchain, err)
	}
	dir := t.TempDir()
	for _, kind := range []BuildType{Release, Debug} {
		for _, label := range []string{"cold", "warm"} {
			binary := executableName(dir, label+"-"+string(kind))
			if err := buildNative(testProgram(t, label+" "+string(kind)), binary, kind, nil); err != nil {
				t.Fatal(err)
			}
			if got := runProgram(t, binary); !strings.Contains(got, label+" "+string(kind)) {
				t.Fatalf("%s output %q", label, got)
			}
		}
	}
}

func TestNativeBuildRecompilesRemovedArchives(t *testing.T) {
	t.Setenv("MANUSCRIPT_CACHE_DIR", t.TempDir())
	if _, _, ok := nativeToolchain(); !ok {
		t.Skip("built-in Go tools unavailable: race build or different SDK release")
	}
	dir := t.TempDir()
	if err := buildNative(testProgram(t, "seed"), executableName(dir, "seed"), Release, nil); err != nil {
		t.Fatal(err)
	}
	cache, _ := archiveCache()
	archives, err := filepath.Glob(filepath.Join(cache, "*", "*.a"))
	if err != nil || len(archives) == 0 {
		t.Fatalf("no cached archives: %v", err)
	}
	// Trim half the cache, as a user cleaning it might.
	for _, archive := range archives[:len(archives)/2] {
		os.Remove(archive)
	}
	binary := executableName(dir, "rebuilt")
	if err := buildNative(testProgram(t, "rebuilt"), binary, Release, nil); err != nil {
		t.Fatal(err)
	}
	if got := runProgram(t, binary); !strings.Contains(got, "rebuilt") {
		t.Fatalf("rebuilt output %q", got)
	}
}

func TestConcurrentNativeBuildsShareWorkspace(t *testing.T) {
	t.Setenv("MANUSCRIPT_CACHE_DIR", t.TempDir())
	dir := t.TempDir()
	var group sync.WaitGroup
	errors := make([]error, 6)
	for i := range errors {
		group.Add(1)
		go func() {
			defer group.Done()
			// Pairs build identical source into distinct outputs.
			errors[i] = buildNative(testProgram(t, fmt.Sprint("program ", i/2)), executableName(dir, fmt.Sprint("program", i)), Release, nil)
		}()
	}
	group.Wait()
	for i, err := range errors {
		if err != nil {
			t.Fatal(err)
		}
		if got := runProgram(t, executableName(dir, fmt.Sprint("program", i))); !strings.Contains(got, fmt.Sprint("program ", i/2)) {
			t.Fatalf("program %d printed %q", i, got)
		}
	}
	entries, err := os.ReadDir(filepath.Join(os.Getenv("MANUSCRIPT_CACHE_DIR"), "manuscript", "workspaces"))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Fatalf("expected one published workspace, found %d", len(entries))
	}
}
