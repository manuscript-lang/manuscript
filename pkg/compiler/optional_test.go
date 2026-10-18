package compiler

import (
	"strings"
	"testing"
)

func TestOptionalArgumentsCompose(t *testing.T) {
	for _, payload := range []string{"4", "\"wrong\""} {
		argument := payload
		for range 32 {
			argument = "number(" + argument + ")"
		}
		source := "fn number(value: Optional[Int]) Int: return value.get()\nfn call() Int: return " + argument + "\n"
		result := CompileSource("nested.ms", source, Options{})
		if result.Success() != (payload == "4") {
			t.Fatal("incorrect nested argument compatibility", result.Diagnostics)
		}
	}
}

func TestOptionalArgumentBoundaries(t *testing.T) {
	for _, tt := range []struct{ name, source, want string }{
		{"wrong payload", "fn f(value: Optional[Int]) Unit: return\nfn call() Unit: f(\"wrong\")\n", "expected Optional[Int], found String"},
		{"numeric conversion", "fn f(value: Optional[Float]) Unit: return\nfn call() Unit: f(4)\n", "expected Optional[Float], found Int"},
		{"required optional", "fn f(value: Optional[Int]) Unit: return\nfn call() Unit: f()\n", "missing argument value"},
		{"assignment stays exact", "fn call() Unit:\n    let value: Optional[Int] = 4\n", "expected Optional[Int], found Int"},
		{"return stays exact", "fn f() Optional[Int]: return 4\n", "expected Optional[Int], found Int"},
		{"default stays exact", "fn f(value: Optional[Int] = 4) Unit: return\n", "expected Optional[Int], found Int"},
		{"no recursive wrapping", "fn f(value: Optional[Optional[Int]]) Unit: return\nfn call() Unit: f(4)\n", "expected Optional[Optional[Int]], found Int"},
		{"no unwrapping", "fn f(value: Int) Unit: return\nfn call() Unit: f(some(value: 4))\n", "expected Int, found Optional[Int]"},
		{"invariant optionals", "fn f(value: Optional[Float]) Unit: return\nfn call(value: Optional[Int]) Unit: f(value)\n", "expected Optional[Float], found Optional[Int]"},
		{"conflicting inference", "fn f[T](first: Optional[T], second: T) Unit: return\nfn call() Unit: f(first: 4, second: \"wrong\")\n", "conflicting generic inference"},
		{"omission does not infer", "fn f[T](value: Optional[T] = none) Unit: return\nfn call() Unit: f()\n", "cannot infer type argument T"},
		{"missing result context", "fn f[T](value: Optional[T]) T: return value.get()\nfn call() Unit: let value = f(none)\n", "cannot infer type argument T"},
		{"collection elements stay exact", "fn f(values: List[Optional[Int]]) Unit: return\nfn call() Unit: f([4])\n", "expected Optional[Int], found Int"},
		{"function identity stays exact", "fn f(value: Int) Int: return value\nfn call() Unit:\n    let callback: fn(value: Optional[Int]) Int = f\n", "expected fn(value: Optional[Int])"},
		{"unknown label", "fn f(value: Optional[Int]) Unit: return\nfn call() Unit: f(other: 4)\n", "unknown argument other"},
		{"duplicate label", "fn f(value: Optional[Int]) Unit: return\nfn call() Unit: f(4, value: 5)\n", "duplicate argument value"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			source := "" + tt.source
			result := CompileSource("optional.ms", source, Options{AnalyzeOnly: true})
			for _, diagnostic := range result.Diagnostics {
				if strings.Contains(diagnostic.Message, tt.want) {
					return
				}
			}
			t.Fatalf("expected %q, got %v", tt.want, result.Diagnostics)
		})
	}
	t.Run("same spelling is not the standard identity", func(t *testing.T) {
		result := CompileSource("local.ms", "type Optional[T]:\n    case some(value: T)\n    case none\nfn f(value: Optional[Int]) Unit: return\nfn call() Unit: f(4)\n", Options{AnalyzeOnly: true})
		if result.Success() {
			t.Fatal("wrapped into a local alternative named Optional")
		}
	})
}

func TestOptionalMethodsRejectInvalidContracts(t *testing.T) {
	for name, source := range map[string]string{
		"wrong fallback": `fn wrong(value: Optional[Int]) Int:
    return value.get("missing")
`,
		"nested values do not flatten": `fn wrong(value: Optional[Optional[Int]]) Int:
    return value.get()
`,
		"result does not inherit optional predicates": `fn wrong(value: Result[Int, String]) Bool:
    return value.is_some()
`,
		"local names do not inherit native methods": `type Optional[T]:
    case some(value: T)
    case none
fn wrong(value: Optional[Int]) Int:
    return value.get()
`,
		"private implementation is not a second public spelling": `import unwrap from "@std/optional.ms"
`,
	} {
		t.Run(name, func(t *testing.T) {
			if result := CompileSource("optional.ms", source, Options{}); result.Success() {
				t.Fatal("accepted an invalid Optional contract")
			}
		})
	}
}
