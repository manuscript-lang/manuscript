package e2e_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestResultArgumentInferenceKeepsLocalErrorScope(t *testing.T) {
	root := t.TempDir()
	sources := map[string]string{
		"domain.ms": `export type Cause[T]:
    value: T
export fn make() -> Result[Int, Cause[Int]]: error(Cause(7))
`,
		"helper.ms": `export fn erase[T](r: Result[T, Error]) -> Result[T, Error]: r
export fn forward[T, E: Error](r: Result[T, E]) -> Result[T, Error]: erase(r)
`,
		"main.ms": `import {first, first_generic} from "./first.ms"
import {second, second_generic} from "./second.ms"
import Cause from "./domain.ms"
import {expect_true, fail} from "@std/testing.ms"
fn describe(r: Result[Int, Error]) -> String:
    match r:
        ok(_): return "unexpected success"
        error(cause):
            return cause.message()
test "local implementations remain selected after inference and forwarding":
    if describe(first()) != "first 7": return fail("lost first scope")
    if describe(second()) != "second 7": return fail("lost second scope")
    if describe(first_generic()) != "first 7": return fail("lost first generic evidence")
    if describe(second_generic()) != "second 7": return fail("lost second generic evidence")
`,
	}
	for _, name := range []string{"first", "second"} {
		sources[name+".ms"] = `import {Cause, make} from "./domain.ms"
import {erase, forward} from "./helper.ms"
impl Error for Cause[T]:
    fn message() -> String: "` + name + ` {self.value}"
export fn ` + name + `() -> Result[Int, Error]: erase(make())
export fn ` + name + `_generic() -> Result[Int, Error]: forward(make())
`
	}
	for name, source := range sources {
		if err := os.WriteFile(filepath.Join(root, name), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	result := compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{Tests: true})
	data, err := execute(t, result)
	if err != nil || !strings.Contains(string(data), "0 failed") {
		t.Fatalf("scope regression: %v\n%s", err, data)
	}

	// Loading both implementation modules must not expose either implementation
	// to a raw Cause value in this importing module.
	invalid := sources["main.ms"] + `import erase from "./helper.ms"
fn invalid(r: Result[Int, Cause[Int]]) -> Result[Int, Error]: erase(r)
`
	if err := os.WriteFile(filepath.Join(root, "main.ms"), []byte(invalid), 0600); err != nil {
		t.Fatal(err)
	}
	result = compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{AnalyzeOnly: true})
	if result.Success() {
		t.Fatal("local Error implementation leaked into importing module")
	}
	for _, diagnostic := range result.Diagnostics {
		if diagnostic.Position.File != "main.ms" {
			t.Fatalf("failed outside raw use site: %v", result.Diagnostics)
		}
	}
}
