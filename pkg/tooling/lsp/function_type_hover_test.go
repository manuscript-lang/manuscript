package lsp

import (
	"strings"
	"testing"
)

func TestFunctionTypeHoverUsesSourceReturnSyntax(t *testing.T) {
	for _, tc := range []struct {
		name, source, needle, want string
	}{
		{
			"function",
			"fn double(value: Int) Int: value * 2\nfn run() Int: double(2)\n",
			"double(2)",
			"double: fn(value: Int) Int",
		},
		{
			"callback parameter",
			"fn apply(callback: fn(value: Int) Int) Int: callback(2)\n",
			"callback(2)",
			"callback: fn(value: Int) Int",
		},
		{
			"nested function types",
			"fn identity(callback: fn(value: Int) Int) fn(value: Int) Int: callback\nfn use(callback: fn(value: Int) Int) Int: identity(callback)(2)\n",
			"identity(callback)",
			"identity: fn(callback: fn(value: Int) Int) fn(value: Int) Int",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, _, hover := definitionAt(t, tc.source, strings.LastIndex(tc.source, tc.needle))
			if !strings.Contains(hover, "```manuscript\n"+tc.want+"\n```") {
				t.Fatalf("hover = %q, want source signature %q", hover, tc.want)
			}
		})
	}
}
