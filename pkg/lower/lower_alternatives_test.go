package lower

import (
	"strings"
	"testing"
)

// A direct function returning Result/Optional returns the typed form; try and
// match on a typed call consume it without boxing, and any other use boxes.
func TestTypedAlternativeABI(t *testing.T) {
	r := compileSource("alt.ms", `fn checked(n: Int) -> Result[Int, String]:
    if n < 0:
        return error(cause: "negative")
    return ok(value: n + 1)

fn chain(n: Int) -> Result[Int, String]:
    let v = try checked(n)
    return ok(value: v)

fn halve(n: Int) -> Optional[Int]:
    if n % 2 != 0:
        return none
    return some(value: n / 2)

fn use(n: Int) -> Int:
    match chain(n):
        ok(v):
            return v
        error(_):
            return 0

fn boxed(n: Int) -> String:
    return "{halve(n)}"
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, want := range []string{
		"(directResult rt.Result[int64])",
		"(directResult rt.Option[int64])",
		"rt.Result[int64]{Cause: ",
		".Failed {",
		".Tag() {",
	} {
		if !strings.Contains(r.Source, want) {
			t.Fatalf("missing %q\n%s", want, r.Source)
		}
	}
	// The formatted use of a typed Optional is boxed, never passed typed.
	if !strings.Contains(r.Source, ".Box(") {
		t.Fatalf("typed Optional reached a Value consumer unboxed\n%s", r.Source)
	}
	// try and match over typed calls do not assert Alternatives.
	for _, forbidden := range []string{".(rt.Alternative)", "rt.Tag(temporary"} {
		if strings.Contains(r.Source, forbidden) {
			t.Fatalf("unexpected %q\n%s", forbidden, r.Source)
		}
	}
}

// list.at(i).unwrap() reads the element directly instead of building an Optional.
func TestListAtUnwrapSkipsOptional(t *testing.T) {
	r := compileSource("at.ms", `import List from "@std/collections.ms"
fn pick(values: List[Int], index: Int) -> Int:
    return values.at(index).unwrap()

fn keep(values: List[Int], index: Int) -> Int:
    let found = values.at(index)
    return found.unwrap()
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if got := strings.Count(r.Source, "rt.ListAtUnwrap("); got != 1 {
		t.Fatalf("fused unwrap count = %d, want 1 (a stored Optional keeps ListAt)\n%s", got, r.Source)
	}
}
