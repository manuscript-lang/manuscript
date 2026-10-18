package parser_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
)

func TestMixedArgumentsStrictAndPartial(t *testing.T) {
	for _, newline := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll("fn run() Int:\n    return select[Int](\n        1,\n        last: 3,\n        fn(value): value + 1,\n    )\n", "\n", newline)
		strict, err := parser.Parse("mixed.ms", source)
		if err != nil {
			t.Fatal(err)
		}
		partial, diagnostics := parser.ParsePartial("mixed.ms", source)
		if len(diagnostics) != 0 {
			t.Fatal(diagnostics)
		}
		for _, call := range []string{"strict", "partial"} {
			m := strict
			if call == "partial" {
				m = partial
			}
			args := m.Declarations[0].Body[0].Value.Args
			if len(args) != 3 || args[0].Name != "" || args[1].Name != "last" || args[2].Name != "" {
				t.Fatal(args)
			}
			for i, text := range []string{"1,", "last:", "fn(value)"} {
				if args[i].Pos.Offset != strings.Index(source, text) || args[i].Pos.Line != i+3 {
					t.Fatal(args[i].Pos)
				}
			}
		}
	}
}
