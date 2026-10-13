package compiler

import (
	"strings"
	"testing"
)

func TestAPIParityRejectsInvalidContracts(t *testing.T) {
	for name, source := range map[string]string{
		"opaque seeded generator": `import Random from "@std/random.ms"
test "invalid":
    let value = Random()
`,
		"random float arguments": `import seeded from "@std/random.ms"
test "invalid":
    let value = seeded(1).float(1)
`,
		"random choice needs list": `import seeded from "@std/random.ms"
test "invalid":
    let value = seeded(1).choice("abc")
`,
		"random bound label": `import seeded from "@std/random.ms"
test "invalid":
    let value = seeded(1).int(minimum: 0)
`,
		"bytes start is Int": `import Bytes from "@std/bytes.ms"
test "invalid":
    let value = Bytes([]).index_of_from(Bytes([]), 1.0)
`,
		"byte hex takes no args": `import Bytes from "@std/bytes.ms"
test "invalid":
    let value = Bytes([]).to_hex(1)
`,
		"regex find input is String": `import compile from "@std/regex.ms"
test "invalid":
    let value = compile("x").unwrap().find(1)
`,
		"regex capture presence preserved": `import compile from "@std/regex.ms"
test "invalid":
    let value: List[String] = compile("(x)").unwrap().find("x").unwrap().groups
`,
		"regex split retains Result": `import compile from "@std/regex.ms"
test "invalid":
    let value: List[String] = compile("x").unwrap().split("abc")
`,
		"integer power retains Result": `import pow_int from "@std/math.ms"
test "invalid":
    let value: Int = pow_int(2, 4)
`,
		"float conversion retains Optional": `test "invalid":
    let value: Int = 1.5.round_to_int()
`,
		"bigint exponent Int": `import from_int from "@std/bigint.ms"
test "invalid":
    let value = from_int(1).pow(1.0)
`,
		"HTML stringify domain": `import stringify from "@std/html.ms"
test "invalid":
    let value = stringify("<b>text</b>")
`,
		"timestamp format layout": `import timestamp from "@std/time.ms"
test "invalid":
    let value = timestamp(0, 0).unwrap().format(1)
`,
		"instant has no calendar format": `import clock from "@std/time.ms"
test "invalid":
    let value = clock().now().format("2006-01-02")
`,
		"list distinct needs equality": `import seeded from "@std/random.ms"
test "invalid":
    let value = [seeded(1)].distinct()
`,
		"list zip keeps pair records": `test "invalid":
    let value: List[Int] = [1].zip(["a"])
`,
		"list partition needs predicate": `test "invalid":
    let value = [1].partition(fn(value: Int) -> Int: return value)
`,
		"list min comparison required": `test "invalid":
    let value = [1].min()
`,
		"list insert index Int": `test "invalid":
    let value = [1].insert(1.0, 2)
`,
		"list pop retains Optional": `test "invalid":
    let value: Int = [1].pop()
`,
	} {
		t.Run(name, func(t *testing.T) {
			result := CompileSource("invalid-parity.ms", source, Options{Tests: true, AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("invalid public contract accepted")
			}
			for _, diagnostic := range result.Diagnostics {
				if strings.Contains(diagnostic.Message, "internal") {
					t.Fatalf("checking crashed instead of rejecting source: %v", result.Diagnostics)
				}
			}
		})
	}
}
