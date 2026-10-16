package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

const jsonParseHeader = "import {parse, JsonValue, JsonError} from \"@std/json.ms\"\n"

// parse[T] takes its type from the expected result, an explicit argument, or
// the JsonValue default. Like stringify it admits every type at check time.
func TestParseTypeArgument(t *testing.T) {
	cases := []struct{ name, source, want string }{
		{"default is JsonValue", "fn f(text: String) -> Result[JsonValue, JsonError]:\n    return parse(text)\n", ""},
		{"explicit record", "type Request:\n    model: String\nfn f(text: String) -> Result[Request, JsonError]:\n    return parse[Request](text)\n", ""},
		{"expected result", "type Request:\n    model: String\nfn f(text: String) -> Result[Request, JsonError]:\n    return parse(text)\n", ""},
		{"try with explicit type", "type Request:\n    model: String\nfn f(text: String) -> Result[Request, JsonError]:\n    let request = try parse[Request](text)\n    return ok(request)\n", ""},
		{"try gives no context", "type Request:\n    model: String\nfn f(text: String) -> Result[Request, JsonError]:\n    let request: Request = try parse(text)\n    return ok(request)\n", "expected"},
		{"unbounded generic", "fn f[T](text: String) -> Result[T, JsonError]:\n    return parse[T](text)\n", ""},
		{"function field accepted", "type Request:\n    callback: fn() -> Int\nfn f(text: String) -> Result[Request, JsonError]:\n    return parse[Request](text)\n", ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			source := jsonParseHeader + c.source
			m, err := parser.Parse("parse.ms", source)
			if err != nil {
				t.Fatal(err)
			}
			diagnostics := checker.Check([]*syntax.Module{m}, nil).Diagnostics
			if c.want == "" {
				if len(diagnostics) != 0 {
					t.Fatal(diagnostics)
				}
				return
			}
			for _, d := range diagnostics {
				if strings.Contains(d.Message, c.want) {
					return
				}
			}
			t.Fatalf("want %q, got %v", c.want, diagnostics)
		})
	}
}
