package e2e_test

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestUnprovenIndexIsRejectedAsInt(t *testing.T) {
	result := compiler.CompileSource("unproven.ms", "fn read(values: List[Int], index: Int) -> Int:\n    if index < values.length():\n        return values[index]\n    return 0\n", compiler.Options{})
	rejected(t, result, "type", "expected Int, found Optional[Int]")
}
