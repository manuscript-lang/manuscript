package parser

import (
	"fmt"
	"reflect"
	"strings"
	"testing"
)

func continuationSource(kind string, size int) string {
	if strings.HasSuffix(kind, "CRLF") {
		return strings.ReplaceAll(continuationSource(strings.TrimSuffix(kind, "CRLF"), size), "\n", "\r\n")
	}
	var source strings.Builder
	if kind != "Imports" && kind != "Constants" {
		source.WriteString("fn broken(\n")
	}
	switch kind {
	case "Imports":
		source.WriteString("import{\n")
		for i := range size {
			fmt.Fprintf(&source, "Name%d,\n", i)
		}
		source.WriteString("} from \"./module.ms\"\nfn broken(\n")
	case "Constants":
		source.WriteString("let values = [\n")
		for range size {
			source.WriteString("1,\n")
		}
		source.WriteString("]\nfn broken(\n")
	case "ManyFunctions", "UnsupportedCalls", "TinyUnterminated", "TinyInvalid":
		for i := range size {
			switch kind {
			case "ManyFunctions":
				fmt.Fprintf(&source, "fn later%d(\nvalue: Int,\n) Int:\n    return 1\n", i)
			case "UnsupportedCalls":
				source.WriteString("call(\n1,\n)\n")
			case "TinyUnterminated":
				fmt.Fprintf(&source, "fn later%d(\nvalue: Int,\n", i)
			case "TinyInvalid":
				fmt.Fprintf(&source, "fn later%d(\nvalue: ) Int:\n    return 1\n", i)
			}
		}
	default:
		source.WriteString("fn later(\n")
		for i := range size {
			fmt.Fprintf(&source, "value%d: Int,\n", i)
		}
		switch kind {
		case "Unterminated":
		case "InvalidHeader":
			source.WriteString("last: ) Int:\n    return 1\n")
		case "InvalidBody":
			source.WriteString(") Int:\n    let invalid = = 1\n    return 1\n")
		default:
			source.WriteString(") Int:\n    return 1\n")
		}
	}
	return source.String()
}

func BenchmarkPartialContinuation(b *testing.B) {
	for _, kind := range []string{"Valid", "ValidCRLF", "Imports", "Constants", "ManyFunctions", "Unterminated", "InvalidHeader", "InvalidBody", "InvalidBodyCRLF", "TinyUnterminated", "TinyInvalid", "UnsupportedCalls"} {
		for _, size := range []int{64, 128, 256} {
			b.Run(fmt.Sprintf("%s/%d", kind, size), func(b *testing.B) {
				source := continuationSource(kind, size)
				want, issues := legacyParsePartial("bench.ms", source)
				b.SetBytes(int64(len(source)))
				b.ReportAllocs()
				for b.Loop() {
					got, diagnostics := ParsePartial("bench.ms", source)
					if len(got.Declarations) != len(want.Declarations) || len(got.Imports) != len(want.Imports) || len(diagnostics) != len(issues) {
						b.Fatal("unexpected recovery result")
					}
				}
			})
		}
	}
}

func comparePartial(t *testing.T, source string) {
	t.Helper()
	want, wantIssues := legacyParsePartial("differential.ms", source)
	got, gotIssues := ParsePartial("differential.ms", source)
	if !reflect.DeepEqual(got, want) || !reflect.DeepEqual(gotIssues, wantIssues) {
		t.Fatalf("recovery differs from legacy splitter for %q\ngot: %#v; issues: %#v\nwant: %#v; issues: %#v", source, got, gotIssues, want, wantIssues)
	}
}

func TestPartialContinuationDifferential(t *testing.T) {
	fragments := []string{
		"", "# prefix\n", "fn broken(\n", "let broken = [\n",
		"fn later(\nvalue: Int = 3,\n) Int:\n    return value\n",
		"export fn later[\nT,\n](\nvalue: T,\n) T:\n    return value\n",
		"import{\nName,\nOther,\n} from \"./module.ms\"\n",
		"export let(\n    first = 1\n    second = 2\n)\n",
		"let value = [\n1,\n2,\n]\n", "let first = 1\nlet second = 2\n",
		"fn later(\nletter: String = \"{1 + 2}\",\ninterface_name: Int = 1,\n) Int:\n    return 1\n",
		"fn work() Int:\n    let bad = = 1\n    return 1\n",
		"fn later(\nvalue: Int,\n", "call(\n1,\n)\n",
		"impl Box:\n    fn value(self) Int:\n        return 1\n",
		"# comment with )]}\n", "let invalid = = 1\n",
	}
	for i, first := range fragments {
		for j, second := range fragments {
			for k, third := range []string{"", "fn broken(\n", "let value = 1\n", "# tail\n"} {
				source := first + second + third
				for _, ending := range []string{"LF", "CRLF", "mixed"} {
					t.Run(fmt.Sprintf("%d/%d/%d/%s", i, j, k, ending), func(t *testing.T) {
						text := source
						if ending == "CRLF" {
							text = strings.ReplaceAll(text, "\n", "\r\n")
						} else if ending == "mixed" {
							text = "# mixed prefix\r\n" + strings.Replace(text, "\n", "\r\n", 1)
						}
						comparePartial(t, text)
					})
				}
			}
		}
	}
	for _, kind := range []string{"Valid", "Imports", "Constants", "ManyFunctions", "Unterminated", "InvalidHeader", "InvalidBody", "TinyUnterminated", "TinyInvalid", "UnsupportedCalls"} {
		comparePartial(t, continuationSource(kind, 32))
	}
}

func TestPartialContinuationLeadingTriviaAndRecoverySpan(t *testing.T) {
	for _, tail := range []string{"    return 1\n", "    let bad = = 1\n    return 1\n"} {
		source := "# prefix\r\n# second\nfn work(\r\na: Int,\n) Int:\r\n" + tail + "fn broken(\n"
		comparePartial(t, source)
		module, _ := ParsePartial("span.ms", source)
		if len(module.Declarations) != 1 || module.Declarations[0].Pos.Offset != strings.Index(source, "fn work") {
			t.Fatal("lost first declaration or leading-trivia position", module)
		}
		if strings.Contains(tail, "bad") {
			if len(module.Recovered) != 1 || module.Recovered[0].Start != 0 || module.Recovered[0].End != strings.Index(source, "fn broken") {
				t.Fatal("leading trivia no longer belongs to first recovered chunk", module.Recovered)
			}
		} else if len(module.Recovered) != 0 {
			t.Fatal("valid continuation was marked repaired", module.Recovered)
		}
	}
}

func FuzzPartialContinuationDifferential(f *testing.F) {
	for _, kind := range []string{"Valid", "Imports", "Constants", "ManyFunctions", "Unterminated", "InvalidBody", "UnsupportedCalls"} {
		f.Add(continuationSource(kind, 3))
	}
	f.Add("# prefix\r\nfn work(\na: Int,\n) Int:\r\n    let bad = = 1\n    return 1\r\n")
	f.Fuzz(func(t *testing.T, source string) {
		// The legacy oracle intentionally retains quadratic malformed recovery.
		if len(source) > 8192 {
			t.Skip()
		}
		comparePartial(t, source)
	})
}
