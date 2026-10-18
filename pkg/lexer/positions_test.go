package lexer_test

import (
	"reflect"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestMixedLineEndingPositions(t *testing.T) {
	for name, source := range map[string]string{
		"layout":                 "# é😀\r\n\nfn value() String:\r\n    # comment\n    if true:\r\n        return \"é😀\"\r\n    return \"\"\n",
		"continuation":           "fn value(\r\nvalue: Int,\n) Int:\r\n    return (value +\r\n1)\n",
		"trailing blank":         "# first\r\n\n\r\n",
		"no final newline":       "# first\r\nfn value() Int:\n    return 1",
		"lone CR in code":        "# first\r\nfn value() Int:\n    return 1\r",
		"lone CR in comment":     "# first\r\n# invalid\rcomment\n",
		"unknown escape":         "# first\r\nfn value() String:\n    return \"a\\q\"\r\n",
		"Unicode escape newline": "# first\r\nfn value() String:\n    return \"\\u{1\r\n",
		"raw newline in text":    "# first\r\nfn value() String:\n    return \"open\r\n",
		"open delimiter at EOF":  "# first\r\nfn value() Int:\n    return (1\r\n",
		"mismatched delimiter":   "# first\r\nfn value() Int:\n    return [1)\r\n",
	} {
		t.Run(name, func(t *testing.T) {
			normalized := strings.ReplaceAll(source, "\r\n", "\n")
			want, wantErr := lexer.Lex("positions.ms", normalized)
			got, gotErr := lexer.Lex("positions.ms", source)
			// The grammar uses byte columns. Mapping an LF reference position
			// through original line starts is independent of normalization.
			starts := []int{0}
			for i := range source {
				if source[i] == '\n' {
					starts = append(starts, i+1)
				}
			}
			original := func(p syntax.Position) syntax.Position {
				p.Offset = starts[p.Line-1] + p.Column - 1
				return p
			}
			for i := range want {
				want[i].Pos = original(want[i].Pos)
				want[i].End = original(want[i].End)
			}
			if !reflect.DeepEqual(got, want) {
				t.Fatalf("tokens differ:\n got: %+v\nwant: %+v", got, want)
			}
			if wantErr == nil {
				if gotErr != nil {
					t.Fatal(gotErr)
				}
				return
			}
			diagnostic := wantErr.(syntax.Diagnostic)
			diagnostic.Position = original(diagnostic.Position)
			if diagnostic.End != nil {
				end := original(*diagnostic.End)
				diagnostic.End = &end
			}
			if !reflect.DeepEqual(gotErr, diagnostic) {
				t.Fatalf("diagnostics differ:\n got: %#v\nwant: %#v", gotErr, diagnostic)
			}
		})
	}
}

func TestPunctuationTokenTextAndRanges(t *testing.T) {
	source := "() [] {} : , . + - * / % < > = & | -> == != <= >=\n"
	tokens, err := lexer.Lex("punctuation.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	want := strings.Fields("( ) [ ] { } : , . + - * / % < > = & | -> == != <= >=")
	if len(tokens) != len(want)+2 {
		t.Fatalf("unexpected tokens: %+v", tokens)
	}
	for i, text := range want {
		token := tokens[i]
		if token.Kind != text || token.Text != text || source[token.Pos.Offset:token.End.Offset] != text {
			t.Fatalf("token %d: %+v, want %q", i, token, text)
		}
	}
}
