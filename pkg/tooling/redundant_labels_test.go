package tooling_test

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func TestDropRedundantLabels(t *testing.T) {
	declarations := `type Point:
    x: Int
    y: Int

fn bump(map: Int, key: Int, step: Int = 1) -> Int: map + key + step

type Counter:
    total: Int

interface Adder:
    fn add(amount: Int, extra: Int) -> Int

impl Adder for Counter:
    fn add(amount: Int, extra: Int) -> Int: self.total + amount + extra

fn use(map: Int, key: Int, y: Int, x: Int, counter: Counter) -> Int:
`
	for _, test := range []struct{ name, body, want string }{
		{"all in order", "return bump(map: map, key: key)", "return bump(map, key)"},
		{"label order differs", "return bump(key: key, map: map)", "return bump(key: key, map)"},
		{"defaulted parameter is not skipped", "return bump(key: key, map: 1)", "return bump(key: key, map: 1)"},
		{"labeled middle", "return bump(map: map, step: 3, key: key)", "return bump(map, step: 3, key)"},
		{"different name stays labeled", "return bump(map: key, key: map)", "return bump(map: key, key: map)"},
		{"expression stays labeled", "return bump(map: map + 1, key: key)", "return bump(map: map + 1, key)"},
		{"record fields", "return Point(x: x, y: y).x", "return Point(x, y).x"},
		{"record fields reordered", "return Point(y: y, x: x).x", "return Point(y: y, x).x"},
		{"method arguments", "return counter.add(amount: key, extra: y)", "return counter.add(amount: key, extra: y)"},
		{"method arguments by name", "let amount = key\n    let extra = y\n    return counter.add(amount: amount, extra: extra)", "let amount = key\n    let extra = y\n    return counter.add(amount, extra)"},
	} {
		t.Run(test.name, func(t *testing.T) {
			source := declarations + "    " + test.body + "\n"
			result := compiler.CompileSource("labels.ms", source, compiler.Options{AnalyzeOnly: true})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			got, _ := tooling.DropRedundantLabels(result.Program, source)
			want := declarations + "    " + test.want + "\n"
			if got != want {
				t.Fatalf("got:\n%s\nwant:\n%s", got, want)
			}
			again := compiler.CompileSource("labels.ms", got, compiler.Options{AnalyzeOnly: true})
			if !again.Success() {
				t.Fatalf("dropped labels changed validity: %v\n%s", again.Diagnostics, got)
			}
			if second, n := tooling.DropRedundantLabels(again.Program, got); n != 0 || second != got {
				t.Fatalf("not idempotent: %d\n%s", n, second)
			}
		})
	}
}

func TestDropRedundantLabelsSkipsBrokenSource(t *testing.T) {
	source := "fn f(a: Int) -> Int:\n    return g(a: a)\n"
	result := compiler.CompileSource("broken.ms", source, compiler.Options{AnalyzeOnly: true})
	if got, n := tooling.DropRedundantLabels(result.Program, source); n != 0 || got != source {
		t.Fatalf("edited source with errors: %d %q", n, got)
	}
}
