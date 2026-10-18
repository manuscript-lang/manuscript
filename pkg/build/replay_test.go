package build

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"os"
	"os/exec"
	"path/filepath"
	goruntime "runtime"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestSplitTraceCommand(t *testing.T) {
	environment, arguments, ok := splitTraceCommand(`GOROOT='' /go/pkg/tool/link -o $WORK/b001/exe/a.out "-trimpath=/a b=>x;$WORK/b001=>" -s # internal`)
	if !ok || !slices.Equal(environment, []string{"GOROOT="}) || !slices.Equal(arguments, []string{"/go/pkg/tool/link", "-o", "$WORK/b001/exe/a.out", "-trimpath=/a b=>x;$WORK/b001=>", "-s"}) {
		t.Fatalf("%v %q %q", ok, environment, arguments)
	}
	if _, _, ok := splitTraceCommand(`/go/compile "unterminated`); ok {
		t.Fatal("accepted an unterminated quote")
	}
	if got := withoutBuildID([]string{"compile", "-buildid", "a/b", "-p", "main", "-buildid=c"}); !slices.Equal(got, []string{"compile", "-p", "main"}) {
		t.Fatalf("%q", got)
	}
}

// testProgram returns generated source unique to this run, so Go's package
// cache cannot satisfy its compilation and leave nothing to record.
func testProgram(t *testing.T, label string) string {
	t.Helper()
	result := compiler.CompileSource("main.ms", fmt.Sprintf(`import stdout from "@std/io.ms"

export fn main() Int:
    match stdout().write(data: %q.to_bytes()):
        ok(_):
            return 0
        error(_):
            return 1
`, fmt.Sprint(label, " ", time.Now().UnixNano())), compiler.Options{Entry: true})
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

func TestNativeBuildReplaysRecordedCommands(t *testing.T) {
	t.Setenv("MANUSCRIPT_CACHE_DIR", t.TempDir())
	dir := t.TempDir()
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
		// A cold Debug runtime compiles inside the go command's work directory,
		// which cannot be replayed; the next build finds it in Go's cache.
		for _, label := range []string{"cold", "first"} {
			if err := buildNative(testProgram(t, label+" "+string(kind)), executableName(dir, label+"-"+string(kind)), kind, nil); err != nil {
				t.Fatal(err)
			}
		}
		root, err := workspaceRoot()
		if err != nil {
			t.Fatal(err)
		}
		key, err := replayKey(kind, nil)
		if err != nil {
			t.Fatal(err)
		}
		source := testProgram(t, "second "+string(kind))
		imports, err := sourceImports(source)
		if err != nil {
			t.Fatal(err)
		}
		profile, ok := loadReplay(root, key, imports)
		if !ok {
			t.Fatalf("%s build recorded no replay profile", kind)
		}
		// A replay that cannot reach its tools must fall back to go build.
		broken := *profile
		broken.Compile = append([]string{filepath.Join(dir, "missing-compile")}, profile.Compile[1:]...)
		if err := saveReplay(root, key, &broken); err != nil {
			t.Fatal(err)
		}
		fallback := executableName(dir, "fallback-"+string(kind))
		if err := buildNative(testProgram(t, "fallback "+string(kind)), fallback, kind, nil); err != nil {
			t.Fatal(err)
		}
		if got := runProgram(t, fallback); !strings.Contains(got, "fallback "+string(kind)) {
			t.Fatalf("fallback output %q", got)
		}
		if refreshed, ok := loadReplay(root, key, imports); !ok || refreshed.Compile[0] != profile.Compile[0] {
			t.Fatal("fallback did not refresh the replay profile")
		}
		replayed := executableName(dir, "second-"+string(kind))
		if err := buildNative(source, replayed, kind, nil); err != nil {
			t.Fatal(err)
		}
		if got := runProgram(t, replayed); !strings.Contains(got, "second "+string(kind)) {
			t.Fatalf("replayed output %q", got)
		}
	}
}

func TestReplayRequiresMatchingImportsAndArchives(t *testing.T) {
	t.Setenv("MANUSCRIPT_CACHE_DIR", t.TempDir())
	// The first build may compile the runtime itself and record nothing.
	for _, label := range []string{"cold", "seed"} {
		if err := buildNative(testProgram(t, label), executableName(t.TempDir(), label), compiler.Release, nil); err != nil {
			t.Fatal(err)
		}
	}
	root, _ := workspaceRoot()
	key, err := replayKey(compiler.Release, nil)
	if err != nil {
		t.Fatal(err)
	}
	imports, _ := sourceImports(testProgram(t, "seed"))
	profile, ok := loadReplay(root, key, imports)
	if !ok {
		t.Fatal("no replay profile")
	}
	if _, ok := loadReplay(root, key, append(slices.Clone(imports), "fmt")); ok {
		t.Fatal("replayed source with different imports")
	}
	missing := *profile
	missing.Archives = append(slices.Clone(profile.Archives), filepath.Join(t.TempDir(), "trimmed.a"))
	if err := saveReplay(root, key, &missing); err != nil {
		t.Fatal(err)
	}
	if _, ok := loadReplay(root, key, imports); ok {
		t.Fatal("replayed with a missing package archive")
	}
}

func TestConcurrentNativeBuildsShareWorkspace(t *testing.T) {
	t.Setenv("MANUSCRIPT_CACHE_DIR", t.TempDir())
	dir := t.TempDir()
	// Sources are generated on the test goroutine; pairs share one source and
	// build into distinct outputs.
	sources := []string{testProgram(t, "program 0"), testProgram(t, "program 1"), testProgram(t, "program 2")}
	var group sync.WaitGroup
	errors := make([]error, 6)
	for i := range errors {
		group.Add(1)
		go func() {
			defer group.Done()
			errors[i] = buildNative(sources[i/2], executableName(dir, fmt.Sprint("program", i)), compiler.Release, nil)
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

func TestReplayRejectsExternalTools(t *testing.T) {
	profile := &replayProfile{Compile: []string{"external-compile"}, Link: []string{"external-link"}}
	err := profile.replay(t.TempDir(), "main", filepath.Join(t.TempDir(), "output"))
	if err == nil || !strings.Contains(err.Error(), "replay requires bundled") {
		t.Fatalf("external replay accepted: %v", err)
	}
}
