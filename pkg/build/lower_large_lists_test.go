package build

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func listOf(items []string) string { return "[" + strings.Join(items, ", ") + "]" }

func repeated(n int, item func(int) string) []string {
	items := make([]string, n)
	for i := range items {
		items[i] = item(i)
	}
	return items
}

// Large literals lower to typed tables or chunked closures in non-Debug
// builds. Their native behavior must match the small-literal contract: fresh
// storage per evaluation, source-order effects, and early exits.
func TestLargeListLiteralSemantics(t *testing.T) {
	const n = 300
	ints := repeated(n-2, func(i int) string {
		if i%2 == 1 {
			return fmt.Sprint(-i)
		}
		return fmt.Sprint(i)
	})
	ints = append(ints, "-9223372036854775808", "9223372036854775807")
	early := repeated(n, func(int) string { return "next(counter)" })
	early[150] = "match value:\n        some(v): v\n        none: return -counter.count\n    "
	source := `import panic from "@std/faults.ms"

type Counter:
    count: Int

fn ints() -> List[Int]: ` + listOf(ints) + `
fn floats() -> List[Float]: ` + listOf(repeated(n, func(i int) string { return fmt.Sprintf("%d.5", i) })) + `
fn flags() -> List[Bool]: ` + listOf(repeated(n, func(i int) string { return fmt.Sprint(i%3 == 0) })) + `
fn words() -> List[String]: ` + listOf(repeated(n, func(i int) string { return fmt.Sprintf("%q", fmt.Sprintf("w%d", i)) })) + `
fn defaults(items: List[Int] = ` + listOf(repeated(n, func(int) string { return "9" })) + `) -> List[Int]: items

fn next(counter: Counter) -> Int:
    counter.count = counter.count + 1
    return counter.count

fn step(counter: Counter, index: Int, bad: Int) -> Result[Int, String]:
    counter.count = counter.count + 1
    if index == bad: return error(cause: "bad")
    return ok(value: index)

fn ordered(counter: Counter) -> List[Int]: ` + listOf(repeated(n, func(int) string { return "next(counter)" })) + `

fn propagated(counter: Counter, bad: Int) -> Result[List[Int], String]:
    return ok(value: ` + listOf(repeated(n, func(i int) string { return fmt.Sprintf("try step(counter, %d, bad)", i) })) + `)

fn early(counter: Counter, value: Optional[Int]) -> Int:
    let items = ` + listOf(early) + `
    return items.length

test "large constant literals are fresh per evaluation":
    let first = ints()
    let second = ints()
    let alias = first
    first.set(index: 0, value: 99)
    alias.append(1)
    if second.at(0).unwrap() != 0 or ints().at(0).unwrap() != 0 or second.length != 300 or first.length != 301:
        return panic("constant table storage is shared")
    if second.at(1).unwrap() != -1 or second.at(298).unwrap() != -9223372036854775807 - 1 or second.at(299).unwrap() != 9223372036854775807:
        return panic("Int values changed")
    let f = floats()
    f.set(index: 2, value: 0.0)
    if floats().at(2).unwrap() != 2.5 or f.at(3).unwrap() != 3.5:
        return panic("Float table")
    let b = flags()
    b.set(index: 0, value: false)
    if not flags().at(0).unwrap() or flags().at(1).unwrap():
        return panic("Bool table")
    let w = words()
    w.set(index: 299, value: "changed")
    if words().at(299).unwrap() != "w299" or w.at(299).unwrap() != "changed":
        return panic("String table")
    let d = defaults()
    d.set(index: 0, value: 17)
    if defaults().at(0).unwrap() != 9:
        return panic("defaults share mutable storage")

test "large computed literals evaluate in order":
    let counter = Counter(count: 0)
    let items = ordered(counter)
    if counter.count != 300 or items.at(0).unwrap() != 1 or items.at(64).unwrap() != 65 or items.at(299).unwrap() != 300:
        return panic("order changed")

test "propagation stops a large literal":
    let counter = Counter(count: 0)
    let failed = propagated(counter, 200)
    if failed.is_ok or counter.count != 201:
        return panic("propagation did not stop evaluation")
    let whole = propagated(counter, -1)
    if not whole.is_ok or counter.count != 501:
        return panic("complete evaluation failed")

test "a return inside a large literal leaves the function":
    let counter = Counter(count: 0)
    if early(counter, none) != -150 or counter.count != 150:
        return panic("early return")
    if early(counter, some(5)) != 300 or counter.count != 449:
        return panic("complete literal")
`
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
		r := compiler.CompileSourceForBuild("large.ms", source, compiler.Options{Tests: true}, kind)
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		if kind == compiler.Release && (!strings.Contains(r.Source, "rt.ListTable[int64]") || !strings.Contains(r.Source, "*[64]rt.Value")) {
			t.Fatal("Release did not lower large literals to tables and chunks")
		}
		binary := filepath.Join(t.TempDir(), "program")
		if _, err := BuildCheckedWithType(r, binary, kind); err != nil {
			t.Fatal(err)
		}
		data, err := exec.Command(binary).CombinedOutput()
		if err != nil || !strings.Contains(string(data), "4 tests, 0 failed") {
			t.Fatalf("%s: %v\n%s", kind, err, data)
		}
	}
}

// A fault raised by an item past the first chunk reports the same source
// frames as the single-expression lowering Debug builds keep.
func TestLargeListLiteralFaultFrames(t *testing.T) {
	items := repeated(300, func(i int) string { return fmt.Sprintf("value(%d)", i) })
	items[200] = "fail()"
	source := "fn value(i: Int) -> Int: i\nfn fail() -> Int:\n    return 1 / 0\nexport fn main() -> Int:\n    let data = " + listOf(items) + "\n    return data.length\n"
	var transcripts []string
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
		r := compiler.CompileSourceForBuild("fault.ms", source, compiler.Options{Entry: true}, kind)
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		binary := filepath.Join(t.TempDir(), "program")
		if _, err := BuildCheckedWithType(r, binary, kind); err != nil {
			t.Fatal(err)
		}
		data, err := exec.Command(binary).CombinedOutput()
		if err == nil {
			t.Fatal("expected fault")
		}
		transcripts = append(transcripts, string(data))
	}
	if transcripts[0] != transcripts[1] || !strings.Contains(transcripts[0], "fault.ms:3 in fail") || !strings.Contains(transcripts[0], "fault.ms:5 in main") {
		t.Fatalf("fault frames changed: %q", transcripts)
	}
}
