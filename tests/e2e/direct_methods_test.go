package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// Method semantics live in testdata/accept/direct-method-semantics.ms; only the
// fault frame, which the ms test runner cannot inspect, is checked here.
func TestDirectMethodFaultFrame(t *testing.T) {
	result := compiler.CompileSource("methods.ms", `interface Shape:
    fn area() Int

type Rect:
    w: Int
    h: Int

impl Shape for Rect:
    fn area() Int:
        return self.w * self.h

test "method fault frame":
    let rect = Rect(w: 9223372036854775807, h: 2)
    rect.area()
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err == nil || !strings.Contains(string(output), "1 tests, 1 failed") || !strings.Contains(string(output), "in Rect.area") {
		t.Fatalf("direct method fault frame changed: %v\n%s", err, output)
	}
}
