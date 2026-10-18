package parser_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestMatchPayloadPositionsSurviveRecovery(t *testing.T) {
	for _, newline := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll("# café 🦀\nfn use(value: Envelope) Int:\n    match value:\n        Pair(\n            _,\n            NotFound,\n        ): return 1\n", "\n", newline)
		for _, recover := range []bool{false, true} {
			input := source
			var module *syntax.Module
			if recover {
				input = "fn broken(\n" + input
				var diagnostics []syntax.Diagnostic
				module, diagnostics = parser.ParsePartial("positions.ms", input)
				if len(diagnostics) == 0 {
					t.Fatal("missing malformed-neighbor diagnostic")
				}
			} else {
				var err error
				module, err = parser.Parse("positions.ms", input)
				if err != nil {
					t.Fatal(err)
				}
			}
			if len(module.Declarations) != 1 {
				t.Fatal(module.Declarations)
			}
			arm := module.Declarations[0].Body[0].Value.Arms[0]
			if len(arm.NamePositions) != 2 {
				t.Fatal(arm)
			}
			line := 6
			if recover {
				line++
			}
			want := syntax.Position{File: "positions.ms", Line: line, Column: 13, Offset: strings.Index(input, "NotFound")}
			if arm.NamePositions[1] != want {
				t.Fatalf("got %+v, want %+v", arm.NamePositions[1], want)
			}
			if arm.NamePositions[0].Offset != strings.Index(input, "_,") {
				t.Fatal("placeholder position lost")
			}
		}
	}
}
