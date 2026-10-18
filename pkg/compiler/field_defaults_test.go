package compiler

import (
	"fmt"
	"strings"
	"testing"
)

func TestFieldDefaultBoundaries(t *testing.T) {
	for _, item := range []struct{ source, want string }{
		{"type Options:\n    count: Int = true\n", "expected Int, found Bool"},
		{"type Options:\n    first: Int = second\n    second: Int = 2\n", "unknown binding second"},
		{"type Options:\n    count: Int = count\n", "unknown binding count"},
		{"type Options:\n    count: Int = 1\n    required: Int\nfn f() -> Options: return Options()\n", "missing argument required"},
		{"type Box[T]:\n    value: T = 1\n", "expected T, found Int"},
		{"type Growing[T]:\n    value: T\n    next: Int = grow([value])\nfn grow[T](value: T) -> Int:\n    let item = Growing(value: value)\n    return 0\n", "recursive generic applications must preserve their parameters"},
		{"fn missing() -> Int:\n", "reachable fallthrough"},
		{"type Handle:\n    fn read() -> Int:\n", "a type declares only fields or cases"},
	} {
		result := CompileSource("fields.ms", item.source, Options{AnalyzeOnly: true})
		if result.Success() || !strings.Contains(fmt.Sprint(result.Diagnostics), item.want) {
			t.Errorf("expected %q: %v", item.want, result.Diagnostics)
		}
	}
}
