package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func invoke(t *testing.T, args ...string) (int, string, string) {
	t.Helper()
	dir := t.TempDir()
	out, err := os.Create(filepath.Join(dir, "stdout"))
	if err != nil {
		t.Fatal(err)
	}
	defer out.Close()
	errors, err := os.Create(filepath.Join(dir, "stderr"))
	if err != nil {
		t.Fatal(err)
	}
	defer errors.Close()
	stdout, stderr := os.Stdout, os.Stderr
	os.Stdout, os.Stderr = out, errors
	defer func() { os.Stdout, os.Stderr = stdout, stderr }()
	status := Run(args)
	output, err := os.ReadFile(out.Name())
	if err != nil {
		t.Fatal(err)
	}
	diagnostics, err := os.ReadFile(errors.Name())
	if err != nil {
		t.Fatal(err)
	}
	return status, string(output), string(diagnostics)
}

func sourceFile(t *testing.T, source string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "main.ms")
	if err := os.WriteFile(path, []byte(source), 0640); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0640); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestUsageAndInvalidOptions(t *testing.T) {
	for _, args := range [][]string{nil, {"--help"}, {"-h"}, {"--version"}, {"doc", "--help"}} {
		status, output, errors := invoke(t, args...)
		if status != 0 || output == "" || errors != "" {
			t.Fatalf("%v: %d, %q, %q", args, status, output, errors)
		}
	}
	for _, args := range [][]string{
		{"check"}, {"unknown", "missing.ms"}, {"check", "missing.ms", "--wat"},
		{"check", "missing.ms", "-o"}, {"check", "missing.ms", "--cpu-profile"},
		{"check", "missing.ms", "--check"}, {"fmt", "missing.ms", "--json"},
		{"check", "missing.ms", "--debug"}, {"check", "missing.ms", "--trace", "trace.out"},
		{"stdlib", "out", "extra"},
		{"build", "missing.ms", "--build-type"},
		{"build", "missing.ms", "--build-type", ""},
		{"build", "missing.ms", "--build-type", "Fast"},
		{"build", "missing.ms", "--build-type", "--help"},
		{"check", "missing.ms", "--build-type", "Release"},
		{"emit", "missing.ms", "--build-type", "Debug"},
		{"build", "missing.ms", "--debug", "--build-type", "Release"},
		{"build", "missing.ms", "--build-type", "Release", "--debug"},
		{"debug", "missing.ms", "--build-type", "RelWithDebInfo"},
		{"build", "missing.ms", "--build-type", "Debug", "--build-type", "Release"},
		{"build", "missing.ms", "--watch"}, {"check", "missing.ms", "--watch"},
		{"run", "missing.ms", "--watch", "--trace", "trace.out"},
	} {
		status, output, errors := invoke(t, args...)
		if status != 2 || output != "" || errors == "" {
			t.Fatalf("%v: %d, %q, %q", args, status, output, errors)
		}
	}
}

func TestHelpForEveryCommand(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	for _, command := range []string{
		"check", "lint", "lsp", "profile", "debug", "build", "emit", "run",
		"test", "fmt", "inspect", "diagram", "lock", "init", "doc", "stdlib", "help",
	} {
		for _, args := range [][]string{
			{command, "--help"}, {command, "-h"}, {"help", command},
			{command, "missing.ms", "--help"},
		} {
			status, output, errors := invoke(t, args...)
			if status != 0 || errors != "" || !strings.Contains(output, "Usage: ms "+command) ||
				!strings.Contains(output, "Options:") || !strings.Contains(output, "Examples:") {
				t.Fatalf("%v: %d, %q, %q", args, status, output, errors)
			}
		}
	}
	for command, defaultType := range map[string]string{"build": "Release", "run": "Release", "test": "Release", "profile": "RelWithDebInfo"} {
		status, output, errors := invoke(t, command, "--help")
		if status != 0 || errors != "" || !strings.Contains(output, "--build-type") || !strings.Contains(output, "Default build type: "+defaultType) || !strings.Contains(output, "MinSizeRel") {
			t.Fatalf("build types missing from %s help: %d, %q, %q", command, status, output, errors)
		}
	}
	status, output, errors := invoke(t, "doc", "--stdlib", "--help")
	if status != 0 || errors != "" || !strings.Contains(output, "ms doc --stdlib --json") {
		t.Fatalf("stdlib documentation help: %d, %q, %q", status, output, errors)
	}
	for _, command := range []string{"check", "build", "stdlib", "doc"} {
		status, output, errors := invoke(t, command)
		if status != 2 || output != "" || !strings.Contains(errors, "Usage: ms "+command) {
			t.Fatalf("missing arguments for %s: %d, %q, %q", command, status, output, errors)
		}
	}
	for _, args := range [][]string{{"help", "unknown"}, {"help", "run", "extra"}, {"unknown", "--help"}} {
		status, output, errors := invoke(t, args...)
		if status != 2 || output != "" || errors == "" {
			t.Fatalf("invalid help request %v: %d, %q, %q", args, status, output, errors)
		}
	}
}

func TestHelpPreservesProgramArgumentsAndOutputPaths(t *testing.T) {
	for _, args := range [][]string{
		{"run", "missing.ms", "--", "--help"},
		{"run", "missing.ms", "--", "-h"},
		{"emit", "missing.ms", "-o", "--help"},
		{"run", "missing.ms", "--cpu-profile", "-h"},
		{"run", "missing.ms", "--trace", "--help"},
		{"profile", "missing.ms", "--trace", "--", "--help"},
	} {
		status, output, errors := invoke(t, args...)
		if status != 1 || output != "" || errors == "" {
			t.Fatalf("help consumed a path or application argument %v: %d, %q, %q", args, status, output, errors)
		}
	}
}

func TestProfileTraceHelp(t *testing.T) {
	status, output, errors := invoke(t, "profile", "missing.ms", "--trace", "--help")
	if status != 0 || errors != "" || !strings.Contains(output, "Add --trace") || !strings.Contains(output, "overhead") {
		t.Fatalf("trace flag consumed profile help: %d, %q, %q", status, output, errors)
	}
}

func TestStructuredDiagnosticsAndFailedEmit(t *testing.T) {
	for _, tc := range []struct {
		source string
		status int
	}{
		{"fn value() -> Int:\n    return 3\n", 0},
		{"fn value() -> Int:\n    return unknown\n", 1},
		{"fn value(\n", 1},
	} {
		file := sourceFile(t, tc.source)
		status, output, errors := invoke(t, "check", file, "--json")
		var result struct {
			Format      int                 `json:"format"`
			Diagnostics []syntax.Diagnostic `json:"diagnostics"`
		}
		if status != tc.status || errors != "" || json.Unmarshal([]byte(output), &result) != nil || result.Format != 1 || result.Diagnostics == nil {
			t.Fatalf("invalid structured response: %d, %q, %q", status, output, errors)
		}
		if (len(result.Diagnostics) == 0) != (tc.status == 0) {
			t.Fatal("exit status disagrees with diagnostics")
		}
		if tc.status == 0 {
			continue
		}
		artifact := filepath.Join(t.TempDir(), "main.go")
		if err := os.WriteFile(artifact, []byte("previous artifact"), 0600); err != nil {
			t.Fatal(err)
		}
		status, _, _ = invoke(t, "emit", file, "-o", artifact)
		data, err := os.ReadFile(artifact)
		if status != 1 || err != nil || string(data) != "previous artifact" {
			t.Fatal("failed check replaced an output artifact")
		}
	}
}

func TestFormattingCheckAndPermissionPreservation(t *testing.T) {
	for _, tc := range []struct {
		name, source, want string
	}{
		{"spacing", "fn value() -> Int:   \n    return 3   \n", "fn value() -> Int:\n    return 3\n"},
		{"paragraphs", "fn value() -> Int:\n    if true: return 3\n    return 0\n", "fn value() -> Int:\n    if true: return 3\n\n    return 0\n"},
		{"expressions", "fn value() -> Int:\n    return sum(left: read(1), right: 2)\n", "fn value() -> Int:\n    return sum(\n        left: read(1),\n        right: 2\n    )\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			checkFormattingAndPermissions(t, tc.source, tc.want)
		})
	}
}

func checkFormattingAndPermissions(t *testing.T, source, want string) {
	t.Helper()
	file := sourceFile(t, source)
	originalInfo, err := os.Stat(file)
	if err != nil {
		t.Fatal(err)
	}
	before, _ := os.ReadFile(file)
	status, _, _ := invoke(t, "fmt", file, "--check")
	after, _ := os.ReadFile(file)
	if status != 1 || string(before) != string(after) {
		t.Fatal("format check modified source or missed drift")
	}
	if status, _, errors := invoke(t, "fmt", file); status != 0 {
		t.Fatal(errors)
	}
	formatted, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	if string(formatted) != want {
		t.Fatalf("formatted source: %q, want %q", formatted, want)
	}
	if status, _, errors := invoke(t, "fmt", file, "--check"); status != 0 {
		t.Fatal(errors)
	}
	info, err := os.Stat(file)
	if err != nil || info.Mode().Perm() != originalInfo.Mode().Perm() {
		t.Fatalf("permissions changed: %v, %v", info, err)
	}
}

func TestProjectLintChecksImportedSource(t *testing.T) {
	root := t.TempDir()
	for name, source := range map[string]string{
		"ms.toml":  "[project]\nname = \"lint\"\nsource = \".\"\nentry = \"main.ms\"\n",
		"main.ms":  "import value from \"./other.ms\"\nfn read() -> Int:\n    return value()\n",
		"other.ms": "export fn value() -> Int:   \n    return 3\n",
	} {
		if err := os.WriteFile(filepath.Join(root, name), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	status, output, errors := invoke(t, "lint", filepath.Join(root, "ms.toml"), "--json")
	var result struct {
		Format      int                   `json:"format"`
		Diagnostics []tooling.LintFinding `json:"diagnostics"`
	}
	if status != 1 || errors != "" || json.Unmarshal([]byte(output), &result) != nil || result.Format != 1 {
		t.Fatalf("%d, %q, %q", status, output, errors)
	}
	found := false
	for _, issue := range result.Diagnostics {
		if issue.Code == "MSL001" && issue.Position.File == "other.ms" {
			found = true
		}
	}
	if !found {
		t.Fatal("project lint ignored its imported module", result.Diagnostics)
	}
}

func TestSourceCommandsNeedNoNativeToolchain(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	file := sourceFile(t, "export fn value() -> Int:\n    return 3\n")
	for _, command := range []string{"check", "inspect", "diagram", "emit", "doc"} {
		status, output, errors := invoke(t, command, file)
		if status != 0 || output == "" || errors != "" {
			t.Fatalf("%s: %d, %q", command, status, errors)
		}
		if command == "emit" && (!strings.Contains(output, "package main") || strings.Contains(output, `"github.com/manuscript-lang/manuscript/pkg/runtime"`)) {
			t.Fatal("emit did not bundle runtime")
		}
	}
}

func TestSourceCommandsRetainProjectEntryValidation(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "ms.toml"), []byte("[project]\nname = \"invalid-entry\"\nsource = \".\"\nentry = \"main.ms\"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "main.ms"), []byte("export fn helper() -> Int:\n    return 1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, command := range []string{"check", "inspect", "diagram", "doc", "lock"} {
		status, _, errors := invoke(t, command, filepath.Join(root, "ms.toml"))
		if status != 1 || !strings.Contains(errors, "entry must export") {
			t.Fatalf("%s lost application entry checking: %d, %s", command, status, errors)
		}
	}
}

func TestFailedProfileDoesNotCreateAnArtifactDirectory(t *testing.T) {
	file := sourceFile(t, "fn value() -> Int:\n    return unknown\n")
	output := filepath.Join(t.TempDir(), "profile")
	status, _, errors := invoke(t, "profile", file, "-o", output)
	if status != 1 || errors == "" {
		t.Fatalf("invalid profile source: %d, %q", status, errors)
	}
	if _, err := os.Stat(output); !os.IsNotExist(err) {
		t.Fatal("failed checking created a profile artifact directory", err)
	}
}

func TestCLIErrorsNameTheFix(t *testing.T) {
	status, _, errors := invoke(t, "chek", "x.ms")
	if status != 2 || !strings.Contains(errors, "Did you mean 'ms check'?") {
		t.Fatalf("unknown command: %d, %q", status, errors)
	}
	status, _, errors = invoke(t, "check", "missing-file.ms")
	if status != 1 || !strings.Contains(errors, "file not found: missing-file.ms; check the path") || !strings.Contains(errors, "1 error;") {
		t.Fatalf("missing file: %d, %q", status, errors)
	}
	status, _, errors = invoke(t, "fmt", "missing-file.ms")
	if status != 1 || !strings.Contains(errors, "file not found: missing-file.ms") {
		t.Fatalf("missing format file: %d, %q", status, errors)
	}
	source := sourceFile(t, "fn value() -> Int:\n    return 1\n")
	status, _, errors = invoke(t, "check", source, "--bogus")
	if status != 2 || !strings.Contains(errors, "unknown option --bogus for ms check; run 'ms help check'") {
		t.Fatalf("unknown option: %d, %q", status, errors)
	}
}

func TestLintJSONReportsParseAndTypeErrors(t *testing.T) {
	for _, source := range []string{"export fn main() -> Int:\n    return \"a\"\n", "fn (\n"} {
		status, output, _ := invoke(t, "lint", sourceFile(t, source), "--json")
		var document struct {
			Format      int               `json:"format"`
			Diagnostics []json.RawMessage `json:"diagnostics"`
		}
		if status != 1 || json.Unmarshal([]byte(output), &document) != nil || document.Format != 1 || len(document.Diagnostics) == 0 {
			t.Fatalf("%q: %d, %q", source, status, output)
		}
	}
}

func TestArgumentMistakesNameTheProblem(t *testing.T) {
	source := sourceFile(t, "export fn main() -> Int:\n    return 0\n")
	status, _, errors := invoke(t, "build", source, "extra.ms")
	if status != 2 || !strings.Contains(errors, "unexpected extra argument extra.ms (ms build takes one file") {
		t.Fatalf("extra argument: %d, %q", status, errors)
	}
	status, _, errors = invoke(t, "build", "--bogus", source)
	if status != 2 || !strings.Contains(errors, "unknown option --bogus for ms build") {
		t.Fatalf("unknown flag: %d, %q", status, errors)
	}
	status, _, errors = invoke(t, "stdlib")
	if status != 2 || strings.Contains(errors, "file argument") || !strings.Contains(errors, "ms stdlib: pass exactly one directory") {
		t.Fatalf("stdlib usage: %d, %q", status, errors)
	}
	directory := t.TempDir()
	status, _, errors = invoke(t, "build", source, "-o", directory)
	if status != 2 || !strings.Contains(errors, "is a directory; pass a file path") || strings.Contains(errors, "rename") {
		t.Fatalf("output directory: %d, %q", status, errors)
	}
}

func TestDirectoryArgumentUsesManifestOrExplains(t *testing.T) {
	directory := t.TempDir()
	status, _, errors := invoke(t, "check", directory)
	if status != 0 || errors != "" {
		t.Fatalf("plain directory: %d, %q", status, errors)
	}
	if err := os.MkdirAll(filepath.Join(directory, "src"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "ms.toml"), []byte("[project]\nname = \"demo\"\nsource = \"src\"\nentry = \"./src/main.ms\"\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "src", "main.ms"), []byte("export fn main() -> Int:\n    return 0\n"), 0644); err != nil {
		t.Fatal(err)
	}
	status, output, errors := invoke(t, "check", directory)
	if status != 0 || !strings.Contains(output, "Checked "+filepath.Join(directory, "ms.toml")) {
		t.Fatalf("project directory: %d, %q, %q", status, output, errors)
	}
}

func TestLintIgnoresBundledStandardModules(t *testing.T) {
	source := sourceFile(t, "import TomlValue from \"@std/toml.ms\"\n\nexport fn main() -> Int:\n    let v: Optional[TomlValue] = none\n    match v:\n        some(_):\n            return 1\n        none:\n            return 0\n")
	status, output, errors := invoke(t, "lint", source)
	if status != 0 || strings.Contains(errors, "@std/") || output != "" {
		t.Fatalf("%d, %q, %q", status, output, errors)
	}
}
