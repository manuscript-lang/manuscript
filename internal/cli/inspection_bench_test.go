package cli

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// Include output writing in this benchmark so the removed traversal is measured
// against the rest of the command. Legacy diagrams are an unchanged control.
func BenchmarkInspectProgram(b *testing.B) {
	for _, size := range []int{128, 256, 512} {
		b.Run(fmt.Sprint(size), func(b *testing.B) {
			var source strings.Builder
			for i := range size {
				fmt.Fprintf(&source, "fn value%d(x: Int) Int: return x + 1\n", i)
			}
			result := compiler.CompileSource("bench.ms", source.String(), compiler.Options{AnalyzeOnly: true})
			if !result.Success() {
				b.Fatal(result.Diagnostics)
			}
			for _, mode := range []string{"Inspect", "ScopedDiagram", "LegacyDiagram"} {
				b.Run(mode, func(b *testing.B) {
					inv := &invocation{command: "diagram", format: "ascii", output: filepath.Join(b.TempDir(), "out")}
					if mode == "Inspect" {
						inv.command = "inspect"
					}
					if mode == "ScopedDiagram" {
						inv.view = "calls"
					}
					b.ReportAllocs()
					b.ResetTimer()
					for range b.N {
						if status := inspectProgram(inv, result); status != 0 {
							b.Fatalf("%s returned %d", mode, status)
						}
					}
				})
			}
		})
	}
}
