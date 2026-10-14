package compiler_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestNumericLoweringAvoidsParsingAndDynamicDispatch(t *testing.T) {
	result := compiler.CompileSource("numeric.ms", `fn calculate(value: Int) -> Int:
    let minimum = -9223372036854775808
    let leading = 9
    if value < 5:
        return (value + leading) * 3 - minimum % 7
    return value / 2
fn fraction(value: Float) -> Float:
    if value >= 1e-3: return value * 2.5 + 1.0 / 0.0
    return value - 5e-324
`, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, forbidden := range []string{"rt.Integer(", "rt.Float(", "rt.Binary("} {
		if strings.Contains(result.Source, forbidden) {
			t.Fatalf("numeric hot path still contains %s", forbidden)
		}
	}
	for _, required := range []string{"int64(-9223372036854775808)", "int64(9)", "rt.IntAddAt(", "rt.IntSubtractAt(", "rt.IntMultiplyAt(", "rt.IntDivideAt(", "rt.IntRemainderAt(", "rt.FloatValue("} {
		if !strings.Contains(result.Source, required) {
			t.Fatalf("missing typed lowering %s", required)
		}
	}
}

func TestDirectNativeCollectionLowering(t *testing.T) {
	result := compiler.CompileSource("collections.ms", `import List from "@std/collections.ms"
fn read(values: List[Int], index: Int) -> Int:
    return values.at(index).unwrap()
fn stored(values: List[Int], index: Int) -> Optional[Int]:
    return values.at(index)
fn bound(values: List[Int]) -> Optional[Int]:
    let at = values.at
    return at(0)
type Custom:
    value: Int
interface At:
    fn at(index: Int) -> Int
impl At for Custom:
    fn at(index: Int) -> Int: return self.value + index
`, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, operation := range []string{"rt.ListAt(", "rt.ListAtUnwrap(", "rt.NativeMemberResult(", "rt.Invoke("} {
		if !strings.Contains(result.Source, operation) {
			t.Fatalf("missing expected dispatch %s", operation)
		}
	}
}

func TestDirectLengthLowering(t *testing.T) {
	result := compiler.CompileSource("length.ms", `import {List, Map, Set} from "@std/collections.ms"
type Sized:
    items: List[Int]
interface Measure:
    fn length() -> Int
impl Measure for Sized:
    fn length() -> Int: return self.items.length()
fn sizes(values: List[Int], pairs: Map[String, Int], names: Set[String], text: String, sized: Sized) -> Int:
    let measure = Measure(value: sized)
    let length = values.length
    return values.length() + pairs.length() + names.length() + text.byte_length() + measure.length() + length()
`, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if strings.Count(result.Source, "rt.CollectionLength(") != 4 || strings.Count(result.Source, "rt.StringByteLength(") != 1 {
		t.Fatalf("expected direct length calls only for built-in receivers:\n%s", result.Source)
	}
	if !strings.Contains(result.Source, "rt.NativeMemberResult(") {
		t.Fatal("bound method reference must keep ordinary callable dispatch")
	}
}

func TestStatementMatchLowersWithoutClosure(t *testing.T) {
	result := compiler.CompileSource("statement-match.ms", `fn pick(value: Optional[Int]) -> Int:
    match value:
        none: return 0
        some(inner): return inner
    return -1
fn total(values: Optional[Int]) -> Int:
    let doubled = match values:
        none: 0
        some(inner): inner * 2
    return doubled
`, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if strings.Count(result.Source, "rt.Return(") != 0 {
		t.Fatalf("statement match returns must be native Go returns:\n%s", result.Source)
	}
	if strings.Count(result.Source, "func() rt.Value {") < 1 {
		t.Fatal("a match used as a value keeps its closure")
	}
}

func TestStatementTryReturnsInline(t *testing.T) {
	result := compiler.CompileSource("try.ms", `fn parse(n: Int) -> Result[Int, String]:
    if n < 0:
        return error("neg")
    return ok(n)
fn bound(n: Int) -> Result[Int, String]:
    let v = try parse(n: n)
    return ok(v + 1)
fn nested(n: Int) -> Result[Int, String]:
    return ok((try parse(n: n)) + 1)
`, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if strings.Count(result.Source, "rt.Try(") != 1 {
		t.Fatalf("only the nested try keeps the panic form:\n%s", result.Source)
	}
}

func TestStaticSpecializationIsHoisted(t *testing.T) {
	result := compiler.CompileSource("hoist.ms", `fn ident[T](x: T) -> T:
    return x
fn twice[T](x: T) -> T:
    return ident(x: ident(x: x))
fn use() -> Int:
    return ident(x: 1) + ident(x: 2)
`, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if strings.Count(result.Source, "var specialized1 rt.Lazy") != 1 || strings.Contains(result.Source, "specialized2") {
		t.Fatalf("one hoisted specialization expected for the shared Int call sites:\n%s", result.Source)
	}
	if strings.Count(result.Source, "rt.Specialize(") != 4 {
		t.Fatalf("static Int sites share a Lazy; type-variable sites stay dynamic:\n%s", result.Source)
	}
}

func TestDirectListAppendAndIsEmptyLowering(t *testing.T) {
	result := compiler.CompileSource("append.ms", `import List from "@std/collections.ms"
fn grow(values: List[Int]) -> Bool:
    values.append(1)
    return values.is_empty()
`, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, operation := range []string{"rt.ListAppend(", "rt.ListIsEmpty("} {
		if !strings.Contains(result.Source, operation) {
			t.Fatalf("missing direct %s:\n%s", operation, result.Source)
		}
	}
}

func TestDirectKeyedAndStringLowering(t *testing.T) {
	result := compiler.CompileSource("keyed.ms", `import {List, Map, Set} from "@std/collections.ms"
fn use(l: List[Int], m: Map[String, Int], s: Set[Int], t: String) -> Unit:
    l.contains(1)
    m.contains("a")
    m.get("a")
    m.add("a", 1)
    m.add(value: 2, key: "b")
    s.contains(1)
    s.add(1)
    t.at(0)
`, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, operation := range []string{"rt.ListContains(", "rt.MapContains(", "rt.MapGet(", "rt.MapWithEntry(", "rt.SetContains(", "rt.SetWithValue(", "rt.StringAt("} {
		if !strings.Contains(result.Source, operation) {
			t.Fatalf("missing direct %s", operation)
		}
	}
	if strings.Count(result.Source, "rt.MapWithEntry(") != 1 || !strings.Contains(result.Source, `"add"`) {
		t.Fatalf("reordered labels must keep ordinary dispatch:\n%s", result.Source)
	}
}

func TestDirectMethodCallLowering(t *testing.T) {
	result := compiler.CompileSource("method.ms", `type Counter:
    n: Int
interface Bumper:
    fn bump(by: Int) -> Int
interface Scaler:
    fn scale(factor: Int, offset: Optional[Int] = none) -> Int
impl Bumper for Counter:
    fn bump(by: Int) -> Int: self.n + by
impl Scaler for Counter:
    fn scale(factor: Int, offset: Optional[Int] = none) -> Int: self.n * factor
fn direct(c: Counter) -> Int:
    return c.bump(by: 1)
fn view(b: Bumper) -> Int:
    return b.bump(by: 1)
fn omitted(c: Counter) -> Int:
    return c.scale(factor: 2)
fn reordered(c: Counter) -> Int:
    return c.scale(offset: some(1), factor: 2)
`, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if strings.Count(result.Source, "rt.CallMethod(") != 1 || strings.Count(result.Source, "var method1 rt.MethodSite") != 1 {
		t.Fatalf("only the in-order concrete call is direct:\n%s", result.Source)
	}
	if strings.Count(result.Source, "rt.Bind(") != 3 {
		t.Fatalf("views, omitted defaults, and reordered labels keep Bind:\n%s", result.Source)
	}
}
