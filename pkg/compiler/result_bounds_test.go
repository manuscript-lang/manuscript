package compiler_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

const affineResultSource = `type Cause:
    text: String
impl Error for Cause:
    fn message() String: self.text
fn affine(n: Int) Result[Int, Cause]:
    if n < 0:
        return error(Cause("negative"))
    return ok(n + 1)
fn wrapped(n: Int) Result[Int, Cause]:
    let value = try affine(n)
    return ok(value)
fn twice(n: Int) Result[Int, Cause]:
    let value = try wrapped(n)
    return ok(value)
`

func TestSuccessfulResultIntBounds(t *testing.T) {
	for _, tc := range []struct {
		name, helper, prefix, argument string
		checked                        bool
	}{
		{"direct", "affine", "", "i", false},
		{"one wrapper", "wrapped", "", "i", false},
		{"two wrappers", "twice", "", "i", true},
		{"unknown argument", "affine", "", "value", true},
		{"callable alias", "alias", "let alias = affine\n    ", "i", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := affineResultSource + "fn probe(value: Int) Int:\n    " + tc.prefix + "var sum = 0\n    var i = 0\n    while i < 1000:\n        if let found = " + tc.helper + "(" + tc.argument + "):\n            sum += found\n        else:\n            sum -= 1\n        i += 1\n    return sum\n"
			for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
				r := compiler.CompileSource("result.ms", source, compiler.Options{BuildType: kind})
				if !r.Success() {
					t.Fatal(r.Diagnostics)
				}
				want := tc.checked || kind == compiler.Debug
				if got := strings.Contains(r.Source, "sum = rt.IntAdd("); got != want {
					t.Fatalf("checked=%v want %v (%s):\n%s", got, want, kind, r.Source)
				}
				if !strings.Contains(r.Source, "rt.IntAdd(n, int(1))") {
					t.Fatalf("changed general callee:\n%s", r.Source)
				}
			}
		})
	}
}

func TestSuccessfulResultBoundsRejectDifferentReturns(t *testing.T) {
	for _, helper := range []string{
		`fn affine(n: Int = 0) Result[Int, Cause]:
    if n < 0: return error(Cause("negative"))
    return ok(n + 1)
`,
		`fn affine(n: Int) Result[Int, Cause]:
    if n < 0: return ok(9223372036854775807)
    return ok(n + 1)
`,
		`fn affine(n: Int) Result[Int, Cause]:
    if n < 0: return error(Cause("negative {n}"))
    return ok(n + 1)
`,
		`fn affine(n: Int) Result[Int, Cause]:
    if n < 0: return error(Cause())
    return ok(n + 1)
`,
		`fn affine(n: Int) Result[Int, Cause]:
    if n < 0:
        return error(Cause(match some(n):
            some(value):
                return ok(9223372036854775807)
            none: "negative"
        ))
    return ok(n + 1)
`,
		`fn affine(n: Int) Result[Int, Cause]:
    if n < 0: return error(Cause("negative"))
    return ok(n + 9223372036854775807)
`,
	} {
		cause := "type Cause:\n    text: String\nimpl Error for Cause:\n    fn message() String: self.text\n"
		if strings.Contains(helper, "Cause()") {
			cause = strings.Replace(cause, "text: String", "text: String = \"negative\"", 1)
		}
		source := cause + helper + `fn probe() Int:
    var sum = 0
    var i = -1
    while i < 1000:
        if let found = affine(i):
            sum += found
        i += 1
    return sum
`
		r := compiler.CompileSource("fallback.ms", source, compiler.Options{})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		if !strings.Contains(r.Source, "sum = rt.IntAdd(") {
			t.Fatalf("unsafe summary selected:\n%s", r.Source)
		}
	}
}

func TestSuccessfulResultBoundsKeepPeerAndPrefixChecks(t *testing.T) {
	for _, body := range []string{
		"if let found = affine(peer):\n            sum += found\n        peer += 1",
		"if let found = affine(i):\n            sum += found\n            sum -= found",
	} {
		source := affineResultSource + "fn probe() Int:\n    var sum = 9223372036854775807\n    var peer = 0\n    var i = 0\n    while i < 1000:\n        " + body + "\n        i += 1\n    return sum\n"
		r := compiler.CompileSource("peers.ms", source, compiler.Options{})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		if !strings.Contains(r.Source, "sum = rt.IntAdd(") {
			t.Fatalf("peer/prefix check removed:\n%s", r.Source)
		}
	}
}

func TestSuccessfulResultBoundsRestoreElseScope(t *testing.T) {
	source := affineResultSource + `fn probe(found: Int) Int:
    var sum = 0
    var i = 0
    while i < 1000:
        if let found = affine(i):
            sum += found
        else:
            sum += found
        i += 1
    return sum
`
	r := compiler.CompileSource("scope.ms", source, compiler.Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Count(r.Source, "sum = rt.IntAdd(") != 2 {
		t.Fatalf("success facts reached else:\n%s", r.Source)
	}
}

func TestSuccessfulResultSubtractBounds(t *testing.T) {
	source := strings.ReplaceAll(affineResultSource, "n + 1", "n - 2") + `fn probe() Int:
    var sum = 0
    var i = 0
    while i < 1000:
        if let found = wrapped(i):
            sum += found
        i += 1
    return sum
`
	r := compiler.CompileSource("subtract.ms", source, compiler.Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Contains(r.Source, "sum = rt.IntAdd(") || !strings.Contains(r.Source, "rt.IntSubtract(n, int(2))") {
		t.Fatalf("subtract bounds changed general helper or kept safe caller check:\n%s", r.Source)
	}
}

func TestSuccessfulResultBoundsDeterministic(t *testing.T) {
	source := affineResultSource + `fn probe() Int:
    var sum = 0
    var i = 0
    while i < 1000:
        if let found = wrapped(i):
            sum += found
        i += 1
    return sum
`
	first := compiler.CompileSource("deterministic.ms", source, compiler.Options{})
	if !first.Success() {
		t.Fatal(first.Diagnostics)
	}
	outputs := make(chan string, 8)
	for range 8 {
		go func() {
			r := compiler.CompileSource("deterministic.ms", source, compiler.Options{})
			if !r.Success() {
				outputs <- "compile failed"
				return
			}
			outputs <- r.Source
		}()
	}
	for range 8 {
		if source := <-outputs; source != first.Source {
			t.Fatal("concurrent compilation changed output")
		}
	}
}
