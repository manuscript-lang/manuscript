package lower

import (
	"strings"
	"testing"
)

func TestCoreAccessorsUseTypedReceiverOnlyHelpers(t *testing.T) {
	r := compileSource("accessors.ms", `import Bytes from "@std/bytes.ms"
fn inspect(list: List[Int], map: Map[Int, Int], set: Set[Int], bytes: Bytes, text: String, option: Optional[Int], result: Result[Int, String], number: Float) -> Unit:
    let a = list.length
    let b = list.is_empty
    let c = list.first
    let d = list.last
    let e = map.length
    let f = map.is_empty
    let g = set.length
    let h = set.is_empty
    let i = bytes.length
    let j = bytes.is_empty
    let k = text.byte_length
    let l = text.length
    let m = text.scalar_length
    let n = text.is_empty
    let o = option.is_some
    let p = option.is_none
    let q = result.is_ok
    let r = result.is_error
    let s = number.is_nan
    let t = number.is_finite
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, helper := range []string{"ListLength", "ListIsEmpty", "ListFirst", "ListLast", "MapLength", "MapIsEmpty", "SetLength", "SetIsEmpty", "BytesLength", "BytesIsEmpty", "StringByteLength", "StringLength", "StringScalarLength", "StringIsEmpty", "OptionalSome", "OptionalNone", "ResultOK", "ResultError", "FloatNaN", "FloatFinite"} {
		if !strings.Contains(r.Source, "rt."+helper+"Read(ctx, ") {
			t.Errorf("missing receiver-only helper %s\n%s", helper, r.Source)
		}
	}
	for _, forbidden := range []string{"rt.NativeMemberResult(", "rt.Invoke(", "rt.Bind(", "rt.CallNative(", "rt.BindNativeCall(", "rt.NewFunction(", "rt.ReadAccessor("} {
		if strings.Contains(r.Source, forbidden) {
			t.Errorf("accessor manufactured callable/dispatch %s\n%s", forbidden, r.Source)
		}
	}
	for _, name := range []string{"a", "e", "g", "i", "k", "l", "m"} {
		if !strings.Contains(localNumbers.ReplaceAllString(r.Source, "local_"), "var local_"+name+" int64 = rt.") {
			t.Errorf("Int accessor result %s did not stay typed\n%s", name, r.Source)
		}
	}
}

func TestPresenceAccessorsPreserveTypedAlternativeLocals(t *testing.T) {
	r := compileSource("flags.ms", `fn option(n: Int) -> Optional[Int]: some(n)
fn result(n: Int) -> Result[Int, String]: ok(n)
fn flags(n: Int) -> Bool:
    let optional = option(n)
    let outcome = result(n)
    return optional.is_some and not optional.is_none and outcome.is_ok and not outcome.is_error
fn immediate(n: Int) -> Bool: option(n).is_some and result(n).is_ok
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	source := localNumbers.ReplaceAllString(r.Source, "local_")
	for _, want := range []string{"local_optional rt.Option[int64]", "local_outcome rt.Result[int64]", "rt.OptionalSomeRead(ctx, rt.Seq(local_optional.Some))", "rt.ResultOKRead(ctx, rt.Seq(local_outcome.Failed))"} {
		if !strings.Contains(source, want) {
			t.Errorf("missing typed tag read %s\n%s", want, source)
		}
	}
	if strings.Contains(source, `local_optional.Box(`) || strings.Contains(source, `local_outcome.Box(`) {
		t.Fatal("presence-only locals were boxed", source)
	}
}

func TestSourceAccessorsUseDirectFunctionsAndDynamicEvidence(t *testing.T) {
	r := compileSource("source-accessors.ms", `interface Size:
    get length -> Int
type Buffer:
    items: List[Int]
impl Size for Buffer:
    get length -> Int: self.items.length
fn concrete(value: Buffer) -> Int: value.length
fn dynamic(value: Size) -> Int: value.length
fn generic[T: Size](value: T) -> Int: value.length
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, want := range []string{"func method_", "return method_", "Accessor: true", "Read: func(", "rt.ReadAccessor(ctx,"} {
		if !strings.Contains(r.Source, want) {
			t.Errorf("missing accessor lowering %s\n%s", want, r.Source)
		}
	}
	for _, forbidden := range []string{"rt.Bind(", "rt.BoundDirect(", "rt.CallMethod("} {
		if strings.Contains(r.Source, forbidden) {
			t.Errorf("source accessor bound callable %s\n%s", forbidden, r.Source)
		}
	}
}

func TestAccessorReadPreventsTryHoisting(t *testing.T) {
	r := compileSource("order-accessors.ms", `interface Read:
    get value -> Int
type Box:
    reads: Int
impl Read for Box:
    get value -> Int:
        self.reads = self.reads + 1
        return self.reads
fn fail() -> Result[Int, String]: error("failed")
fn consume(first: Int, second: Int) -> Int: first + second
fn read(box: Box) -> Result[Int, String]: ok(consume(box.value, try fail()))
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if !strings.Contains(r.Source, "rt.Try(") {
		t.Fatal("try crossed an executing accessor", r.Source)
	}
}

func TestAccessorCyclesKeepSampledDepthChecks(t *testing.T) {
	r := compileSource("recursive-accessors.ms", `interface Read:
    get value -> Int
type Box:
    count: Int
impl Read for Box:
    get value -> Int: self.value
fn read(box: Box) -> Int: box.value
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if !strings.Contains(r.Source, "rt.Enter(ctx)") || !strings.Contains(r.Source, "rt.Exit(ctx)") || !strings.Contains(r.Source, "directResult = method_") {
		t.Fatal("recursive accessor lost direct cycle/depth accounting", r.Source)
	}
}

func TestGuardScalarAccessorValidatesOnceThenUnboxes(t *testing.T) {
	r := compileSource("guard-accessor.ms", `import SynchronizedGuard from "@std/sync.ms"
fn int(guard: SynchronizedGuard[Int]) -> Int: guard.value
fn bool(guard: SynchronizedGuard[Bool]) -> Bool: guard.value
fn float(guard: SynchronizedGuard[Float]) -> Float: guard.value
fn string(guard: SynchronizedGuard[String]) -> String: guard.value
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, unbox := range []string{"IntValue", "Bool", "FloatValue", "StringValue"} {
		if !strings.Contains(r.Source, "rt."+unbox+"(rt.SynchronizedGuardValueRead(ctx, ") {
			t.Errorf("missing post-validation scalar extraction %s\n%s", unbox, r.Source)
		}
	}
	if strings.Count(r.Source, "rt.SynchronizedGuardValueRead(ctx, ") != 4 {
		t.Fatal("scalar extraction reread guard", r.Source)
	}
}
