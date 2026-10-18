package lower

import (
	"fmt"
	"os"
	"reflect"
	"runtime"
	"sort"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

func TestGoPreservesSourceAndLocalsAcrossWorkers(t *testing.T) {
	source, err := os.ReadFile("../../tests/e2e/testdata/accept/interface-view-callables.ms")
	if err != nil {
		t.Fatal(err)
	}
	// Generic instances introduce successive single-function waves; ordinary
	// declarations introduce wide waves. Both must keep their own unit state.
	var chain strings.Builder
	chain.Write(source)
	chain.WriteString("\n" + mixedOperandsSource)
	chain.WriteString("\nfn step0[T](value: T) T: return value\n")
	for i := 1; i < 16; i++ {
		fmt.Fprintf(&chain, "fn step%d[T](value: T) T: return step%d(value)\n", i, i-1)
	}
	chain.WriteString("fn chain() Int: return step15(1)\n")
	program := checkedLoweringProgram(t, chain.String())
	previous := runtime.GOMAXPROCS(1)
	t.Cleanup(func() { runtime.GOMAXPROCS(previous) })
	var wantSource string
	var wantLocals []string
	for _, workers := range []int{1, 2, 8, 32} {
		runtime.GOMAXPROCS(workers)
		for range 3 {
			var locals []string
			got, err := Go(program, "benchmark.ms", Options{Tests: true, Locals: func(function, name string, binding *checker.Binding) {
				locals = append(locals, function+"/"+name+"/"+binding.ID+"/"+binding.Type.String())
			}})
			if err != nil {
				t.Fatal(err)
			}
			sort.Strings(locals)
			if wantSource == "" {
				wantSource, wantLocals = got, locals
			}
			if got != wantSource || !reflect.DeepEqual(locals, wantLocals) {
				t.Fatalf("source or debugger locals changed with %d workers", workers)
			}
		}
	}
}
