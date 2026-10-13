package lexer_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestLayoutAndLineEndings(t *testing.T) {
	source := "# module\nfn value() -> Int:\n\n    # comment\n    if true:\n        return 3\n    else:\n        return 4\n"
	lf, err := lexer.Lex("layout.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	crlf, err := lexer.Lex("layout.ms", strings.ReplaceAll(source, "\n", "\r\n"))
	if err != nil {
		t.Fatal(err)
	}
	if len(lf) != len(crlf) {
		t.Fatal("line endings change tokens")
	}
	for i, token := range lf {
		other := crlf[i]
		if token.Kind != other.Kind || token.Text != other.Text || token.Pos.Line != other.Pos.Line || token.Pos.Column != other.Pos.Column {
			t.Fatal("line endings change token meaning")
		}
		if token.Text == "3" && strings.ReplaceAll(source, "\n", "\r\n")[other.Pos.Offset] != '3' {
			t.Fatal("CRLF offset does not reference original source")
		}
	}
	var layout []string
	for _, token := range lf {
		if token.Kind == lexer.Indent || token.Kind == lexer.Dedent {
			layout = append(layout, token.Kind)
		}
		if token.Text == "3" && (token.Pos.Line != 6 || token.Pos.Column != 16) {
			t.Fatal(token.Pos)
		}
	}
	if strings.Join(layout, ",") != "INDENT,INDENT,DEDENT,INDENT,DEDENT,DEDENT" {
		t.Fatal(layout)
	}
}

func TestLexicalBoundaries(t *testing.T) {
	for name, source := range map[string]string{
		"BOM":                 "\ufefffn value() -> Unit:\n    return\n",
		"UTF8":                string([]byte{0xff}),
		"unicode name":        "fn café() -> Unit:\n    return\n",
		"tab":                 "fn value() -> Unit:\n\treturn\n",
		"lone CR":             "fn value() -> Unit:\r    return\n",
		"jumped indentation":  "fn value() -> Unit:\n        return\n",
		"leading zero":        "fn value() -> Int:\n    return 03\n",
		"hex":                 "fn value() -> Int:\n    return 0xff\n",
		"separator":           "fn value() -> Int:\n    return 1_000\n",
		"exponent":            "fn value() -> Float:\n    return 1e+\n",
		"delimiters":          "fn value() -> Unit:\n    other(value: [1)\n",
		"raw control":         "fn value() -> String:\n    return \"a\tb\"\n",
		"surrogate":           "fn value() -> String:\n    return \"\\u{d800}\"\n",
		"empty interpolation": "fn value() -> String:\n    return \"{}\"\n",
	} {
		t.Run(name, func(t *testing.T) {
			_, err := lexer.Lex(name+".ms", source)
			diagnostic, ok := err.(syntax.Diagnostic)
			if !ok || diagnostic.Position.Line < 1 || diagnostic.Position.Column < 1 {
				t.Fatalf("missing positioned error: %v", err)
			}
		})
	}
	source := "fn value() -> String:\n    return \"héllo \\u{1F600} {1 + 2} \\{literal\\}\"\n"
	if _, err := lexer.Lex("unicode.ms", source); err != nil {
		t.Fatal(err)
	}
}

func TestTokenEndPositionsUseOriginalBytes(t *testing.T) {
	source := "fn f() -> String:\r\n    return \"é\" # keep\r\n"
	tokens, err := lexer.Lex("ends.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	for _, token := range tokens {
		if token.End.File != token.Pos.File || token.End.Offset < token.Pos.Offset || token.End.Offset > len(source) {
			t.Fatalf("invalid token range: %+v", token)
		}
		if token.Text != "" && source[token.Pos.Offset:token.End.Offset] != token.Text {
			t.Fatalf("incorrect original range: %+v", token)
		}
		if token.Kind == lexer.String && (token.End.Column != token.Pos.Column+len(token.Text) || token.End.Line != 2) {
			t.Fatalf("incorrect UTF-8 end: %+v", token)
		}
	}
}
