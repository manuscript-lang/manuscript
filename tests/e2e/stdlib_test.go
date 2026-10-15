package e2e_test

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Keep source checking cheap enough for make verify and require an explicit
// source-level home for every public module as the standard library grows.
// Imports and checked prelude type uses establish module coverage, not exhaustive operation/branch coverage.
func TestStandardLibrarySources(t *testing.T) {
	covered := map[string]bool{}
	files := append(standardLibraryFixtures(t), "testdata/stdlib/faults/faults.ms")
	for _, file := range files {
		module := standardLibraryFixture(t, file)
		for _, imported := range module.Imports {
			if strings.HasPrefix(imported.Path, "@std/") {
				covered[strings.TrimPrefix(imported.Path, "@std/")] = true
			}
		}
		result := compiler.CompileFile(file, compiler.Options{Tests: true, AnalyzeOnly: true})
		if !result.Success() {
			t.Errorf("%s: %v", file, result.Diagnostics)
		}
		// Prelude-only modules cannot be covered by imports. Count source uses
		// of their checked canonical types, rather than every ambient symbol.
		for _, checked := range result.Program.Modules {
			syntax.Nodes{Type: func(node *syntax.Type) {
				if typ, ok := node.Fact.(*checker.Type); ok && typ.Def != nil && checker.IsPreludeSymbol(typ.Def.Symbol) {
					covered[strings.TrimPrefix(typ.Def.Symbol.Module, "@std/")] = true
				}
			}}.Module(checked)
		}
	}
	entries, err := stdlib.Sources.ReadDir(".")
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".ms") {
			continue
		}
		source, err := stdlib.Sources.ReadFile(entry.Name())
		if err != nil {
			t.Fatal(err)
		}
		module, err := parser.Parse(entry.Name(), string(source))
		if err != nil {
			t.Fatal(err)
		}
		for _, declaration := range module.Declarations {
			if declaration.Export && !covered[entry.Name()] {
				t.Errorf("public stdlib module %s needs an executable Manuscript fixture", entry.Name())
				break
			}
		}
	}
}

// Faults are intentionally failing Manuscript tests, so they need a separate
// transcript expectation. Verify every failure and the final passing test;
// merely observing a nonzero status could hide checking/building failures.
func TestStandardLibraryFaults(t *testing.T) {
	file := "testdata/stdlib/faults/faults.ms"
	module := standardLibraryFixture(t, file)
	result := compiler.CompileFile(file, compiler.Options{Tests: true})
	data, err := execute(t, result)
	if err == nil {
		t.Fatalf("expected stdlib faults, got success:\n%s", data)
	}
	output := string(data)
	faults := map[string]string{
		"panic unwinds Closeable":                 "intentional stdlib panic",
		"absent Optional unwrap faults":           "called Optional.unwrap() on none",
		"sealed builder mutation faults":          "builder is sealed",
		"zero queue capacity faults":              "Queue: capacity must be between 1 and 9223372036854775807",
		"negative queue capacity faults":          "Queue: capacity must be between 1 and 9223372036854775807",
		"stale synchronized guard faults":         "Synchronized guard is closed",
		"unwrapping an out of range slice faults": "called Result.unwrap() on error",
		"negative split limit faults":             "split: max_parts must be nonnegative, found -1",
		"negative replace limit faults":           "replace: max_replacements must be nonnegative, found -1",
	}
	for _, declaration := range module.Declarations {
		if declaration.Kind != syntax.KindTest {
			continue
		}
		prefix := "FAIL "
		if declaration.Name == "runner continues with fresh roots after faults" {
			prefix = "PASS "
		}
		expected := prefix + "faults.ms::" + declaration.Name
		if prefix == "FAIL " {
			message, ok := faults[declaration.Name]
			if !ok {
				t.Fatalf("missing fault expectation for %q", declaration.Name)
			}
			expected += ": " + message
		}
		if !strings.Contains(output, expected) {
			t.Errorf("missing %s%s:\n%s", prefix, declaration.Name, output)
		}
	}
	for _, expected := range []string{"fault cleanup completed\n", "fresh root after stdlib faults\n", "10 tests, 9 failed"} {
		if !strings.Contains(output, expected) {
			t.Errorf("missing transcript %q:\n%s", expected, output)
		}
	}
}

// The Go harness only builds and launches tests. All library calls and
// behavioral expectations live in Manuscript test blocks.
func TestStandardLibraryConformance(t *testing.T) {
	for _, file := range standardLibraryFixtures(t) {
		t.Run(filepath.Base(file), func(t *testing.T) {
			module := standardLibraryFixture(t, file)
			tests := 0
			for _, declaration := range module.Declarations {
				if declaration.Kind == syntax.KindTest {
					tests++
				}
			}
			result := compiler.CompileFile(file, compiler.Options{Tests: true})
			data, err := execute(t, result)
			if err != nil {
				t.Fatalf("stdlib execution failed: %v\n%s", err, data)
			}
			if !strings.HasSuffix(strings.TrimSpace(string(data)), fmt.Sprintf("%d tests, 0 failed", tests)) {
				t.Fatalf("test runner did not execute all checks: %s", data)
			}
		})
	}
}

func standardLibraryFixtures(t *testing.T) []string {
	t.Helper()
	files, err := filepath.Glob("testdata/stdlib/*.ms")
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Fatal("missing Manuscript stdlib fixtures")
	}
	return files
}

func standardLibraryFixture(t *testing.T, file string) *syntax.Module {
	t.Helper()
	source, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	module, err := parser.Parse(file, string(source))
	if err != nil {
		t.Fatal(err)
	}
	for _, declaration := range module.Declarations {
		if declaration.Kind == syntax.KindTest {
			return module
		}
	}
	t.Fatalf("%s has no executable Manuscript test blocks", file)
	return nil
}
