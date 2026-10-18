package parser_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
)

func TestNestingLimits(t *testing.T) {
	const deep = 200000
	wrap := func(body string) string { return "fn f() Int:\n    return " + body + "\n" }
	for name, source := range map[string]string{
		"parentheses":   wrap(strings.Repeat("(", deep) + "1" + strings.Repeat(")", deep)),
		"lists":         wrap(strings.Repeat("[", deep) + strings.Repeat("]", deep)),
		"calls":         wrap(strings.Repeat("f(", deep) + "1" + strings.Repeat(")", deep)),
		"unary":         wrap(strings.Repeat("-", deep) + "1"),
		"operator":      wrap(strings.Repeat("1+", deep) + "1"),
		"interpolation": wrap(strings.Repeat("\"{", deep) + "1" + strings.Repeat("}\"", deep)),
		"member access": wrap("x" + strings.Repeat(".a", deep)),
		"types":         "fn f(x: " + strings.Repeat("(", deep) + "Int" + strings.Repeat(")", deep) + ") Int:\n    return 1\n",
	} {
		t.Run(name, func(t *testing.T) {
			_, err := parser.Parse("deep.ms", source)
			if err == nil || !strings.Contains(err.Error(), "exceeds") {
				t.Fatalf("expected a nesting diagnostic, got %v", err)
			}
		})
	}
}

func TestModerateNestingParses(t *testing.T) {
	source := "fn f() Int:\n    return " + strings.Repeat("(", 500) + "1" + strings.Repeat(")", 500) + " " + strings.Repeat("+ 1 ", 5000) + "\n"
	if _, err := parser.Parse("ok.ms", source); err != nil {
		t.Fatal(err)
	}
}
