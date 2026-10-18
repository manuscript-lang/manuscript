package compiler

import (
	"strings"
	"testing"
)

func TestListTakeDropRejectInvalidContracts(t *testing.T) {
	for _, method := range []string{"take", "drop"} {
		for _, test := range []struct{ name, source, want string }{
			{"count is Int", `fn wrong() List[Int]: [1].METHOD(true)`, "Int"},
			{"payload type stays exact", `fn wrong() List[String]: [1].METHOD(1)`, "List[Int]"},
			{"required count", `fn wrong() List[Int]: [1].METHOD()`, "count"},
			{"bound label", `fn wrong() List[Int]:
    let copy = [1].METHOD
    return copy(length: 1)`, "length"},
		} {
			t.Run(method+"/"+test.name, func(t *testing.T) {
				result := CompileSource("list-copy.ms", strings.ReplaceAll(test.source, "METHOD", method)+"\n", Options{AnalyzeOnly: true})
				if result.Success() {
					t.Fatal("accepted invalid List copy contract")
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
}
