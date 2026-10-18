package e2e_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// Method behavior lives in testdata/accept/inherent-methods.ms; only the fault
// frame, which the ms test runner cannot inspect, is checked here.
func TestInherentImplFaultFrame(t *testing.T) {
	result := compiler.CompileSource("inherent.ms", `type Counter:
    value: Int

impl Counter:
    fn overflow() Int:
        return self.value * self.value

test "inherent fault frame":
    Counter(value: 9223372036854775807).overflow()
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err == nil || !strings.Contains(string(output), "1 tests, 1 failed") || !strings.Contains(string(output), "in Counter.overflow") {
		t.Fatalf("inherent fault frame changed: %v\n%s", err, output)
	}
}

func TestInherentImplRejections(t *testing.T) {
	for _, item := range []struct{ source, want string }{
		{"type A:\n    x: Int\n    fn f() Int:\n        return 1\n", "a type declares only fields or cases"},
		{"interface I:\n    fn f() Int\nimpl I:\n    fn f() Int:\n        return 1\n", "I is an interface"},
		{"import Duration from \"@std/time.ms\"\nimpl Duration:\n    fn f() Int:\n        return 1\n", "inherent methods belong in the module that declares Duration"},
		{"type B[T]:\n    x: T\nimpl B:\n    fn f() Int:\n        return 1\n", "impl must repeat the type parameters of B"},
		{"type B:\n    x: Int\nimpl B:\n    fn m[U](u: U) U:\n        return u\n", "declares its own type parameters"},
		{"type B:\n    x: Int\nimpl B:\n    fn m() Int:\n        return 1\nimpl B:\n    fn m() Int:\n        return 2\n", "duplicate implementation operation m"},
		{"type B:\n    x: Int\nimpl B:\n    fn m() Int:\n", "reachable fallthrough"},
	} {
		result := compiler.CompileSource("rejected.ms", item.source, compiler.Options{AnalyzeOnly: true})
		if result.Success() || !strings.Contains(fmt.Sprint(result.Diagnostics), item.want) {
			t.Errorf("expected %q: %v", item.want, result.Diagnostics)
		}
	}
}
