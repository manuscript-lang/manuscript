package parser

import (
	"reflect"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestTextPartsAcrossStrictAndPartialParsing(t *testing.T) {
	for _, test := range []struct {
		raw  string
		want []syntax.TextPart
	}{
		{`""`, []syntax.TextPart{{Text: ""}}},
		{`"plain text"`, []syntax.TextPart{{Text: "plain text"}}},
		{`"é😀"`, []syntax.TextPart{{Text: "é😀"}}},
		{`"a\n\t\r\u{1F600}\{x\}\\\""`, []syntax.TextPart{{Text: "a\n\t\r😀{x}\\\""}}},
	} {
		for _, prefix := range []string{"", "fn broken(\r\n"} {
			source := prefix + "# prefix\r\nfn value() String:\n    return " + test.raw + "\r\n"
			var module *syntax.Module
			if prefix == "" {
				var err error
				module, err = Parse("text.ms", source)
				if err != nil {
					t.Fatal(err)
				}
			} else {
				var issues []syntax.Diagnostic
				module, issues = ParsePartial("text.ms", source)
				if len(issues) != 1 {
					t.Fatalf("unexpected diagnostics: %v", issues)
				}
			}
			if len(module.Declarations) != 1 {
				t.Fatalf("unexpected declarations: %+v", module.Declarations)
			}
			text := module.Declarations[0].Body[0].Value
			offset := strings.Index(source, test.raw)
			wantPos := syntax.Position{File: "text.ms", Line: strings.Count(source[:offset], "\n") + 1, Column: 12, Offset: offset}
			if text.Pos != wantPos || !reflect.DeepEqual(text.Parts, test.want) {
				t.Fatalf("%s: position %+v, parts %+v; want %+v, %+v", test.raw, text.Pos, text.Parts, wantPos, test.want)
			}
		}
	}
}
