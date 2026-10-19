package e2e_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestCollectionQueryCallbackFaultLocations(t *testing.T) {
	for _, kind := range []string{"Map", "Set"} {
		for _, method := range []string{"fold", "find", "some", "every", "fold_right", "find_last", "map", "map_keys"} {
			if kind == "Set" && (method == "map" || method == "map_keys") {
				continue
			}
			t.Run(kind+"."+method, func(t *testing.T) {
				parameters, constructor := "value: Int", "Set[Int]()"
				if kind == "Map" {
					parameters, constructor = "key: String, value: Int", "Map[String, Int]()"
				}
				add := "add(0)"
				if kind == "Map" {
					add = "add(\"a\", 0)"
				}
				result, expression, arguments := "Bool", "1 / value == 0", "crash"
				if method == "fold" || method == "fold_right" {
					parameters = "accumulator: Int, " + parameters
					result, expression, arguments = "Int", "1 / value", "0, crash"
				}
				if method == "map" || method == "map_keys" {
					result, expression = "Int", "1 / value"
				}
				source := fmt.Sprintf("fn crash(%s) %s:\n    return %s\nexport fn main() Int:\n    var values = %s\n    values.%s\n    let result = values.%s(%s)\n    return 0\n", parameters, result, expression, constructor, add, method, arguments)
				assertQueryFaultFrames(t, source, []string{"query-fault.ms:2 in crash", "query-fault.ms:6 in main"})
			})
		}
	}
}

func TestLazyConversionFaultLocation(t *testing.T) {
	source := `import {TextError} from "@std/errors.ms"
fn crash() TextError:
    return TextError((1 / 0).to_string())
export fn main() Int:
    let value: Optional[Int] = none
    let result = value.ok_or_else(crash)
    return 0
`
	assertQueryFaultFrames(t, source, []string{"query-fault.ms:3 in crash", "query-fault.ms:6 in main"})
}

func assertQueryFaultFrames(t *testing.T, source string, expected []string) {
	t.Helper()
	result := compiler.CompileSource("query-fault.ms", source, compiler.Options{Entry: true})
	data, err := execute(t, result)
	if err == nil {
		t.Fatalf("expected callback fault: %s", data)
	}
	var frames []string
	for _, line := range strings.Split(string(data), "\n") {
		if frame, ok := strings.CutPrefix(line, "  at "); ok {
			frames = append(frames, frame)
		}
	}
	if strings.Join(frames, "\n") != strings.Join(expected, "\n") {
		t.Fatalf("frames = %q, want %q; transcript:\n%s", frames, expected, data)
	}
}
