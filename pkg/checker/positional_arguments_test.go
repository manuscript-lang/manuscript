package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestArgumentBindingPreservesWrittenOrderAndSource(t *testing.T) {
	for _, tc := range []struct{ call, labels string }{
		{"f(1, 2, 3)", "first,second,third"},
		{"f(third: 3, 1, 2)", "third,first,second"},
		{"f(1, third: 3, 2)", "first,third,second"},
		{"f(second: 2, third: 3, first: 1)", "second,third,first"},
		{"f(third, first, second)", "first,second,third"},
		{"f((third), (first), (second))", "first,second,third"},
		{"f(first + 1, second, third)", "first,second,third"},
		{"f(1)", "first"},
		{"f(third: 3, 1)", "third,first"},
		{"f()", ""},
	} {
		t.Run(tc.call, func(t *testing.T) {
			source := "fn f(first: Int = 1, second: Int = 2, third: Int = 3) -> Int: first\nfn run(first: Int, second: Int, third: Int) -> Int: " + tc.call + "\n"
			m, err := parser.Parse("arguments.ms", source)
			if err != nil {
				t.Fatal(err)
			}
			call := m.Declarations[1].Body[0].Value
			original := append([]syntax.Argument(nil), call.Args...)
			for range 2 {
				p := checker.Check([]*syntax.Module{m}, nil)
				if len(p.Diagnostics) != 0 {
					t.Fatal(p.Diagnostics)
				}
				var names []string
				for i, arg := range p.Info(call).Arguments {
					names = append(names, arg.Name)
					if arg.Value != original[i].Value || arg.Pos != original[i].Pos || call.Args[i] != original[i] {
						t.Fatal("argument resolution changed source or written order")
					}
				}
				if strings.Join(names, ",") != tc.labels {
					t.Fatal(names, tc.labels)
				}
			}
		})
	}
}

func TestPositionalArgumentDiagnostics(t *testing.T) {
	for _, tc := range []struct {
		name, declarations, call, cause string
		count                           int
	}{
		{"missing", "fn f(first: Int, second: Int) -> Int: first", "f(1)", "missing argument second", 1},
		{"default before required", "fn f(first: Int = 1, second: Int) -> Int: second", "f(2)", "missing argument second", 1},
		{"excess", "fn f(first: Int, second: Int) -> Int: first", "f(1, 2, 3)", "too many positional arguments", 1},
		{"nullary", "fn f() -> Int: 1", "f(1)", "too many positional arguments", 1},
		{"duplicate mixed", "fn f(first: Int, second: Int = 2) -> Int: first", "f(1, first: 2)", "duplicate argument first", 1},
		{"duplicate label", "fn f(first: Int) -> Int: first", "f(first: 1, first: 2)", "duplicate argument first", 1},
		{"unknown label", "fn f(first: Int) -> Int: first", "f(other: 1, 2)", "unknown argument other", 1},
		{"wrong type", "fn f(first: Int, second: Bool) -> Int: first", "f(1, 2)", "expected Bool, found Int", 1},
		{"constructor missing", "type Pair:\n    first: Int\n    second: Int", "Pair(1)", "missing argument second", 1},
		{"constructor excess", "type Pair:\n    first: Int\n    second: Int", "Pair(1, 2, 3)", "too many positional arguments", 1},
		{"callback labels remain identity", "fn f(n: Int) -> Int: n\nfn apply(callback: fn(value: Int) -> Int, input: Int) -> Int: callback(input)", "apply(f, 1)", "expects value", 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m, err := parser.Parse("arguments.ms", tc.declarations+"\nfn run() -> Unit:\n    let ignored = "+tc.call+"\n")
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			if len(p.Diagnostics) != tc.count || !strings.Contains(p.Diagnostics[0].Message, tc.cause) {
				t.Fatal(p.Diagnostics)
			}
			if p.Diagnostics[0].Position.File != "arguments.ms" {
				t.Fatal(p.Diagnostics[0])
			}
		})
	}
}
