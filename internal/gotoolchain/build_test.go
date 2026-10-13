package gotoolchain

import (
	"debug/buildinfo"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func testRoot(t *testing.T) string {
	t.Helper()
	tool := os.Getenv("MANUSCRIPT_GO")
	if tool == "" {
		tool = "go"
	}
	output, err := exec.Command(tool, "env", "GOROOT").Output()
	if err != nil {
		t.Skipf("no Go SDK: %v", err)
	}
	root := strings.TrimSpace(string(output))
	if err := Supported(root); err != nil {
		t.Skipf("SDK cannot be used with built-in tools: %v", err)
	}
	return root
}

func writeModule(t *testing.T, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for name, data := range files {
		path := filepath.Join(dir, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(data), 0644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestBuildExecutable(t *testing.T) {
	root := testRoot(t)
	module := writeModule(t, map[string]string{
		"go.mod":            "module example.com/app\n\ngo 1.25.0\n",
		"main.go":           "package main\n\nimport (\n\t\"example.com/app/greeting\"\n\t\"fmt\"\n)\n\nfunc main() { fmt.Println(greeting.Text) }\n",
		"greeting/g.go":     "package greeting\n\nimport _ \"embed\"\n\n//go:embed text.txt\nvar Text string\n",
		"greeting/text.txt": "hello from the built-in tools",
	})
	cache := t.TempDir()
	output := filepath.Join(t.TempDir(), "app")
	if runtime.GOOS == "windows" {
		output += ".exe"
	}
	config := Config{GOROOT: root, ModuleRoot: module, ModulePath: "example.com/app", Dir: module, ImportPath: "example.com/app",
		Trimpath: true, LDFlags: "-s -w", Cache: cache, Environment: os.Environ(), Output: output}
	started := time.Now()
	if err := Build(config); err != nil {
		t.Fatal(err)
	}
	cold := time.Since(started)
	data, err := exec.Command(output).CombinedOutput()
	if err != nil || strings.TrimSpace(string(data)) != "hello from the built-in tools" {
		t.Fatalf("%v: %q", err, data)
	}
	info, err := buildinfo.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	settings := map[string]string{}
	for _, setting := range info.Settings {
		settings[setting.Key] = setting.Value
	}
	if info.Path != "example.com/app" || settings["-trimpath"] != "true" || settings["CGO_ENABLED"] != "0" || info.GoVersion != Version() {
		t.Fatalf("unexpected build information: %v", info)
	}
	// A rebuild reuses every archive and only links.
	started = time.Now()
	if err := Build(config); err != nil {
		t.Fatal(err)
	}
	t.Logf("cold build %v, cached build %v", cold, time.Since(started))
}

func TestBuildReportsCompileErrors(t *testing.T) {
	root := testRoot(t)
	module := writeModule(t, map[string]string{
		"go.mod":  "module example.com/broken\n\ngo 1.25.0\n",
		"main.go": "package main\n\nfunc main() { undefined() }\n",
	})
	err := Build(Config{GOROOT: root, ModuleRoot: module, ModulePath: "example.com/broken", Dir: module, ImportPath: "example.com/broken",
		Cache: t.TempDir(), Environment: os.Environ(), Output: filepath.Join(t.TempDir(), "broken")})
	if err == nil || !strings.Contains(err.Error(), "undefined: undefined") {
		t.Fatalf("expected a compile error, got %v", err)
	}
}
