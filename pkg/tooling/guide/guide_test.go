package guide

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// The cheat sheet's complete program is the one claim a reader can copy verbatim.
func TestCheatsheetProgramChecks(t *testing.T) {
	_, after, found := strings.Cut(Cheatsheet(), "<!-- complete -->\n```manuscript\n")
	if !found {
		t.Fatal("cheat sheet lost its complete program")
	}
	source, _, _ := strings.Cut(after, "```")
	result := compiler.CompileSource("cheatsheet.ms", source, compiler.Options{Entry: true, Tests: true, AnalyzeOnly: true})
	for _, issue := range result.Diagnostics {
		t.Errorf("cheat sheet program: %v", issue)
	}
}

// Agents read the guide every session, so its size is part of the contract.
func TestCheatsheetStaysShort(t *testing.T) {
	if n := len(Cheatsheet()); n > 2500 {
		t.Errorf("cheat sheet is %d bytes; keep it under 2500", n)
	}
}

func TestStdlibIndexAndModules(t *testing.T) {
	index := StdlibIndex()
	if !strings.Contains(index, "## @std/fs.ms") || !strings.Contains(index, "## prelude") {
		t.Errorf("index incomplete: %.200q", index)
	}
	for _, name := range []string{"json", "@std/json.ms"} {
		doc, ok := Module(name)
		if !ok || !strings.HasPrefix(doc, "# @std/json.ms") || !strings.Contains(doc, "parse") {
			t.Errorf("Module(%q) = %v, %.80q", name, ok, doc)
		}
	}
	if _, ok := Module("nope"); ok {
		t.Error("unknown module found")
	}
	names := ModuleNames()
	if len(names) < 20 || !contains(names, "json") || !contains(names, "prelude") {
		t.Errorf("module names = %v", names)
	}
}

func contains(list []string, want string) bool {
	for _, item := range list {
		if item == want {
			return true
		}
	}
	return false
}
