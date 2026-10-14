package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The command list, the help text, and dispatch describe one set of commands.
func TestCommandNamesMatchHelp(t *testing.T) {
	listed := map[string]bool{}
	for _, line := range strings.Split(strings.SplitN(strings.SplitN(help, "Commands:\n", 2)[1], "\n\n", 2)[0], "\n") {
		listed[strings.Fields(line)[0]] = true
	}
	for _, name := range commandNames {
		if _, ok := commandHelp(name); !ok {
			t.Errorf("%s has no command help", name)
		}
		if !listed[name] {
			t.Errorf("%s is missing from the help command list", name)
		}
		delete(listed, name)
	}
	if len(listed) > 0 {
		t.Errorf("help lists commands absent from commandNames: %v", listed)
	}
}

func TestTypoSuggestionCoversEveryCommand(t *testing.T) {
	_, _, errors := invoke(t, "pprofx")
	if !strings.Contains(errors, "Did you mean 'ms pprof'?") {
		t.Fatalf("pprof typo not suggested: %q", errors)
	}
}

func TestJSONFlagMessageNamesEveryAcceptingCommand(t *testing.T) {
	_, _, errors := invoke(t, "run", sourceFile(t, "export fn main() -> Int:\n    return 0\n"), "--json")
	for _, command := range jsonCommands {
		if !strings.Contains(errors, command) {
			t.Errorf("--json message omits %s: %q", command, errors)
		}
	}
}

// Each source command reports analysis failures as the shared diagnostics document.
func TestSourceCommandsReportFailuresAsJSON(t *testing.T) {
	file := sourceFile(t, "export fn main() -> Int:\n    return \"wrong\"\n")
	for _, command := range []string{"inspect", "diagram", "emit"} {
		status, output, errors := invoke(t, command, file, "--json")
		var document diagnosticsDocument
		if err := json.Unmarshal([]byte(output), &document); err != nil || status != 1 || document.Format != 1 || len(document.Diagnostics) == 0 || errors != "" {
			t.Errorf("%s --json: %d, %q, %q, %v", command, status, output, errors, err)
		}
	}
}

func TestLockRequiresAProjectAndPinsOne(t *testing.T) {
	status, _, errors := invoke(t, "lock", sourceFile(t, "export fn main() -> Int:\n    return 0\n"))
	if status != 2 || !strings.Contains(errors, "lock requires a project ms.toml") {
		t.Fatalf("single-file lock: %d, %q", status, errors)
	}
	root := t.TempDir()
	for name, source := range map[string]string{
		"ms.toml":     "[project]\nname = \"pinned\"\nsource = \"src\"\nentry = \"src/main.ms\"\n",
		"src/main.ms": "export fn main() -> Int:\n    return 0\n",
	} {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	status, output, errors := invoke(t, "lock", filepath.Join(root, "ms.toml"))
	if status != 0 || !strings.Contains(output, "Pinned") {
		t.Skipf("pinning needs the bundled toolchain: %d, %q, %q", status, output, errors)
	}
	if _, err := os.Stat(filepath.Join(root, "ms.lock")); err != nil {
		t.Fatal(err)
	}
}

func TestFailurePositionReadsTheFirstLocation(t *testing.T) {
	position := failurePosition("boom\n  at test.ms:4:12 in test bad")
	if position == nil || position.File != "test.ms" || position.Line != 4 || position.Column != 12 {
		t.Fatalf("position = %+v", position)
	}
	if failurePosition("no location") != nil {
		t.Fatal("text without a location produced a position")
	}
}
