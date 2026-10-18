package e2e_test

import (
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"path/filepath"
	"strings"
	"testing"
)

const nativeBoundedMatch = `type Shape:
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

func TestBoundedMatchNative(t *testing.T) {
	for _, tc := range []struct {
		name, tail, message string
		frames              []string
	}{
		{"values and once-only index", `import Closeable from "@std/cleanup.ms"
type Count:
    total: Int
type Watch:
    count: Count
impl Closeable for Watch:
    fn close() Unit:
        self.count.total += 10
fn next(count: Count) Int:
    with watch = Watch(count):
        count.total += 1
        return 0
fn unknown(s: Shape) Int: return area(s)
export fn main() Int:
    let shapes = [Shape.Circle(2), Shape.Square(3), Shape.Tri(4)]
    let count = Count(0)
    if area(shapes.get(next(count) * 0)) != 6: return 1
    if count.total != 11: return 2
    if area(shapes.get(next(count))) != 6: return 5
    if count.total != 22: return 6
    if unknown(Shape.Tri(4)) != 4: return 3
    var sum = 0
    var i = 0
    while i < 321:
        sum += area(shapes.get(i % 3))
        i += 1
    if sum != 2033: return 4
    return 0
`, "", nil},
		{"missing get", `fn probe() Int:
    let shapes = [Shape.Circle(2)]
    return area(shapes.get(2))
export fn main() Int:
    return probe()
`, "index 2 out of range for length 1", []string{"bounded-native.ms:17 in probe", "bounded-native.ms:19 in main"}},
		{"general overflow", `fn unknown(s: Shape) Int: return area(s)
export fn main() Int:
    let shapes = [Shape.Circle(2)]
    let good = area(shapes.get(0))
    return unknown(Shape.Square(9223372036854775807))
`, "Int overflow", []string{"bounded-native.ms:11 in area", "bounded-native.ms:15 in unknown", "bounded-native.ms:19 in main"}},
		{"index effect faults", `fn fail() Int:
    return 1 / 0
export fn main() Int:
    let shapes = [Shape.Circle(2)]
    return area(shapes.get(fail() * 0))
`, "division by zero", []string{"bounded-native.ms:16 in fail", "bounded-native.ms:19 in main"}},
		{"caller prefix overflow", `export fn main() Int:
    let shapes = [Shape.Circle(2)]
    var sum = 9223372036854775807
    var i = 0
    while i < 2:
        sum += area(shapes.get(0))
        i += 1
    return sum
`, "Int overflow", []string{"bounded-native.ms:20 in main"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
				r := compiler.CompileSource("bounded-native.ms", nativeBoundedMatch+tc.tail, compiler.Options{Entry: true, BuildType: kind})
				if !r.Success() {
					t.Fatal(r.Diagnostics)
				}
				if strings.Contains(r.Source, "func area_bounded(") != (kind == compiler.Release) {
					t.Fatal("unexpected clone selection")
				}
				if kind == compiler.Release {
					if tc.name == "values and once-only index" && (!strings.Contains(r.Source, "shapes.Items[next(") || !strings.Contains(r.Source, "rt.List_Get[Shape](ctx, shapes, next(")) {
						t.Fatalf("selected and fallback effectful gets were not both exercised:\n%s", r.Source)
					}
					if tc.name == "index effect faults" && !strings.Contains(r.Source, "shapes.Items[fail(") {
						t.Fatal("faulting index did not select direct indexing")
					}
				}

				for _, standalone := range []bool{false, true} {
					native := r.Source
					if standalone {
						var err error
						native, err = build.Standalone(native)
						if err != nil {
							t.Fatal(err)
						}
					}
					binary := filepath.Join(t.TempDir(), "bounded-native")
					if err := build.Build(native, binary); err != nil {
						t.Fatal(err)
					}
					output, err := commandOutput(t, binary)
					if tc.message == "" {
						if err != nil {
							t.Fatalf("%v\n%s", err, output)
						}
						continue
					}
					if err == nil || !strings.Contains(string(output), tc.message) {
						t.Fatalf("want fault %q: %v\n%s", tc.message, err, output)
					}
					var frames []string
					for _, line := range strings.Split(string(output), "\n") {
						if frame, ok := strings.CutPrefix(line, "  at "); ok {
							frames = append(frames, frame)
						}
					}
					if strings.Join(frames, "\n") != strings.Join(tc.frames, "\n") {
						t.Fatalf("frames=%q want%q\n%s", frames, tc.frames, output)
					}
				}
			}
		})
	}
}

func TestBoundedMatchSignedAndEndpointNative(t *testing.T) {
	for _, tc := range []struct {
		name, area, tail string
		clone, fault     bool
	}{
		{"subtraction directions", strings.Replace(strings.Replace(nativeBoundedMatch, "out = r * 3", "out = r - 7", 1), "out = side * side", "out = 10 - side", 1), `export fn main() Int:
    let shapes = [Shape.Circle(-3), Shape.Square(4), Shape.Tri(-1)]
    if area(shapes.get(0)) != -10: return 1
    if area(shapes.get(1)) != 6: return 2
    if area(shapes.get(2)) != -1: return 3
    if area(shapes.get(-1)) != -1: return 4
    return 0
`, true, false},
		{"addition and negative multiplication", strings.Replace(strings.Replace(nativeBoundedMatch, "out = r * 3", "out = r + 7", 1), "out = side * side", "out = side * -2", 1), `export fn main() Int:
    let shapes = [Shape.Circle(-3), Shape.Square(4), Shape.Tri(-1)]
    if area(shapes.get(0)) != 4: return 1
    if area(shapes.get(1)) != -8: return 2
    return 0
`, true, false},
		{"endpoint union", nativeBoundedMatch, `export fn main() Int:
    let shapes = [Shape.Square(3037000499), Shape.Square(-3037000499), Shape.Circle(-3037000499)]
    if area(shapes.get(0)) != 9223372030926249001: return 1
    if area(shapes.get(1)) != 9223372030926249001: return 2
    if area(shapes.get(2)) != -9111001497: return 3
    return 0
`, true, false},
		{"supplied default", nativeBoundedMatch, `export fn main() Int:
    let shapes = [Shape.Circle(2)]
    if area(shapes.get(2, Shape.Tri(7))) != 7: return 1
    return 0
`, false, false},
		{"next square overflows", nativeBoundedMatch, `export fn main() Int:
    let shapes = [Shape.Square(3037000500)]
    return area(shapes.get(0))
`, false, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
				r := compiler.CompileSource("signed-bound.ms", tc.area+tc.tail, compiler.Options{Entry: true, BuildType: kind})
				if !r.Success() {
					t.Fatal(r.Diagnostics)
				}
				if strings.Contains(r.Source, "func area_bounded(") != (tc.clone && kind == compiler.Release) {
					t.Fatal("unexpected signed clone selection")
				}
				for _, standalone := range []bool{false, true} {
					native := r.Source
					if standalone {
						var err error
						native, err = build.Standalone(native)
						if err != nil {
							t.Fatal(err)
						}
					}
					binary := filepath.Join(t.TempDir(), "signed-bound")
					if err := build.Build(native, binary); err != nil {
						t.Fatal(err)
					}
					output, err := commandOutput(t, binary)
					if tc.fault {
						if err == nil || !strings.Contains(string(output), "Int overflow") {
							t.Fatalf("expected checked endpoint overflow: %v\n%s", err, output)
						}
					} else if err != nil {
						t.Fatalf("%v\n%s", err, output)
					}
				}
			}
		})
	}
}
