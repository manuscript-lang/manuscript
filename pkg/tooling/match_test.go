package tooling_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"strings"
	"testing"
)

func TestFormatMatchExpressions(t *testing.T) {
	source := `fn read(values: List[Int]) Int:
    let result=match values.first():
        some(number):
            let doubled=number*2
            doubled
        none: return 0
    return result
`
	for _, ending := range []string{"\n", "\r\n"} {
		formatted, err := tooling.Format("match.ms", strings.ReplaceAll(source, "\n", ending))
		if err != nil {
			t.Fatal(err)
		}
		assertFormatMeaning(t, "match.ms", strings.ReplaceAll(source, "\n", ending), formatted)
		again, err := tooling.Format("match.ms", formatted)
		if err != nil || again != formatted {
			t.Fatalf("not idempotent: %v\n%s", err, again)
		}
		result := compiler.CompileSource("match.ms", formatted, compiler.Options{})
		if !result.Success() {
			t.Fatal(result.Diagnostics)
		}
	}
}
