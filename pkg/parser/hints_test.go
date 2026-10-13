package parser_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
)

func TestSyntaxErrorsStateTheFix(t *testing.T) {
	for _, tt := range []struct{ name, source, want string }{
		{"missing header colon", "fn f() -> Int\n    return 1\n", "must end with ':'"},
		{"tab", "fn f() -> Int:\n\treturn 1\n", "indent with four spaces"},
		{"odd indent", "fn f() -> Int:\n  return 1\n", "found 2; use 0 or 4"},
		{"unterminated paren", "fn f() -> Int:\n    return (1\n", "opened at line 2:12"},
		{"unterminated text", "fn f() -> Int:\n    let s = \"abc\n    return 1\n", "unterminated text literal; text must close"},
		{"semicolon", "fn f() -> Int:\n    return 1;\n", "remove the semicolon"},
		{"top-level statement", "let x = 1\n", "put statements inside a fn"},
		{"missing expression", "fn f() -> Int:\n    let x = \n    return 1\n", "expected an expression, found end of line"},
		{"standalone expression", "fn f() -> Int:\n    1 + 1\n    return 1\n", "use 'let name = ...'"},
		{"indexing", "fn f(xs: List[Int]) -> Int:\n    return xs[0]\n", "xs.at(index: 0)"},
		{"unknown escape", "fn f() -> String:\n    return \"a\\q\"\n", "valid escapes are"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			_, err := parser.Parse("hints.ms", tt.source)
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("expected %q, got %v", tt.want, err)
			}
		})
	}
}
