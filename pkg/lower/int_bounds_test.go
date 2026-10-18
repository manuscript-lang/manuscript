package lower

import (
	"fmt"
	"math"
	"math/big"
	"math/rand"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestAddIntBoundsAgainstBigInt(t *testing.T) {
	values := []int64{math.MinInt64, math.MinInt64 + 1, -1, 0, 1, math.MaxInt64 - 1, math.MaxInt64}
	rng := rand.New(rand.NewSource(47))
	for range 100 {
		values = append(values, int64(rng.Uint64()))
	}
	for i, low := range values {
		a := intBounds{min(low, values[(i+1)%len(values)]), max(low, values[(i+1)%len(values)])}
		for _, value := range values {
			b := intBounds{min(value, int64(0)), max(value, int64(0))}
			for _, sub := range []bool{false, true} {
				got, valid := addIntBounds(a, b, sub)
				// Independently enumerate all endpoint combinations with exact integers.
				var lo, hi *big.Int
				for _, x := range []int64{a.lo, a.hi} {
					for _, y := range []int64{b.lo, b.hi} {
						n := new(big.Int)
						if sub {
							n.Sub(big.NewInt(x), big.NewInt(y))
						} else {
							n.Add(big.NewInt(x), big.NewInt(y))
						}
						if lo == nil || n.Cmp(lo) < 0 {
							lo = new(big.Int).Set(n)
						}
						if hi == nil || n.Cmp(hi) > 0 {
							hi = new(big.Int).Set(n)
						}
					}
				}
				want := lo.IsInt64() && hi.IsInt64()
				if valid != want || valid && got != (intBounds{lo.Int64(), hi.Int64()}) {
					t.Fatalf("%v sub=%v %v: %v/%v vs [%s,%s]/%v", a, sub, b, got, valid, lo, hi, want)
				}
			}
		}
	}
}

// Isolate the new pass from parsing, checking, code generation and printing.
func BenchmarkIntProofScaling(b *testing.B) {
	for _, n := range []int{128, 256, 512} {
		var source strings.Builder
		source.WriteString("fn probe() Int:\n    var sum = 0\n")
		for i := 0; i < n; i++ {
			fmt.Fprintf(&source, "    var i%d = 0\n    while i%d < 100:\n        sum += i%d\n        i%d += 1\n", i, i, i, i)
		}
		source.WriteString("    return sum\n")
		program := checkedLoweringProgram(b, source.String())
		var body []*syntax.Statement
		for _, module := range program.Modules {
			for _, decl := range module.Declarations {
				if decl.Name == "probe" {
					body = decl.Body
				}
			}
		}
		if body == nil {
			b.Fatal("missing probe body")
		}
		g := newGen(program)
		b.Run(fmt.Sprint(n), func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				g.fn = &funcState{}
				g.proveIntArithmetic(body)
			}
		})
	}
}

func TestMultiplyIntBoundsAgainstInteriorOracle(t *testing.T) {
	for alo := int64(-4); alo <= 4; alo++ {
		for ahi := alo; ahi <= 4; ahi++ {
			for blo := int64(-4); blo <= 4; blo++ {
				for bhi := blo; bhi <= 4; bhi++ {
					lo, hi := int64(100), int64(-100)
					// Enumerate every interior point, independent of endpoint logic.
					for x := alo; x <= ahi; x++ {
						for y := blo; y <= bhi; y++ {
							lo = min(lo, x*y)
							hi = max(hi, x*y)
						}
					}
					got, ok := multiplyIntBounds(intBounds{alo, ahi}, intBounds{blo, bhi})
					if !ok || got != (intBounds{lo, hi}) {
						t.Fatalf("[%d,%d]*[%d,%d]: %v/%v want [%d,%d]", alo, ahi, blo, bhi, got, ok, lo, hi)
					}
				}
			}
		}
	}
	values := []int64{math.MinInt64, math.MinInt64 + 1, -3037000500, -3037000499, -1, 0, 1, 3037000499, 3037000500, math.MaxInt64 - 1, math.MaxInt64}
	rng := rand.New(rand.NewSource(53))
	for range 100 {
		values = append(values, int64(rng.Uint64()))
	}
	for _, x := range values {
		for _, y := range values {
			exact := new(big.Int).Mul(big.NewInt(x), big.NewInt(y))
			got, ok := multiplyIntBounds(intBounds{x, x}, intBounds{y, y})
			if ok != exact.IsInt64() || ok && (got.lo != exact.Int64() || got.hi != exact.Int64()) {
				t.Fatalf("%d*%d: %v/%v vs %s", x, y, got, ok, exact)
			}
		}
	}
	if _, ok := multiplyIntBounds(intBounds{math.MinInt64, math.MaxInt64}, intBounds{-1, 1}); ok {
		t.Fatal("proved MinInt*-1")
	}
}

func BenchmarkClosedCellProofScaling(b *testing.B) {
	for _, n := range []int{128, 256, 512} {
		var source strings.Builder
		source.WriteString("interface Counter:\n    fn bump(by: Int) Int\ntype Cell:\n    total: Int\nimpl Counter for Cell:\n    fn bump(by: Int) Int:\n        self.total += by\n        return self.total\nfn probe() Int:\n    var sum = 0\n")
		for i := 0; i < n; i++ {
			fmt.Fprintf(&source, "    let list%d = [1, 2, 3]\n    let cell%d = Cell(0)\n    var i%d = 0\n    while i%d < 1000:\n        cell%d.bump(1)\n        sum += list%d.length()\n        i%d += 1\n", i, i, i, i, i, i, i)
		}
		source.WriteString("    return sum\n")
		program := checkedLoweringProgram(b, source.String())
		var declaration *syntax.Declaration
		for _, module := range program.Modules {
			for _, d := range module.Declarations {
				if d.Name == "probe" {
					declaration = d
				}
			}
		}
		if declaration == nil {
			b.Fatal("missing probe")
		}
		g := newGen(program)
		b.Run(fmt.Sprint(n), func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				g.fn = &funcState{}
				g.fn.localCollections = g.proveLocalCollections(declaration.Params, declaration.Body)
				g.proveIntArithmetic(declaration.Body)
			}
		})
	}
}

// Keep evidence lookup independent of the number of fresh map constructors.
// Both the number of unrelated methods and the number of candidates grow here.
func BenchmarkClosedMapProofScaling(b *testing.B) {
	for _, n := range []int{128, 256, 512} {
		var source strings.Builder
		source.WriteString("interface Tag:\n    fn tag() Int\n")
		for i := 0; i < n; i++ {
			fmt.Fprintf(&source, "type Key%d:\n    value: Int\nimpl Tag for Key%d:\n    fn tag() Int: self.value\n", i, i)
		}
		source.WriteString("fn probe() Int:\n")
		for i := 0; i < n; i++ {
			fmt.Fprintf(&source, "    let map%d = Map[Int, Int]()\n    map%d.add(1, 2)\n", i, i)
		}
		source.WriteString("    return 0\n")
		program := checkedLoweringProgram(b, source.String())
		var declaration *syntax.Declaration
		for _, module := range program.Modules {
			for _, d := range module.Declarations {
				if d.Name == "probe" {
					declaration = d
				}
			}
		}
		if declaration == nil {
			b.Fatal("missing probe")
		}
		g := newGen(program)
		b.Run(fmt.Sprint(n), func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				g.fn = &funcState{}
				inventory := g.proveLocalCollections(declaration.Params, declaration.Body)
				if len(inventory.constructors) != n {
					b.Fatalf("selected %d maps, want %d", len(inventory.constructors), n)
				}
			}
		})
	}
}

func BenchmarkSuccessfulResultScaling(b *testing.B) {
	for _, n := range []int{128, 256, 512} {
		var source strings.Builder
		source.WriteString("import TextError from \"@std/errors.ms\"\n")
		for i := 0; i < n; i++ {
			fmt.Fprintf(&source, "fn affine%d(value: Int) Result[Int, TextError]:\n    if value < 0: return error(TextError(\"negative\"))\n    return ok(value + 1)\n", i)
		}
		source.WriteString("fn probe() Int:\n    var sum = 0\n")
		for i := 0; i < n; i++ {
			fmt.Fprintf(&source, "    var i%d = 0\n    while i%d < 1000:\n        if let found = affine%d(i%d):\n            sum += found\n        else:\n            sum -= 1\n        i%d += 1\n", i, i, i, i, i)
		}
		source.WriteString("    return sum\n")
		program := checkedLoweringProgram(b, source.String())
		g := newGen(program)
		var body []*syntax.Statement
		for _, module := range program.Modules {
			for _, d := range module.Declarations {
				if d.Name == "probe" {
					body = d.Body
				}
			}
		}
		if body == nil || len(g.resultBounds) != n {
			b.Fatalf("missing probe or summaries: %d", len(g.resultBounds))
		}
		b.Run(fmt.Sprint(n)+"/summaries", func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				if len(g.resultIntSummaries()) != n {
					b.Fatal("missing summary")
				}
			}
		})
		b.Run(fmt.Sprint(n)+"/proof", func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				g.fn = &funcState{}
				g.proveIntArithmetic(body)
			}
		})
	}
}

func BenchmarkCounterAggregateScaling(b *testing.B) {
	for _, n := range []int{128, 256, 512} {
		var source strings.Builder
		source.WriteString("fn probe() Int:\n    var sum = 0\n    let unrelated = 7\n")
		for i := 0; i < n; i++ {
			fmt.Fprintf(&source, "    let captured%d = fn() Int: unrelated\n    sum = 0\n    var i%d = 0\n    while i%d < 321:\n        sum += i%d\n        i%d += 1\n", i, i, i, i, i)
		}
		source.WriteString("    return sum\n")
		program := checkedLoweringProgram(b, source.String())
		g := newGen(program)
		var declaration *syntax.Declaration
		for _, module := range program.Modules {
			for _, d := range module.Declarations {
				if d.Name == "probe" {
					declaration = d
				}
			}
		}
		if declaration == nil {
			b.Fatal("missing probe")
		}
		g.fn = &funcState{}
		g.proveIntArithmetic(declaration.Body)
		selected := 0
		for _, chunk := range g.fn.counterChunks {
			if chunk.aggregate != nil {
				selected++
			}
		}
		if selected != n {
			b.Fatalf("selected %d aggregates, want %d", selected, n)
		}
		b.Run(fmt.Sprint(n)+"/captures", func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				g.captureInventory()
			}
		})
		b.Run(fmt.Sprint(n)+"/proof", func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				g.fn = &funcState{}
				g.proveIntArithmetic(declaration.Body)
			}
		})
	}
}

func BenchmarkBuilderRangeScaling(b *testing.B) {
	for _, size := range []int{1, maxBuilderFragmentBytes} {
		for _, n := range []int{128, 256, 512} {
			var source strings.Builder
			source.WriteString("import StringBuilder from \"@std/string.ms\"\nfn probe() Int:\n    let values = [" + strings.TrimSuffix(strings.Repeat("1,", 256), ",") + "]\n    var sum = 0\n")
			for i := 0; i < n; i++ {
				fmt.Fprintf(&source, "    let b%d = StringBuilder()\n    var i%d = 0\n    while i%d < 321:\n        b%d.append(%q)\n        i%d += 1\n    b%d.freeze()\n    for x%d in values:\n        sum += x%d\n", i, i, i, i, strings.Repeat("x", size), i, i, i, i)
			}
			source.WriteString("    return sum\n")
			program := checkedLoweringProgram(b, source.String())
			var d *syntax.Declaration
			for _, module := range program.Modules {
				for _, decl := range module.Declarations {
					if decl.Name == "probe" {
						d = decl
					}
				}
			}
			if d == nil {
				b.Fatal("missing probe")
			}
			g := newGen(program)
			g.fn = &funcState{}
			g.fn.localCollections = g.proveLocalCollections(d.Params, d.Body)
			g.proveIntArithmetic(d.Body)
			builders := 0
			for _, chunk := range g.fn.counterChunks {
				if chunk.aggregate != nil && chunk.aggregate.builder {
					builders++
				}
			}
			if builders != n || len(g.fn.rangeChunks) != n {
				b.Fatalf("selected %d builders/%d ranges, want%d", builders, len(g.fn.rangeChunks), n)
			}
			b.Run(fmt.Sprintf("%dbytes/%d/inventory", size, n), func(b *testing.B) {
				b.ReportAllocs()
				for range b.N {
					g.proveLocalCollections(d.Params, d.Body)
				}
			})
			b.Run(fmt.Sprintf("%dbytes/%d/emit", size, n), func(b *testing.B) {
				b.ReportAllocs()
				for range b.N {
					text, err := Go(program, "", Options{})
					if err != nil {
						b.Fatal(err)
					}
					b.SetBytes(int64(len(text)))
				}
			})
		}
	}
}

func BenchmarkBoundedMatchScaling(b *testing.B) {
	for _, n := range []int{128, 256, 512} {
		var source strings.Builder
		for i := 0; i < n; i++ {
			fmt.Fprintf(&source, "type Shape%d:\n", i)
			for j := 0; j < 8; j++ {
				fmt.Fprintf(&source, "    case C%d(value: Int)\n", j)
			}
			fmt.Fprintf(&source, "fn area%d(s: Shape%d) Int:\n    var out = 0\n    match s:\n", i, i)
			for j := 0; j < 8; j++ {
				fmt.Fprintf(&source, "        C%d(value):\n            out = value * 2\n", j)
			}
			fmt.Fprintf(&source, "    return out\nfn probe%d() Int:\n    let shapes = [Shape%d.C0(1)]\n    return area%d(shapes.get(0))\n", i, i, i)
		}
		program := checkedLoweringProgram(b, source.String())
		g := newGen(program)
		if len(g.matchBounds) != n {
			b.Fatalf("selected%d plans, want%d", len(g.matchBounds), n)
		}
		b.Run(fmt.Sprint(n)+"/plans", func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				if len(g.matchIntPlans()) != n {
					b.Fatal("lost planned calls")
				}
			}
		})
		b.Run(fmt.Sprint(n)+"/initialize", func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				next := newGen(program)
				if len(next.matchBounds) != n || len(next.matchGetLengths) != n {
					b.Fatal("lost published plans/gets")
				}
			}
		})
		b.Run(fmt.Sprint(n)+"/emit", func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				source, err := Go(program, "", Options{})
				if err != nil {
					b.Fatal(err)
				}
				if strings.Count(source, "_bounded(ctx") != 2*n || strings.Count(source, "shapes.Items[") != n {
					b.Fatal("lost bounded function/call")
				}
				b.SetBytes(int64(len(source)))
			}
		})
	}
}

func TestNonnegativeRemainderBoundsOracle(t *testing.T) {
	for _, divisor := range []int{0, -1, -3, 1, 2, 3, 7} {
		program := checkedLoweringProgram(t, fmt.Sprintf("fn probe(value: Int) Int: return value %% %d\n", divisor))
		var d *syntax.Declaration
		for _, module := range program.Modules {
			for _, decl := range module.Declarations {
				if decl.Name == "probe" {
					d = decl
				}
			}
		}
		g := newGen(program)
		g.fn = &funcState{}
		for lo := int64(-1); lo <= 12; lo++ {
			for hi := max(lo, int64(0)); hi <= 13; hi++ {
				p := &intProof{g: g, facts: map[*checker.Binding]intFact{}, epoch: 1, serial: 1, hazards: map[*syntax.Expression]bool{}, inspected: map[*syntax.Expression]bool{}, appendMemo: map[*syntax.Expression]bool{}}
				p.set(program.ParameterBindings(d)[0], intBounds{lo, hi})
				got := p.expression(d.Body[0].Value, false)
				if divisor <= 0 || lo < 0 {
					if got != unknownIntBounds {
						t.Fatalf("unexpected signed/zero divisor proof: %v", got)
					}
					continue
				}
				if got.lo < 0 || got.hi >= int64(divisor) {
					t.Fatalf("not a nonnegative remainder range: %v", got)
				}
				for x := lo; x <= hi; x++ {
					r := x % int64(divisor)
					if r < got.lo || r > got.hi {
						t.Fatalf("[%d,%d]%%%d: %d outside %v", lo, hi, divisor, r, got)
					}
				}
			}
		}
	}
}
