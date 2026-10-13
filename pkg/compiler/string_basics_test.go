package compiler

import (
	"strings"
	"testing"
)

func TestStringBasicsRejectInvalidContracts(t *testing.T) {
	for _, test := range []struct{ name, source, want string }{
		{"length is Int", `fn wrong() -> Bool: "é".length()`, "Int"},
		{"empty is Bool", `fn wrong() -> Int: "".is_empty()`, "Bool"},
		{"chars contain Strings", `fn wrong() -> List[Int]: "é".chars()`, "List[String]"},
		{"lines contain Strings", `fn wrong() -> List[Int]: "a".lines()`, "List[String]"},
		{"reverse is String", `fn wrong() -> List[String]: "a".reverse()`, "String"},
		{"compare result is Int", `fn wrong() -> Bool: "a".compare("b")`, "Int"},
		{"compare input is String", `fn wrong() -> Int: "a".compare(1)`, "String"},
		{"compare bound label", `fn wrong() -> Int:
    let compare = "a".compare
    return compare(value: "b")`, "value"},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := CompileSource("string-basics.ms", "import List from \"@std/collections.ms\"\n"+test.source+"\n", Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("accepted invalid contract")
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
