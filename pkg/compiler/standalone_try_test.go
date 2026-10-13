package compiler

import (
	"strings"
	"testing"
)

func TestStandaloneTry(t *testing.T) {
	for _, tc := range []struct{ name, source, want string }{
		{"unit", "fn operation() -> Result[Unit, String]: ok(unit)\nfn f() -> Result[Int, String]:\n    try operation()\n    return ok(1)\n", ""},
		{"non unit", "fn operation() -> Result[Int, String]: ok(1)\nfn f() -> Result[Int, String]:\n    try operation()\n    return ok(1)\n", "standalone try requires a Unit success value"},
		{"wrong error", "fn operation() -> Result[Unit, Int]: ok(unit)\nfn f() -> Result[Int, String]:\n    try operation()\n    return ok(1)\n", "try requires the same error type"},
		{"unit enclosing", "fn operation() -> Result[Unit, String]: ok(unit)\nfn f() -> Unit:\n    try operation()\n", "try requires an enclosing Result"},
		{"not result", "fn operation() -> Unit: unit\nfn f() -> Result[Int, String]:\n    try operation()\n    return ok(1)\n", "try requires Result"},
		{"test enclosing", "fn operation() -> Result[Unit, String]: ok(unit)\ntest \"invalid\":\n    try operation()\n", "try requires an enclosing Result"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			result := CompileSource("try.ms", tc.source, Options{Tests: true})
			if tc.want == "" {
				if !result.Success() {
					t.Fatal(result.Diagnostics)
				}
				return
			}
			for _, diagnostic := range result.Diagnostics {
				if strings.Contains(diagnostic.Message, tc.want) {
					return
				}
			}
			t.Fatalf("wanted %q, got %v", tc.want, result.Diagnostics)
		})
	}
}
