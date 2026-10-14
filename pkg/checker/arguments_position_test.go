package checker_test

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A missing argument is reported at the call, including calls with no arguments.
func TestMissingArgumentPointsAtCall(t *testing.T) {
	for _, tt := range []struct {
		name, source string
		line, column int
	}{
		{"no arguments", "type T:\n    y: Int\nfn make() -> T:\n    return T()\n", 4, 12},
		{"some arguments", "fn f(a: Int, b: Int) -> Int:\n    return a\nfn g() -> Int:\n    return f(a: 1)\n", 4, 12},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("position.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			if len(p.Diagnostics) != 1 {
				t.Fatal(p.Diagnostics)
			}
			d := p.Diagnostics[0]
			if d.Position.Line != tt.line || d.Position.Column != tt.column {
				t.Fatalf("got %d:%d for %v", d.Position.Line, d.Position.Column, d)
			}
		})
	}
}
