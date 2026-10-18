package lower

import (
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/frontend"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func checkedLoweringProgram(tb testing.TB, source string) *checker.Program {
	tb.Helper()
	graph := frontend.LoadSource("benchmark.ms", source, frontend.Options{})
	if len(graph.Diagnostics) != 0 {
		tb.Fatal(graph.Diagnostics)
	}
	program := checker.Check(graph.Modules, graph.Imports)
	if len(program.Diagnostics) != 0 {
		tb.Fatal(program.Diagnostics)
	}
	return program
}

// Programs are parsed and checked before timing: this measures lowering and
// printing, with the checked model reused as compiler/debugger clients do.
func BenchmarkGo(b *testing.B) {
	b.Run("Empty", func(b *testing.B) { benchmarkGo(b, "") })
	b.Run("Single", func(b *testing.B) { benchmarkGo(b, "fn work() Int: return 1\n") })
	for _, size := range []int{64, 128, 256} {
		b.Run(fmt.Sprintf("Statements/%d", size), func(b *testing.B) {
			var source strings.Builder
			source.WriteString("fn work() Int:\n    var value = 0\n")
			for range size {
				source.WriteString("    value += 1\n")
			}
			source.WriteString("    return value\n")
			benchmarkGo(b, source.String())
		})
		b.Run(fmt.Sprintf("Functions/%d", size), func(b *testing.B) {
			var source strings.Builder
			for i := range size {
				fmt.Fprintf(&source, "fn work%d(value: Int) Int: return value + %d\n", i, i)
			}
			benchmarkGo(b, source.String())
		})
	}
	for _, size := range []int{16, 32, 64} {
		b.Run(fmt.Sprintf("GenericChain/%d", size), func(b *testing.B) {
			var source strings.Builder
			source.WriteString("fn step0[T](value: T) T: return value\n")
			for i := 1; i < size; i++ {
				fmt.Fprintf(&source, "fn step%d[T](value: T) T: return step%d(value)\n", i, i-1)
			}
			fmt.Fprintf(&source, "fn work() Int: return step%d(1)\n", size-1)
			benchmarkGo(b, source.String())
		})
	}
	for _, size := range []int{512, 1024, 2048} {
		b.Run(fmt.Sprintf("Literal/%d", size), func(b *testing.B) {
			source := "fn work() List[Int]: return [" + strings.Repeat("1, ", size-1) + "1]\n"
			benchmarkGo(b, source)
		})
	}
	for _, fixture := range []struct{ name, file string }{
		{"NativeDefaults", "../../scripts/bench-lowering/native-defaults.ms"},
		{"Cleanup", "../../scripts/bench-lowering/production.ms"},
		{"Views", "../../tests/e2e/testdata/accept/interface-view-callables.ms"},
	} {
		b.Run(fixture.name, func(b *testing.B) {
			source, err := os.ReadFile(fixture.file)
			if err != nil {
				b.Fatal(err)
			}
			benchmarkGo(b, string(source))
		})
	}
}

func benchmarkGo(b *testing.B, source string) {
	b.Helper()
	program := checkedLoweringProgram(b, source)
	b.ReportAllocs()
	b.ResetTimer()
	for b.Loop() {
		if _, err := Go(program, "benchmark.ms", Options{Tests: true}); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkSourceDirective(b *testing.B) {
	for _, filename := range []string{"source.ms", "dir/longer source filename.ms", "dir/invalid\r\nname.ms"} {
		b.Run(filename, func(b *testing.B) {
			pos := syntax.Position{File: filename, Line: 123}
			b.ReportAllocs()
			for b.Loop() {
				_ = sourceDirective(pos)
			}
		})
	}
}

// Standard generation has no source markers and is a negative control for
// source-directive changes. It also exercises every declaration/native ABI.
func BenchmarkStandardRuntime(b *testing.B) {
	_ = checker.StandardInventory()
	b.ReportAllocs()
	b.ResetTimer()
	for b.Loop() {
		if _, err := StandardRuntime(); err != nil {
			b.Fatal(err)
		}
	}
}
