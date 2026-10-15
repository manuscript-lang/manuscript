package lower

import (
	"regexp"
	"strings"
	"testing"
)

var localNumbers = regexp.MustCompile(`local\d+_`)

func TestScalarLocalsAndParametersAreTypedGoVariables(t *testing.T) {
	r := compileSource("typed.ms", `fn count(limit: Int, ratio: Float, label: String, on: Bool) -> Int:
    var i = 0
    var hits = 0
    while i < limit and on:
        if i % 3 == 0:
            hits = hits + 1
        i = i + 1
    let scaled = ratio * 2.0
    let same = label == "x"
    if scaled > 1.0 and same:
        return hits
    return 0
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	// Local numbering depends on how much was checked before this module.
	source := localNumbers.ReplaceAllString(r.Source, "local_")
	for _, want := range []string{
		"(ctx *rt.Execution, local_limit int64, local_ratio float64, local_label string, local_on bool) (directResult int64)",
		"var local_i int64 = int64(0)",
		"var local_scaled float64 =",
	} {
		if !strings.Contains(source, want) {
			t.Errorf("missing %q\n%s", want, source)
		}
	}
	// No loop variable is boxed: every use stays typed.
	for _, banned := range []string{"rt.IntValue(local_i)", "rt.IntValue(local_hits)", "var local_i rt.Value", "rt.Bool(local_on)"} {
		if strings.Contains(source, banned) {
			t.Errorf("boxed use %q\n%s", banned, source)
		}
	}
}

func TestConstantFloatArithmeticFollowsRuntimeRules(t *testing.T) {
	r := compileSource("const.ms", "fn f() -> Float: return 1.0 / 0.0\nfn g() -> Float: return 1.7976931348623157e308 * 2.0\n")
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Contains(r.Source, "float64(1) / float64(0)") || strings.Contains(r.Source, "float64(1.7976931348623157e+308) * float64(2)") {
		t.Fatalf("constant float expression left for the Go compiler\n%s", r.Source)
	}
}

func TestRecordsLowerToStructs(t *testing.T) {
	r := compileSource("records.ms", `type Point:
    x: Int
    label: String
fn bump(point: Point) -> Int:
    point.x = point.x + 1
    return point.x
fn make() -> Point: Point(x: 1, label: "a")
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	source := strings.Join(strings.Fields(r.Source), " ")
	for _, want := range []string{"f_x int64", "f_label string", "Get_x()", "Set_x(", "rt.RegisterStruct(", "&record_"} {
		if !strings.Contains(source, want) {
			t.Errorf("missing %q\n%s", want, r.Source)
		}
	}
	if strings.Contains(r.Source, `rt.Field(`) || strings.Contains(r.Source, `rt.SetField(`) {
		t.Errorf("record access fell back to the map-backed path\n%s", r.Source)
	}
}

func TestNegationOfScalarsStaysTyped(t *testing.T) {
	r := compileSource("negate.ms", `fn f(a: Int, b: Float) -> Int:
    var step = -1
    let c = -b
    if c < 0.0:
        step = -a
    return step
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	source := localNumbers.ReplaceAllString(r.Source, "local_")
	for _, want := range []string{"var local_step int64 = int64(-1)", "rt.IntNegateAt(local_a)", "var local_c float64 = -local_b"} {
		if !strings.Contains(source, want) {
			t.Errorf("missing %q\n%s", want, source)
		}
	}
	if strings.Contains(source, `rt.Unary("-"`) {
		t.Errorf("dynamic negation\n%s", source)
	}
}

func TestStaticNativeMembersBindOncePerCallSite(t *testing.T) {
	r := compileSource("native.ms", `import StringBuilder from "@std/string.ms"

fn f(xs: List[Int], text: String, seen: Set[Int]) -> String:
    xs.set(index: 0, value: 1)
    let doubled = seen.map(transform: fn(value: Int) -> Int: return value * 2)
    let sb = StringBuilder()
    sb.append(text.trim())
    return sb.freeze()

fn generic[T](xs: List[T], value: T) -> List[T]:
    return xs.set(index: 0, value: value)
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, want := range []string{`BindNativeCall("List", "set"`, `BindNativeCall("Set", "map"`, "StringBuilderAppend(", "StringBuilderFreeze(", "rt.StringTrim("} {
		if !strings.Contains(r.Source, want) {
			t.Errorf("missing %q", want)
		}
	}
	// The generic receiver's scope is known only at run time, so it keeps
	// ordinary dispatch.
	if !strings.Contains(r.Source, `NativeMemberResult(`) || strings.Count(r.Source, `BindNativeCall("List", "set"`) != 1 {
		t.Errorf("generic call must not bind statically\n%s", r.Source)
	}
}

func TestStandardFunctionsAreResolvedOncePerCallSite(t *testing.T) {
	r := compileSource("standard.ms", `import {stdout} from "@std/io.ms"

fn f() -> Int:
    let out = stdout()
    return 0
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	hoisted := regexp.MustCompile(`specialized\d+\.Get\(func\(\) rt\.Value \{\s*(?:/\*line [^*]*\*/)?\s*return rt.StandardFunction\("io/stdout"`)
	if !hoisted.MatchString(r.Source) {
		t.Errorf("standard function rebuilt per call\n%s", r.Source)
	}
}

func TestNestedTryReturnsInsteadOfPanicking(t *testing.T) {
	const prelude = `fn step(n: Int) -> Result[Int, String]:
    if n < 0:
        return error(cause: "bad")
    return ok(value: n)

fn id(x: Int) -> Int:
    return x

`
	for name, tc := range map[string]struct {
		body    string
		hoisted bool
	}{
		"operands":   {"    let v = (try step(n: a)) + (try step(n: a + 1))\n    return ok(value: v)\n", true},
		"argument":   {"    return ok(value: id(x: try step(n: a)))\n", true},
		"after call": {"    let w = id(x: a)\n    let v = w + try step(n: a)\n    return ok(value: v)\n", true},
		// id runs before the try in source order and would run after it.
		"effect first":  {"    return ok(value: id(x: a) + (try step(n: a)))\n", false},
		"short circuit": {"    let v = a > 0 and (try step(n: a)) > 0\n    return ok(value: a)\n", false},
	} {
		r := compileSource("try.ms", prelude+"fn run(a: Int) -> Result[Int, String]:\n"+tc.body)
		if !r.Success() {
			t.Fatalf("%s: %v", name, r.Diagnostics)
		}
		if panics := strings.Contains(r.Source, "rt.Try("); panics == tc.hoisted {
			t.Errorf("%s: rt.Try present=%v, want %v\n%s", name, panics, !tc.hoisted, r.Source)
		}
	}
}

// Appending to and ranging over a List of a primitive element type neither
// boxes the element nor asserts it back.
func TestPrimitiveListAppendAndRangeAreUnboxed(t *testing.T) {
	r := compileSource("list.ms", `fn sum(count: Int) -> Int:
    let items = List[Int]()
    var i = 0
    while i < count:
        items.append(value: i)
        i = i + 1
    var total = 0
    for v in items:
        total = total + v
    return total
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, want := range []string{"rt.ListAppendInt(", "rt.IterateInt("} {
		if !strings.Contains(r.Source, want) {
			t.Fatalf("missing %q\n%s", want, r.Source)
		}
	}
	if strings.Contains(r.Source, "rt.IntValue(local") {
		t.Fatalf("range element asserted\n%s", r.Source)
	}
}

// Interpolation joins typed parts as Go strings, String.length is a direct
// call, and a Map.get consumed by match reads the value and presence without
// building an Optional.
func TestTextLengthAndMapGetLowerWithoutBoxing(t *testing.T) {
	r := compileSource("strings.ms", `fn label(n: Int, f: Float, ok: Bool, s: String) -> Int:
    let text = "n={n} f={f} ok={ok} s={s}"
    return text.length()

fn lookup(m: Map[Int, Int], key: Int) -> Int:
    match m.get(key: key):
        some(v):
            return v
        none:
            return 0
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, want := range []string{"rt.FormatInt(", "rt.FormatFloat(", "rt.FormatBool(", "rt.StringLengthScalar(", "rt.MapGetParts("} {
		if !strings.Contains(r.Source, want) {
			t.Fatalf("missing %q\n%s", want, r.Source)
		}
	}
	if strings.Contains(r.Source, "rt.Text(") {
		t.Fatalf("interpolation still builds Values\n%s", r.Source)
	}
}

func TestLambdasBorrowCallbackArguments(t *testing.T) {
	r := compileSource("lambdas.ms", `fn double(value: Int) -> Int: value * 2

fn run(items: List[Int]) -> List[Int]:
    return items.map(fn(value: Int) -> Int: double(value: value))
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if !strings.Contains(r.Source, "rt.NewCompiledSourceFunction(") {
		t.Fatalf("lambda does not borrow arguments\n%s", r.Source)
	}
}

func TestOptionalMembersLowerWithoutDynamicDispatch(t *testing.T) {
	r := compileSource("optional.ms", `fn run(o: Optional[Int]) -> Int:
    if o.is_some():
        return o.unwrap_or(fallback: 0)
    return 1
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, want := range []string{"rt.OptionalIsSome(", "rt.OptionalUnwrapOr("} {
		if !strings.Contains(r.Source, want) {
			t.Fatalf("missing %q\n%s", want, r.Source)
		}
	}
	if strings.Contains(r.Source, `"is_some"`) {
		t.Fatalf("Optional member still dispatches by name\n%s", r.Source)
	}
}

func TestPureStandardCallsLowerToPlainRuntimeCalls(t *testing.T) {
	r := compileSource("scalar.ms", `import {sqrt} from "@std/math.ms"
fn run(x: Float, s: String) -> Bool:
    return sqrt(value: x) > 1.0 and s.contains(value: "a")
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, want := range []string{"rt.MathSqrt(", "rt.StringContains("} {
		if !strings.Contains(r.Source, want) {
			t.Fatalf("missing %q\n%s", want, r.Source)
		}
	}
	if strings.Contains(r.Source, "math/sqrt") {
		t.Fatalf("sqrt still resolves dynamically\n%s", r.Source)
	}
}

func TestOmittedDefaultsCallDirectFunctions(t *testing.T) {
	r := compileSource("defaults.ms", `fn scaled(base: Int, factor: Int = 2) -> Int: base * factor
fn run() -> Int: scaled(base: 3)
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if !strings.Contains(r.Source, "call_symbol") || strings.Contains(r.Source, "rt.Invoke(") {
		t.Fatalf("omitted default call still dispatches dynamically\n%s", r.Source)
	}
}

func TestDirectOnlyLambdasLowerToTypedFunctions(t *testing.T) {
	r := compileSource("closure.ms", `fn run(count: Int) -> Int:
    let add = fn(a: Int, b: Int) -> Int: a + b
    var total = 0
    var i = 0
    while i < count:
        total = add(a: total, b: i)
        i = i + 1
    return total

fn shared() -> List[Int]:
    let double = fn(value: Int) -> Int: value * 2
    return [1].map(double)
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Count(r.Source, "rt.NamedFunc(") != 1 {
		t.Fatalf("exactly the direct-only lambda should be typed\n%s", r.Source)
	}
}
