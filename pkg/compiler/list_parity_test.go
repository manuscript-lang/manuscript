package compiler

import (
	"strings"
	"testing"
)

func TestListParityRejectInvalidContracts(t *testing.T) {
	for _, test := range []struct{ name, source, want string }{
		{"count predicate returns Bool", `fn wrong() -> Int: [1].count(fn(value: Int) -> Int: value)`, "Bool"},
		{"count returns Int", `fn wrong() -> Bool: [1].count(fn(value: Int) -> Bool: true)`, "Int"},
		{"insert index is Int", `fn wrong() -> List[Int]: [1].insert(true, 2)`, "Int"},
		{"insert value matches element", `fn wrong() -> List[Int]: [1].insert(0, "a")`, "String"},
		{"pop is Optional", `fn wrong() -> Int: [1].pop()`, "Optional[Int]"},
		{"distinct requires Equal", `fn wrong() -> Int:
    let values = [fn() -> Int: 1]
    return values.distinct().length`, "member distinct on List[fn()->Int]"},
		{"distinct payload type stays exact", `fn wrong() -> List[String]: [1].distinct()`, "List[Int]"},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := CompileSource("list-parity.ms", test.source+"\n", Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("accepted invalid List parity contract")
			}
			for _, diagnostic := range result.Diagnostics {
				if strings.Contains(diagnostic.Message, test.want) {
					return
				}
			}
			t.Fatalf("expected %q, got %v", test.want, result.Diagnostics)
		})
	}
}
