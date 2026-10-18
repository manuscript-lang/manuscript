package parser

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/lexer"
)

func BenchmarkParse(b *testing.B) {
	for _, size := range []int{64, 128, 256} {
		var source strings.Builder
		for i := range size {
			fmt.Fprintf(&source, "fn sample%d(value: Int = 3) Int:\n    let items = [value, 2, 3]\n    if value >= 0:\n        return items[0].get(0) + value\n    return 0\n", i)
		}
		for _, ending := range []string{"LF", "CRLF"} {
			text := source.String()
			if ending == "CRLF" {
				text = strings.ReplaceAll(text, "\n", "\r\n")
			}
			b.Run(fmt.Sprintf("Declarations/%s/%d", ending, size), func(b *testing.B) {
				b.SetBytes(int64(len(text)))
				b.ReportAllocs()
				for b.Loop() {
					if _, err := Parse("bench.ms", text); err != nil {
						b.Fatal(err)
					}
				}
			})
		}
	}
}

func BenchmarkParseText(b *testing.B) {
	for _, size := range []int{64, 4096, 65536} {
		for name, raw := range map[string]string{
			"Plain":         strings.Repeat("x", size),
			"Escaped":       strings.Repeat(`x\n`, size/2),
			"Interpolation": strings.Repeat("x", size) + "{1 + 2}",
		} {
			b.Run(fmt.Sprintf("%s/%d", name, size), func(b *testing.B) {
				tokens, err := lexer.Lex("text.ms", `"`+raw+`"`)
				if err != nil {
					b.Fatal(err)
				}
				p := &Parser{}
				b.SetBytes(int64(len(raw)))
				b.ReportAllocs()
				b.ResetTimer()
				for b.Loop() {
					p.text(tokens[0])
				}
			})
		}
	}
}

func BenchmarkParsePartial(b *testing.B) {
	for _, size := range []int{64, 128, 256} {
		for _, kind := range []string{"Declarations", "Continuation", "Valid", "InvalidStatements"} {
			b.Run(fmt.Sprintf("%s/%d", kind, size), func(b *testing.B) {
				var source strings.Builder
				switch kind {
				case "Continuation":
					source.WriteString("fn broken(\nfn later(\n")
					for i := range size {
						fmt.Fprintf(&source, "value%d: Int,\n", i)
					}
					source.WriteString(") Int:\n    return 1\n")
				case "InvalidStatements":
					source.WriteString("fn later() Int:\n")
					for range size {
						source.WriteString("    let value = 1\n")
					}
					source.WriteString("    let invalid =\n    return 1\n")
				default:
					if kind != "Valid" {
						source.WriteString("fn broken(\n")
					}
					for i := range size {
						fmt.Fprintf(&source, "fn value%d() Int:\n    return 1\n", i)
					}
				}
				text := source.String()
				b.SetBytes(int64(len(text)))
				b.ReportAllocs()
				b.ResetTimer()
				for b.Loop() {
					module, issues := ParsePartial("partial.ms", text)
					if len(module.Declarations) == 0 || (kind != "Valid" && len(issues) == 0) {
						b.Fatal("unexpected recovery result", module, issues)
					}
				}
			})
		}
	}
}
