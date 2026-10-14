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
		{"unbraced import list", "import a, b from \"x.ms\"\n", "import {a, b} from \"path.ms\""},
		{"missing expression", "fn f() -> Int:\n    let x = \n    return 1\n", "expected an expression, found end of line"},
		{"standalone expression", "fn f() -> Int:\n    1 + 1\n    return 1\n", "use 'let name = ...'"},
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

func TestPassAndIfExpressionHints(t *testing.T) {
	for _, tt := range []struct{ name, source, want string }{
		{"pass statement", "fn f(a: Int) -> Unit:\n    if a == 1:\n        pass\n", "'pass' is not a keyword; write 'unit'"},
		{"if expression", "fn f(a: Int) -> Int:\n    let b = if a == 1: 2 else: 3\n    return b\n", "'if' is a statement, not an expression"},
		{"if inside arithmetic", "fn f(a: Int) -> Int:\n    return 1 + (if a == 1: 1 else: 0)\n", "'if' is a statement, not an expression"},
		{"brace in text", "fn f() -> String:\n    return \"function() { return 1; }\"\n", "'{' at column"},
		{"brace before closing quote", "fn f() -> String:\n    return \"a { b\"\n", "unterminated interpolation; the quote after this '{'"},
		{"escaped quote in braces", "fn f() -> String:\n    return \"{\\\"a\\\": 1}\"\n", "'{' starts an interpolation; write \\{ and \\}"},
		{"unmatched closing", "fn f() -> String:\n    return \"a}\"\n", "(and \\{ for the opening brace)"},
		{"continued condition", "fn f(a: Int, b: Int) -> Bool:\n    return a > 0\n        and b > 0\n", "wrap the whole expression in parentheses"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			_, err := parser.Parse("hints.ms", tt.source)
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("want %q, got %v", tt.want, err)
			}
		})
	}
}
