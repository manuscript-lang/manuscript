package compiler_test

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func TestPipelinePreservesCheckedSourceForTools(t *testing.T) {
	source := `fn value(flag: Bool = not false) Bool:
    let callback = fn() Bool: return not (false or false)
    return (not false and callback()) or flag
`
	analyzed := compiler.CompileSource("source.ms", source, compiler.Options{AnalyzeOnly: true})
	lowered := compiler.CompileSource("source.ms", source, compiler.Options{})
	if !analyzed.Success() || !lowered.Success() || analyzed.Source != "" || lowered.Source == "" {
		t.Fatal("incorrect stage boundary", analyzed.Diagnostics, lowered.Diagnostics)
	}
	if !reflect.DeepEqual(analyzed.Program.Modules, lowered.Program.Modules) {
		t.Fatal("optimization rewrote the source AST")
	}
	if !reflect.DeepEqual(analyzed.Program.Effects, lowered.Program.Effects) || !reflect.DeepEqual(tooling.LintProgram(analyzed.Program), tooling.LintProgram(lowered.Program)) {
		t.Fatal("lowering changed the semantic tooling model")
	}
	if strings.Contains(lowered.Source, "rt.Unary(\"not\"") || strings.Contains(lowered.Source, "rt.Bool(false) || rt.Bool(false)") {
		t.Fatal("defaults or closures bypassed optimization", lowered.Source)
	}
	notCount := 0
	for expression := range lowered.Program.Expressions() {
		if expression.Kind == syntax.KindUnary && expression.Text == "not" {
			notCount++
		}
	}
	if notCount != 3 {
		t.Fatal("source expressions were removed from checked metadata", notCount)
	}
}

func TestPipelineChecksSkippedBooleanOperands(t *testing.T) {
	for _, source := range []string{
		"fn value() Bool: return false and missing\n",
		"fn value() Bool: return true or 3\n",
	} {
		result := compiler.CompileSource("invalid.ms", source, compiler.Options{})
		if result.Success() || result.Program == nil || result.Source != "" {
			t.Fatal("optimization hid an invalid operand", result.Diagnostics)
		}
	}
}

func TestSourceAndFileUseTheSamePipeline(t *testing.T) {
	source := "export fn main() Int:\n    if not false: return 3\n    return 0\n"
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "main.ms"), []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	fromSource := compiler.CompileSource("main.ms", source, compiler.Options{Entry: true})
	fromFile := compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{Entry: true})
	if !fromSource.Success() || !fromFile.Success() || fromSource.Source != fromFile.Source || !reflect.DeepEqual(fromSource.Program.Modules, fromFile.Program.Modules) {
		t.Fatal("source and file compilation diverged", fromSource.Diagnostics, fromFile.Diagnostics)
	}
}

func TestRecoveredSourceRetainsResolutionAndParseDiagnostics(t *testing.T) {
	source := "import value from \"./local.ms\"\nfn helper() Int: return 3\nfn broken(\n"
	result := compiler.CompileSource("editor.ms", source, compiler.Options{Recover: true, AnalyzeOnly: true})
	if result.Program == nil || result.Success() || result.Source != "" {
		t.Fatal("invalid editor snapshot escaped checking", result)
	}
	var parse, resolution bool
	for _, issue := range result.Diagnostics {
		parse = parse || issue.Phase == "parse"
		resolution = resolution || issue.Phase == "resolution"
	}
	if !parse || !resolution {
		t.Fatal("pipeline discarded stage diagnostics", result.Diagnostics)
	}
}
