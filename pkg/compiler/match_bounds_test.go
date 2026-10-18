package compiler_test

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

const boundedMatchSource = `type Shape:
    case Circle(r: Int)
    case Square(s: Int)
    case Tri(b: Int)
fn area(s: Shape) Int:
    var out = 0
    match s:
        Circle(r):
            out = r * 3
        Square(side):
            out = side * side
        Tri(base):
            out = base
    return out
`
const boundedMatchProbe = `fn probe() Int:
    let shapes = [Shape.Circle(2), Shape.Square(3), Shape.Tri(4)]
    var sum = 0
    var i = 0
    while i < 321:
        sum += area(shapes.get(i % 3))
        i += 1
    return sum
`

func TestBoundedMatchSelection(t *testing.T) {
	for _, tc := range []struct {
		name, source string
		clone        bool
	}{
		{"closed list", boundedMatchSource + boundedMatchProbe, true},
		{"alias", boundedMatchSource + strings.Replace(boundedMatchProbe, "    var sum", "    let alias = shapes\n    var sum", 1), false},
		{"capture", boundedMatchSource + strings.Replace(boundedMatchProbe, "    var sum", "    let read = fn() Int: shapes.length()\n    var sum", 1), false},
		{"supplied none", boundedMatchSource + strings.ReplaceAll(boundedMatchProbe, "shapes.get(i % 3)", "shapes.get(i % 3, none)"), false},
		{"supplied default", boundedMatchSource + strings.ReplaceAll(boundedMatchProbe, "shapes.get(i % 3)", "shapes.get(i % 3, Shape.Circle(1))"), false},
		{"mutation", boundedMatchSource + strings.Replace(boundedMatchProbe, "    var sum", "    shapes.append(Shape.Tri(1))\n    var sum", 1), false},
		{"function value", boundedMatchSource + strings.Replace(strings.Replace(boundedMatchProbe, "    var sum", "    let f = area\n    var sum", 1), "sum += area(", "sum += f(", 1), false},
		{"unknown payload", boundedMatchSource + strings.Replace(strings.Replace(boundedMatchProbe, "fn probe()", "fn probe(value: Int)", 1), "Shape.Circle(2)", "Shape.Circle(value)", 1), false},
		{"default capture", boundedMatchSource + strings.Replace(boundedMatchProbe, "    var sum", "    let read = fn(value: Shape = shapes.get(0)) Shape: value\n    var sum", 1), false},
		{"callee default", strings.Replace(boundedMatchSource, "s: Shape)", "s: Shape = Shape.Tri(1))", 1) + boundedMatchProbe, false},
		{"callee call", strings.Replace(boundedMatchSource, "out = r * 3", "out = identity(r)", 1) + "fn identity(n: Int) Int: return n\n" + boundedMatchProbe, false},
		{"arithmetic tree", strings.Replace(boundedMatchSource, "out = r * 3", "out = (r * 3) + 1", 1) + boundedMatchProbe, false},
		{"callee generic", strings.Replace(boundedMatchSource, "fn area(", "fn area[T](", 1) + strings.ReplaceAll(boundedMatchProbe, "area(", "area[Int]("), false},
		{"generic caller", boundedMatchSource + strings.Replace(boundedMatchProbe, "fn probe()", "fn probe[T]()", 1), false},
		{"empty list", boundedMatchSource + strings.Replace(boundedMatchProbe, "let shapes = [Shape.Circle(2), Shape.Square(3), Shape.Tri(4)]", "let shapes: List[Shape] = []", 1), false},
		{"unknown general calls coexist", boundedMatchSource + boundedMatchProbe + "fn unknown(s: Shape) Int: return area(s)\n", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
				r := compiler.CompileSource("bounded-match.ms", tc.source, compiler.Options{BuildType: kind})
				if !r.Success() {
					t.Fatal(r.Diagnostics)
				}
				got, want := strings.Contains(r.Source, "func area_bounded("), tc.clone && kind == compiler.Release
				if got != want {
					t.Fatalf("clone=%v want%v\n%s", got, want, r.Source)
				}
				if !strings.Contains(r.Source, "func area") || !strings.Contains(r.Source, "rt.IntMultiply(") {
					t.Fatal("general checked function disappeared")
				}
				if want {
					if !strings.Contains(r.Source, "rt.RegisterSource(area_bounded, \"area\")") || strings.Contains(r.Source, "sum = rt.IntAdd(") {
						t.Fatalf("missing registration or caller bounds\n%s", r.Source)
					}
				}
			}
		})
	}
}

func TestBoundedMatchUnionAndCaseLimits(t *testing.T) {
	overflow := boundedMatchSource + boundedMatchProbe + `fn other() Int:
    let shapes = [Shape.Square(9223372036854775807)]
    return area(shapes.get(0))
`
	for _, source := range []string{overflow} {
		r := compiler.CompileSource("union.ms", source, compiler.Options{})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		if strings.Contains(r.Source, "func area_bounded(") {
			t.Fatal("unsafe union/default selected")
		}
	}
	for _, n := range []int{8, 9} {
		var s strings.Builder
		s.WriteString("type Shape:\n")
		for i := 0; i < n; i++ {
			fmt.Fprintf(&s, "    case C%d(value: Int)\n", i)
		}
		s.WriteString("fn area(s: Shape) Int:\n    var out = 0\n    match s:\n")
		for i := 0; i < n; i++ {
			fmt.Fprintf(&s, "        C%d(value):\n            out = value * 2\n", i)
		}
		s.WriteString("    return out\nfn probe() Int:\n    let shapes = [Shape.C0(1)]\n    return area(shapes.get(0))\n")
		r := compiler.CompileSource("cases.ms", s.String(), compiler.Options{})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		if strings.Contains(r.Source, "func area_bounded(") != (n == 8) {
			t.Fatal("case cap changed")
		}
	}
}

func TestBoundedMatchDeterministic(t *testing.T) {
	const count = 8
	var wg sync.WaitGroup
	outputs := make([]string, count)
	for i := range outputs {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			r := compiler.CompileSource("deterministic.ms", boundedMatchSource+boundedMatchProbe, compiler.Options{})
			if !r.Success() {
				t.Error(r.Diagnostics)
				return
			}
			outputs[i] = r.Source
		}(i)
	}
	wg.Wait()
	for _, output := range outputs {
		if output != outputs[0] {
			t.Fatal("nondeterministic bounded lowering")
		}
	}
}

func TestBoundedMatchRejectsLocalEvidence(t *testing.T) {
	root := t.TempDir()
	split := strings.Index(boundedMatchSource, "fn area(")
	domain := "export interface Tag:\n    fn tag() Int\n" + strings.Replace(boundedMatchSource[:split], "type Shape:", "export type Shape:", 1)
	write(t, root, "domain.ms", domain)
	write(t, root, "main.ms", "import {Shape, Tag} from \"./domain.ms\"\nimpl Tag for Shape:\n    fn tag() Int: return 0\n"+boundedMatchSource[split:]+boundedMatchProbe)
	r := compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Contains(r.Source, "func area_bounded(") {
		t.Fatal("local evidence selected bounded match")
	}
}

func TestBoundedMatchIndexProof(t *testing.T) {
	for _, tc := range []struct {
		index  string
		direct bool
	}{
		{"i % 3", true}, {"i % 2", true}, {"0", true}, {"2", true},
		{"i % 4", false}, {"i % -3", false}, {"i % 0", false}, {"-1", false}, {"3", false}, {"i", false}, {"i % 3 + 1", false},
	} {
		t.Run(tc.index, func(t *testing.T) {
			source := boundedMatchSource + strings.Replace(boundedMatchProbe, "i % 3", tc.index, 1)
			for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
				r := compiler.CompileSource("index.ms", source, compiler.Options{BuildType: kind})
				if !r.Success() {
					t.Fatal(r.Diagnostics)
				}
				if got, want := strings.Contains(r.Source, "shapes.Items["), tc.direct && kind == compiler.Release; got != want {
					t.Fatalf("direct=%v want%v\n%s", got, want, r.Source)
				}
			}
		})
	}
	source := boundedMatchSource + strings.Replace(boundedMatchProbe, "var i = 0", "var i = -10", 1)
	r := compiler.CompileSource("negative.ms", source, compiler.Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Contains(r.Source, "shapes.Items[") {
		t.Fatal("negative remainder lost normalization")
	}
	// A descriptor with no payload arithmetic does not need another function.
	source = strings.Replace(strings.Replace(boundedMatchSource, "r * 3", "r", 1), "side * side", "side", 1) + boundedMatchProbe
	r = compiler.CompileSource("identity.ms", source, compiler.Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Contains(r.Source, "func area_bounded(") {
		t.Fatal("cloned a helper without payload arithmetic")
	}
}
