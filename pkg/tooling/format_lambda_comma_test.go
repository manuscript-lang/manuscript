package tooling_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func TestFormatBlockLambdaFollowedByArgument(t *testing.T) {
	for _, delimiter := range []string{"dedented", "grouped"} {
		source := "fn apply(transform: fn(value: Int) -> Int, value: Int) -> Int: transform(value)\nfn example() -> Int:\n    return apply(\n        transform: fn(value: Int) -> Int:\n            return value - 1\n        ,\n        value: 3,\n    )\n"
		if delimiter == "grouped" {
			source = strings.Replace(source, "transform: fn(value: Int) -> Int:\n            return value - 1\n        ,", "transform: (\n            fn(value: Int) -> Int:\n                return value - 1\n        ),", 1)
		}
		for _, newline := range []string{"\n", "\r\n"} {
			input := strings.ReplaceAll(source, "\n", newline)
			formatted, err := tooling.Format("lambda.ms", input)
			if err != nil {
				t.Fatal(err)
			}
			assertFormatMeaning(t, "lambda.ms", input, formatted)
			twice, err := tooling.Format("lambda.ms", formatted)
			if err != nil || twice != formatted {
				t.Fatalf("not idempotent: %v", err)
			}
			if result := compiler.CompileSource("lambda.ms", formatted, compiler.Options{}); !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		}
	}
}
