package lower

import (
	"regexp"
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
	for _, forbidden := range []string{".(rt.Alternative)", "rt.Tag(temporary", ".Tag()"} {
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

// A let bound to a typed call stays typed only while every use is a match
// scrutinee in the declaring function; any other use or capture boxes it.
func TestTypedAlternativeLets(t *testing.T) {
	const prelude = `fn halve(n: Int) -> Optional[Int]:
    if n % 2 != 0:
        return none
    return some(value: n / 2)

`
	for _, tc := range []struct {
		name, body string
		typed      bool
	}{
		{"match only", "    let found = halve(n)\n    match found:\n        some(v):\n            return v\n        none:\n            return 0\n", true},
		{"matched twice", "    let found = halve(n)\n    match found:\n        some(v):\n            return v\n        none:\n            unit\n    match found:\n        some(v):\n            return v\n        none:\n            return 0\n", true},
		{"formatted", "    let found = halve(n)\n    match found:\n        some(v):\n            return v\n        none:\n            unit\n    return \"{found}\".length()\n", false},
		{"captured", "    let found = halve(n)\n    let read = fn() -> Int:\n        match found:\n            some(v):\n                return v\n            none:\n                return 0\n    return read()\n", false},
		{"variable", "    var found = halve(n)\n    match found:\n        some(v):\n            return v\n        none:\n            return 0\n", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := compileSource("alt-let.ms", prelude+"fn use(n: Int) -> Int:\n"+tc.body)
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			typed := regexp.MustCompile(`var local\d+_found rt\.Option\[int64\] =`).MatchString(r.Source)
			if typed != tc.typed {
				t.Fatalf("typed let = %v, want %v\n%s", typed, tc.typed, r.Source)
			}
		})
	}
}
