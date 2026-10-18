package e2e_test

import (
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
	sources := map[string]string{"runner-faults.ms": runnerFaultSource}
	for _, file := range standardLibraryFixtures(t) {
		source, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		sources[file] = string(source)
	}
	for file, source := range sources {
		module, err := parser.Parse(file, source)
		if err != nil {
			t.Fatal(err)
		}
		for _, imported := range module.Imports {
			if strings.HasPrefix(imported.Path, "@std/") {
				covered[strings.TrimPrefix(imported.Path, "@std/")] = true
			}
		}
		var result compiler.Result
		if file == "runner-faults.ms" {
			result = compiler.CompileSource(file, source, compiler.Options{Tests: true, AnalyzeOnly: true})
		} else {
			result = compiler.CompileFile(file, compiler.Options{Tests: true, AnalyzeOnly: true})
		}
		if !result.Success() {
			t.Errorf("%s: %v", file, result.Diagnostics)
			continue
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

// This is a runner protocol regression, not a standard-library launcher.
// Faults intentionally escape their test blocks, so they need a separate
// transcript expectation. Verify every failure and the final passing test;
// merely observing a nonzero status could hide checking/building failures.
func TestRunnerFaultIsolation(t *testing.T) {
	module, parseErr := parser.Parse("faults.ms", runnerFaultSource)
	if parseErr != nil {
		t.Fatal(parseErr)
	}
	result := compiler.CompileSource("faults.ms", runnerFaultSource, compiler.Options{Tests: true})
	data, err := execute(t, result)
	if err == nil {
		t.Fatalf("expected stdlib faults, got success:\n%s", data)
	}
	output := string(data)
	faults := map[string]string{
		"panic unwinds Closeable":                 "intentional stdlib panic",
		"absent Optional unwrap faults":           "called Optional.get() on none",
		"sealed builder mutation faults":          "builder is sealed",
		"zero queue capacity faults":              "Queue: capacity must be between 1 and 9223372036854775807",
		"negative queue capacity faults":          "Queue: capacity must be between 1 and 9223372036854775807",
		"stale synchronized guard faults":         "Synchronized guard is closed",
		"unwrapping an out of range slice faults": "called Result.get() on error",
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

const runnerFaultSource = `import panic from "@std/faults.ms"
import Closeable from "@std/cleanup.ms"
import {ListBuilder} from "@std/collections.ms"
import {Queue} from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import {stdout, WriteStream} from "@std/io.ms"
import Bytes from "@std/bytes.ms"

fn emit(message: String) Unit:
    let written = stdout().write(message.to_bytes()).get()

type Resource:
    output: WriteStream

impl Closeable for Resource:
    fn close() Unit:
        let written = self.output.write("fault cleanup completed\n".to_bytes()).get()

test "panic unwinds Closeable":
    with resource = Resource(stdout()):
        return panic("intentional stdlib panic")

test "absent Optional unwrap faults":
    let absent: Optional[Int] = none
    let impossible = absent.get()

test "sealed builder mutation faults":
    let builder = ListBuilder[Int]()
    let sealed = builder.freeze()
    builder.append(1)

test "zero queue capacity faults":
    let queue = Queue[Int](0)

test "negative queue capacity faults":
    let queue = Queue[Int](-1)

test "stale synchronized guard faults":
    let state = Synchronized(1)
    let guard = state.lock()
    guard.close()
    let impossible = guard.get()

test "unwrapping an out of range slice faults":
    let impossible = ([1, 2]).slice(start: 0, end: 3).get()

test "negative split limit faults":
    let impossible = "a,b,c".split(separator: ",", max_parts: -1)

test "negative replace limit faults":
    let impossible = "aaa".replace(old: "a", new: "b", max_replacements: -1)

test "runner continues with fresh roots after faults":
    emit("fresh root after stdlib faults\n")
`
