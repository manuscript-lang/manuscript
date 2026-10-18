package compiler_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

func TestConstantStrideChunkSelection(t *testing.T) {
	for _, tc := range []struct {
		name, prefix, body string
		chunk              bool
	}{
		{"literal", "", "sum += 3\n        i += 1", true},
		{"negative literal", "", "sum += -3\n        i += 1", true},
		{"unchanged local", "let stride = 3\n    ", "sum += stride\n        i += 1", true},
		{"exact length", "let values = [1, 2, 3]\n    ", "sum += values.length()\n        i += 1", true},
		{"counter dependent", "", "sum += i\n        i += 1", false},
		{"carry dependent", "", "sum += sum\n        i += 1", false},
		{"counter cancellation", "", "sum += i - i\n        i += 1", false},
		{"carry cancellation", "", "sum += sum - sum\n        i += 1", false},
		{"step first", "", "i += 1\n        sum += 3", false},
		{"unary local", "let stride = 3\n    ", "sum += -stride\n        i += 1", false},
		{"call", "", "sum += identity(3)\n        i += 1", false},
		{"conditional", "", "if flag:\n            sum += 3\n        i += 1", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := "fn identity(n: Int) Int: return n\nfn probe(flag: Bool) Int:\n    " + tc.prefix + "var sum = 0\n    var i = 0\n    while i < 321:\n        " + tc.body + "\n    return sum\n"
			for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
				r := compiler.CompileSource("chunks.ms", source, compiler.Options{BuildType: kind})
				if !r.Success() {
					t.Fatal(r.Diagnostics)
				}
				want := tc.chunk && kind == compiler.Release
				if got := strings.Contains(r.Source, "321-i > 63"); got != want {
					t.Fatalf("chunk=%v want %v (%s):\n%s", got, want, kind, r.Source)
				}
			}
		})
	}
	r := compiler.CompileSource("small.ms", "fn probe() Int:\n    var sum = 0\n    var i = 0\n    while i < 255:\n        sum += 3\n        i += 1\n    return sum\n", compiler.Options{})
	if !r.Success() || strings.Contains(r.Source, "255-i > 63") {
		t.Fatalf("small chunk: %v\n%s", r.Diagnostics, r.Source)
	}
}
