package compiler_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestDeepGenericArgumentsCheckedOnce(t *testing.T) {
	// Rechecking each independently inferred argument made 40 nested calls
	// require trillions of checks. Both success and final mismatch stay bounded.
	for _, value := range []string{"1", `"wrong"`} {
		expression := strings.Repeat("identity(", 40) + value + strings.Repeat(")", 40)
		source := "fn identity[T](value: T) T: value\nfn first() Int: " + expression + "\n"
		result := compiler.CompileSource("nested-inference.ms", source, compiler.Options{})
		if value == "1" {
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		} else if len(result.Diagnostics) != 1 || !strings.Contains(fmt.Sprint(result.Diagnostics), "expected Int, found String") {
			t.Fatal(result.Diagnostics)
		}
	}
}
