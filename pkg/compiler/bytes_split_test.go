package compiler

import (
	"strings"
	"testing"
)

func TestBytesSplitRejectsInvalidContracts(t *testing.T) {
	for _, test := range []struct{ name, source, want string }{
		{"separator is Bytes", `fn wrong(data: Bytes) -> List[Bytes]: data.split("x")`, "Bytes"},
		{"result is binary", `fn wrong(data: Bytes) -> List[String]: data.split(Bytes([]))`, "List[Bytes]"},
		{"cap is optional Int", `fn wrong(data: Bytes) -> List[Bytes]: data.split(Bytes([]), true)`, "Int"},
		{"bound label", `fn wrong(data: Bytes) -> List[Bytes]:
    let split = data.split
    return split(value: Bytes([]))`, "value"},
		{"complete stored method type", `fn wrong(data: Bytes) -> fn(separator: Bytes) -> List[Bytes]: data.split`, "max_parts"},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := CompileSource("bytes-split.ms", "import Bytes from \"@std/bytes.ms\"\nimport List from \"@std/collections.ms\"\n"+test.source+"\n", Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("accepted invalid byte split contract")
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
