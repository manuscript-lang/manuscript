package compiler_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestTailResultIdentityLowering(t *testing.T) {
	for _, tc := range []struct {
		name, input, output, body string
		direct                    bool
	}{
		{"exact", "Int", "Int", "let output = try value\n    return ok(output)", true},
		{"mutable", "Int", "Int", "var output = try value\n    return ok(output)", false},
		{"intervening", "Int", "Int", "let output = try value\n    let unrelated = 1\n    return ok(output)", false},
		{"different binding", "Int", "Int", "let output = try value\n    return ok(7)", false},
		{"changed value", "Int", "Int", "let output = try value\n    return ok(output + 1)", false},
		{"different success type", "Int", "String", "let output = try value\n    return ok(output.to_string())", false},
		{"optional conversion", "Int", "Optional[Int]", "let output = try value\n    return ok(output)", false},
		{"nested function payload", "Optional[fn() Int]", "Optional[fn() Int]", "let output = try value\n    return ok(output)", false},
		{"function payload", "fn() Int", "fn() Int", "let output = try value\n    return ok(output)", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := "import TextError from \"@std/errors.ms\"\nfn tail(value: Result[" + tc.input + ", TextError]) Result[" + tc.output + ", TextError]:\n    " + tc.body + "\n"
			r := compiler.CompileSource("tail.ms", source, compiler.Options{})
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			if got := !strings.Contains(r.Source, ".Failed"); got != tc.direct {
				t.Fatalf("direct=%v want %v:\n%s", got, tc.direct, r.Source)
			}
		})
	}
}

func TestTailResultIdentityPreservesDebugBindings(t *testing.T) {
	source := `import TextError from "@std/errors.ms"
fn tail(value: Result[Int, TextError]) Result[Int, TextError]:
    let output = try value
    return ok(output)
`
	r := compiler.CompileSource("tail.ms", source, compiler.Options{BuildType: compiler.Debug})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if !strings.Contains(r.Source, ".Failed") {
		t.Fatal("Debug removed source binding")
	}
	found := false
	for _, local := range compiler.DebugLocals(r.Program) {
		if local.Name == "output" {
			found = true
		}
	}
	if !found {
		t.Fatal("debug-local inventory lost output")
	}
}

func TestTailResultIdentityKeepsErrorWidening(t *testing.T) {
	r := compiler.CompileSource("tail.ms", `import TextError from "@std/errors.ms"
fn tail(value: Result[Int, TextError]) Result[Int, Error]:
    let output = try value
    return ok(output)
`, compiler.Options{})
	if !r.Success() || !strings.Contains(r.Source, ".Failed") {
		t.Fatalf("lost widened error path: %v\n%s", r.Diagnostics, r.Source)
	}
}
