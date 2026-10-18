package checker

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Every iteration parses a fresh tree: Check annotates the source nodes.
// Standard declarations are warm, matching repeated checking in one process.
func benchmarkCheck(b *testing.B, source string) {
	ensureStandard()
	run := func() {
		module, err := parser.Parse("performance.ms", source)
		if err != nil {
			b.Fatal(err)
		}
		program := Check([]*syntax.Module{module}, nil)
		if len(program.Diagnostics) != 0 {
			b.Fatal(program.Diagnostics)
		}
	}
	run()
	b.ReportAllocs()
	b.ResetTimer()
	for b.Loop() {
		run()
	}
}

func BenchmarkCheckerEffects(b *testing.B) {
	for _, shape := range []string{"chain", "pure", "pure-chain", "cycle", "fanout"} {
		for _, n := range []int{128, 256, 512} {
			b.Run(fmt.Sprintf("%s/%d", shape, n), func(b *testing.B) {
				var source strings.Builder
				source.WriteString("type Cell:\n    value: Int\n")
				for i := 0; i < n; i++ {
					fmt.Fprintf(&source, "fn f%d(cell: Cell) Int: ", i)
					switch {
					case shape == "pure":
						source.WriteString("1\n")
					case shape == "fanout" && i != n-1:
						fmt.Fprintf(&source, "f%d(cell)\n", n-1)
					case i != n-1:
						fmt.Fprintf(&source, "f%d(cell)\n", i+1)
					case shape == "pure-chain":
						source.WriteString("1\n")
					case shape == "cycle":
						source.WriteString("cell.value + f0(cell)\n")
					default:
						source.WriteString("cell.value\n")
					}
				}
				benchmarkCheck(b, source.String())
			})
		}
	}
}

func BenchmarkCheckerGenerics(b *testing.B) {
	for _, n := range []int{128, 256, 512} {
		b.Run(fmt.Sprint(n), func(b *testing.B) {
			var source strings.Builder
			source.WriteString("fn identity[T](value: T) T: value\nfn use() Unit:\n")
			for i := 0; i < n; i++ {
				fmt.Fprintf(&source, "    let v%d = identity(some(%d))\n", i, i)
			}
			benchmarkCheck(b, source.String())
		})
	}
}

func BenchmarkCheckerWideRecord(b *testing.B) {
	for _, n := range []int{16, 32, 64} {
		b.Run(fmt.Sprint(n), func(b *testing.B) {
			var source strings.Builder
			source.WriteString("type Wide[")
			for i := 0; i < n; i++ {
				if i > 0 {
					source.WriteString(", ")
				}
				fmt.Fprintf(&source, "T%d", i)
			}
			source.WriteString("]:\n")
			for i := 0; i < n; i++ {
				fmt.Fprintf(&source, "    f%d: T%d\n", i, i)
			}
			source.WriteString("fn use(value: Wide[")
			for i := 0; i < n; i++ {
				if i > 0 {
					source.WriteString(", ")
				}
				source.WriteString("Int")
			}
			source.WriteString("]) Int:\n")
			for i := 0; i < n; i++ {
				fmt.Fprintf(&source, "    let v%d = value.f%d\n", i, i)
			}
			source.WriteString("    return 0\n")
			benchmarkCheck(b, source.String())
		})
	}
}

func BenchmarkCheckerSubstitution(b *testing.B) {
	for _, n := range []int{16, 32, 64, 128} {
		variables := make([]*Type, n)
		arguments := make([]*Type, n)
		fields := make([]Param, n)
		for i := 0; i < n; i++ {
			variables[i] = &Type{ID: fmt.Sprintf("T%d", i), Name: fmt.Sprintf("T%d", i), Kind: "variable"}
			arguments[i] = primitive("Int")
			fields[i] = Param{Name: fmt.Sprintf("field%d", i), Type: variables[i]}
		}
		typ := &Type{Def: &Definition{Variables: variables, Fields: fields, Cases: []Case{{Name: "Value", Fields: fields}}}, Args: arguments}
		b.Run(fmt.Sprintf("fields/%d", n), func(b *testing.B) {
			b.ReportAllocs()
			for b.Loop() {
				if len(Fields(typ)) != n {
					b.Fatal("lost fields")
				}
			}
		})
		b.Run(fmt.Sprintf("cases/%d", n), func(b *testing.B) {
			b.ReportAllocs()
			for b.Loop() {
				if len(Cases(typ)[0].Fields) != n {
					b.Fatal("lost fields")
				}
			}
		})
	}
	// Keep nongeneric fields and phantom alternatives as controls: neither
	// should pay for a map of bindings it does not use.
	b.Run("nongeneric", func(b *testing.B) {
		typ := &Type{Def: &Definition{Fields: []Param{{Name: "value", Type: primitive("Int")}}}}
		b.ReportAllocs()
		for b.Loop() {
			Fields(typ)
		}
	})
	b.Run("empty-cases", func(b *testing.B) {
		variables := make([]*Type, 128)
		arguments := make([]*Type, 128)
		for i := range variables {
			variables[i] = &Type{ID: fmt.Sprint(i), Kind: "variable"}
			arguments[i] = primitive("Int")
		}
		typ := &Type{Args: arguments, Def: &Definition{Variables: variables, Cases: []Case{{Name: "Empty"}}}}
		b.ReportAllocs()
		b.ResetTimer()
		for b.Loop() {
			Cases(typ)
		}
	})
}

// Generic application walks are a separate control from effect propagation.
func BenchmarkCheckerGenericGraph(b *testing.B) {
	for _, n := range []int{8, 10, 12} {
		b.Run(fmt.Sprint(n), func(b *testing.B) {
			var source strings.Builder
			source.WriteString("fn f0[T](value: T) T: value\n")
			for i := 1; i <= n; i++ {
				fmt.Fprintf(&source, "fn f%d[T](value: T) T: f%d(f%d(value))\n", i, i-1, i-1)
			}
			benchmarkCheck(b, source.String())
		})
	}
}
