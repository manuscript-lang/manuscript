package lsp

import (
	"fmt"
	"reflect"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/lexer"
)

func TestSemanticOriginalUnicodeAndRecoveryPositions(t *testing.T) {
	type expectedToken struct {
		text string
		kind int
	}
	for _, tc := range []struct {
		name, source string
		tokens       []expectedToken
		malformed    bool
	}{
		{"valid CRLF", "# α😀\r\nfn answer() String: \"é😀\"\r\n", []expectedToken{{"fn", 0}, {"answer", 5}, {"String", 1}, {"\"é😀\"", 3}}, false},
		{"unfinished text", "# α😀\r\nfn answer() String: \"é😀\r\nunfinished", []expectedToken{{"# α😀", 4}, {"fn", 0}, {"answer", 5}, {"String", 1}, {"\"é😀", 3}, {"unfinished", 3}}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, lexErr := lexer.Lex("positions.ms", tc.source)
			if (lexErr != nil) != tc.malformed {
				t.Fatalf("unexpected lexer state: %v", lexErr)
			}
			want := []int{}
			previous := position{}
			searchAt := 0
			for _, token := range tc.tokens {
				at := strings.Index(tc.source[searchAt:], token.text)
				if at < 0 {
					t.Fatalf("missing expected token %q", token.text)
				}
				at += searchAt
				start := referencePosition(tc.source, at)
				end := referencePosition(tc.source, at+len(token.text))
				character := start.Character
				if start.Line == previous.Line {
					character -= previous.Character
				}
				want = append(want, start.Line-previous.Line, character, end.Character-start.Character, token.kind, 0)
				previous = start
				searchAt = at + len(token.text)
			}
			got := semantic(document{URI: "file:///positions.ms", Text: tc.source})["data"].([]int)
			if !reflect.DeepEqual(got, want) {
				t.Fatalf("got=%v want=%v", got, want)
			}
		})
	}
}

func TestDocumentSymbolOriginalHeaderAndFieldPositions(t *testing.T) {
	for _, ending := range []string{"\n", "\r\n"} {
		for _, broken := range []string{"", "fn broken(\n"} {
			source := strings.ReplaceAll("# α😀\ninterface Read:\n    fn get() Int\ntype Box:\n    value: Int # 😀é\nimpl Read for Box:\n    fn get() Int:\n        return self.value\nfn neighbor() Int: 1\n"+broken, "\n", ending)
			d := document{URI: "file:///symbols.ms", Text: source}
			result := compiler.CompileSource("/symbols.ms", source, compiler.Options{AnalyzeOnly: true, Recover: true})
			if (len(result.Diagnostics) != 0) != (broken != "") || result.Program == nil {
				t.Fatal("unexpected recovery diagnostics", result.Diagnostics)
			}
			m := module(result, d)
			if m == nil || len(m.Declarations) != 4 {
				t.Fatal("missing recovered declarations", result.Diagnostics)
			}
			symbols := documentSymbols(result, d)
			if len(symbols) != 4 {
				t.Fatalf("got %d symbols", len(symbols))
			}
			tokens, _ := lexer.Lex(m.File, source)
			for i, decl := range m.Declarations {
				symbol := symbols[i].(map[string]any)
				want := span{referencePosition(source, decl.Pos.Offset), referencePosition(source, decl.Pos.Offset)}
				// Retain the original full token scan as the selection oracle,
				// including its fallback when lexing a malformed snapshot fails.
				for _, token := range tokens {
					if token.Pos.Offset < decl.Pos.Offset {
						continue
					}
					if token.Kind == lexer.Newline {
						if token.Pos.Offset == decl.Pos.Offset {
							continue
						}
						break
					}
					if token.Kind == lexer.Name && token.Text == decl.Name {
						want = span{referencePosition(source, token.Pos.Offset), referencePosition(source, token.Pos.Offset+len(decl.Name))}
						break
					}
				}
				if got := symbol["selectionRange"].(span); got != want {
					t.Fatalf("%s selection=%+v want=%+v", decl.Name, got, want)
				}
			}
			field := symbols[1].(map[string]any)["children"].([]any)[0].(map[string]any)
			at := strings.Index(source, "value: Int")
			end := at + len("value: Int # 😀é")
			if got := field["range"].(span); got != (span{referencePosition(source, at), referencePosition(source, end)}) {
				t.Fatalf("field range=%+v", got)
			}
		}
	}
}

var benchmarkDocumentSymbols []any

func BenchmarkDocumentSymbolPositions(b *testing.B) {
	for _, n := range []int{1000, 2000, 4000} {
		b.Run(fmt.Sprint(n), func(b *testing.B) {
			var source strings.Builder
			for i := 0; i < n; i++ {
				fmt.Fprintf(&source, "# α😀\r\nfn f%d() Int: %d\r\n", i, i)
			}
			d := document{URI: "file:///symbols.ms", Text: source.String()}
			result := compiler.CompileSource("/symbols.ms", d.Text, compiler.Options{AnalyzeOnly: true})
			if !result.Success() {
				b.Fatal(result.Diagnostics)
			}
			if got := len(documentSymbols(result, d)); got != n {
				b.Fatalf("got %d symbols, want %d", got, n)
			}
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				benchmarkDocumentSymbols = documentSymbols(result, d)
			}
		})
	}
}
