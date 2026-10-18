package lexer_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/lexer"
)

func BenchmarkLex(b *testing.B) {
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
				benchmarkLex(b, text)
			})
		}
	}
	for _, size := range []int{65536, 131072, 262144} {
		for _, ending := range []string{"LF", "CRLF"} {
			newline := "\n"
			if ending == "CRLF" {
				newline = "\r\n"
			}
			b.Run(fmt.Sprintf("LongComment/%s/%d", ending, size), func(b *testing.B) {
				benchmarkLex(b, "# "+strings.Repeat("x", size)+newline+"fn value() Int:"+newline+"    return 1"+newline)
			})
		}
	}
	b.Run("Malformed", func(b *testing.B) {
		source := "fn invalid() Int:\n    return [1, 2)\n"
		b.ReportAllocs()
		for b.Loop() {
			if _, err := lexer.Lex("bench.ms", source); err == nil {
				b.Fatal("expected diagnostic")
			}
		}
	})
}

func benchmarkLex(b *testing.B, source string) {
	b.Helper()
	b.SetBytes(int64(len(source)))
	b.ReportAllocs()
	b.ResetTimer()
	for b.Loop() {
		if _, err := lexer.Lex("bench.ms", source); err != nil {
			b.Fatal(err)
		}
	}
}
