package compiler

import (
	"strings"
	"testing"
)

func TestMapTransformContracts(t *testing.T) {
	for _, test := range []struct{ name, source, want string }{
		{"value map preserves keys", `fn wrong(values: Map[String, Int]) Map[Int, Int]: values.map(fn(k, v): v)`, "String"},
		{"key map preserves values", `fn wrong(values: Map[String, Int]) Map[Int, String]: values.map_keys(fn(k, v): v)`, "Int"},
		{"key output requires Hashable", `fn wrong(values: Map[String, Int]) Unit:
    let mapped = values.map_keys(fn(k, v): v.to_float())`, "Hashable"},
		{"generic output requires bound", `fn wrong[W](values: Map[String, Int], transform: fn(key: String, value: Int) W) Unit:
    let mapped = values.map_keys(transform)`, "Hashable"},
		{"map callback labels stay exact", `fn transform(value: Int, key: String) Int: value
fn wrong(values: Map[String, Int]) Map[String, Int]: values.map(transform)`, "key"},
		{"last-match predicate returns Bool", `fn wrong(values: Map[String, Int]) Unit:
    let found = values.find_last(fn(k, v): v)`, "Bool"},
		{"reverse fold keeps accumulator type", `fn wrong(values: Set[Int]) Int: values.fold_right(0, fn(acc, v): v.toString())`, "Int"},
		{"last Map match returns entry", `fn wrong(values: Map[String, Int]) Optional[Int]: values.find_last(fn(k, v): true)`, "MapEntry"},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := CompileSource("transform.ms", ""+test.source+"\n", Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("accepted incompatible contract")
			}
			for _, diagnostic := range result.Diagnostics {
				if strings.Contains(diagnostic.Message, test.want) {
					return
				}
			}
			t.Fatalf("expected %q, got %v", test.want, result.Diagnostics)
		})
	}
	t.Run("value output stays unconstrained", func(t *testing.T) {
		result := CompileSource("transform.ms", `fn allowed(values: Map[String, Int]) Map[String, Float]:
    return values.map(fn(key, value): value.to_float())
`, Options{AnalyzeOnly: true})
		if !result.Success() {
			t.Fatal(result.Diagnostics)
		}
	})
}
