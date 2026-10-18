package syntax_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func BenchmarkTraversal(b *testing.B) {
	for _, size := range []int{64, 128, 256} {
		var source strings.Builder
		for i := range size {
			fmt.Fprintf(&source, "fn sample%d(value: Int = 3) Int:\n    let items = [value, 2, 3]\n    if value >= 0:\n        return items[0].get(0) + value\n    return 0\n", i)
		}
		module, err := parser.Parse("walk.ms", source.String())
		if err != nil {
			b.Fatal(err)
		}
		b.Run(fmt.Sprintf("Visitor/%d", size), func(b *testing.B) {
			count := 0
			visitor := syntax.Visitor{Expression: func(*syntax.Expression) { count++ }}
			b.ReportAllocs()
			for b.Loop() {
				for _, declaration := range module.Declarations {
					visitor.Walk(declaration)
				}
			}
			if count == 0 {
				b.Fatal("no expressions visited")
			}
		})
		b.Run(fmt.Sprintf("Nodes/%d", size), func(b *testing.B) {
			count := 0
			nodes := syntax.Nodes{Expression: func(*syntax.Expression) { count++ }}
			b.ReportAllocs()
			for b.Loop() {
				nodes.Module(module)
			}
			if count == 0 {
				b.Fatal("no expressions visited")
			}
		})
	}
}
