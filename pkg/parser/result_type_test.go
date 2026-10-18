package parser

import (
	"strings"
	"testing"
)

func TestResultTypeFollowsParametersWithoutArrow(t *testing.T) {
	for _, source := range []string{
		"fn f(x: Int) Int: x\n",
		"fn f(g: fn(value: Int) Int) fn(value: Int) Int:\n    return g\n",
		"fn f() Int:\n    let g = fn(x) Int: x + 1\n    let h = fn(x): x + 1\n    return g(1) + h(2)\n",
		"interface Read:\n    fn read() Int\n",
		"type Box:\n    value: Int\nimpl Box:\n    fn get() Int: self.value\n",
		"fn f() Unit:\n    let g = fn(x: Int) Result[Int, String]: ok(x)\n    return unit\n",
	} {
		if _, err := Parse("accept.ms", source); err != nil {
			t.Errorf("rejected %q: %v", source, err)
		}
	}
}

func TestResultTypeRejectsArrowAndOmission(t *testing.T) {
	for _, test := range []struct{ source, message string }{
		{"fn f() -> Int: 1\n", "without an arrow"},
		{"fn f(g: fn(value: Int) -> Int) Int: 1\n", "without an arrow"},
		{"fn f() Int:\n    let g = fn(x) -> Int: x\n    return 0\n", "without an arrow"},
		{"interface Read:\n    fn read() -> Int\n", "without an arrow"},
		{"fn f():\n    return unit\n", "declares its result type"},
		{"interface Read:\n    fn read()\n", "declares its result type"},
	} {
		_, err := Parse("reject.ms", test.source)
		if err == nil || !strings.Contains(err.Error(), test.message) {
			t.Errorf("%q: got %v, want %q", test.source, err, test.message)
		}
	}
}
