package lsp

import (
	"fmt"
	"strings"
	"testing"
	"unicode/utf16"
	"unicode/utf8"
)

// Keep the original allocation-based conversion as an independent oracle,
// including offsets inside UTF-8 sequences and CRLF line endings.
func referencePosition(source string, at int) position {
	if at < 0 {
		at = 0
	}
	if at > len(source) {
		at = len(source)
	}
	prefix := source[:at]
	return position{strings.Count(prefix, "\n"), len(utf16.Encode([]rune(prefix[strings.LastIndex(prefix, "\n")+1:])))}
}

func TestSourcePositionsMatchOriginalBytes(t *testing.T) {
	for _, source := range []string{"", "alpha\nbeta\n", "α😀\r\nβ😀\n", "\r\n\n\r", "é\xff😀\xe2\x82\r\nlast"} {
		positions := newSourcePositions(source)
		for at := -2; at <= len(source)+2; at++ {
			want := referencePosition(source, at)
			if got := positions.position(at); got != want {
				t.Fatalf("indexed source=%q at=%d got=%+v want=%+v", source, at, got, want)
			}
			if got := Position(source, at); got != want {
				t.Fatalf("standalone source=%q at=%d got=%+v want=%+v", source, at, got, want)
			}
		}
	}
}

// This retains the pre-change strict/clamping implementation so every error
// boundary is compared, rather than only checking successful round trips.
func referenceOffset(source string, p position, clamp bool) (int, error) {
	if p.Line < 0 || p.Character < 0 {
		return 0, fmt.Errorf("negative position")
	}
	at := 0
	for line := 0; line < p.Line; line++ {
		next := strings.IndexByte(source[at:], '\n')
		if next < 0 {
			if clamp {
				return len(source), nil
			}
			return 0, fmt.Errorf("line outside document")
		}
		at += next + 1
	}
	column := 0
	for at < len(source) && source[at] != '\n' && source[at] != '\r' {
		if column == p.Character {
			return at, nil
		}
		r, size := utf8.DecodeRuneInString(source[at:])
		width := 1
		if r > 0xffff {
			width = 2
		}
		column += width
		at += size
		if column > p.Character {
			return 0, fmt.Errorf("position splits a surrogate pair")
		}
	}
	if column != p.Character && !clamp {
		return 0, fmt.Errorf("character outside line")
	}
	return at, nil
}

func TestOffsetPreservesOriginalBoundaries(t *testing.T) {
	for _, source := range []string{"", "alpha\nbeta\n", "α😀\r\nβ😀\n", "a\rb\n", "é\xff😀\xe2\x82\r\nlast"} {
		for line := -1; line <= strings.Count(source, "\n")+2; line++ {
			for column := -1; column <= len(source)+2; column++ {
				for _, clamp := range []bool{false, true} {
					p := position{line, column}
					want, wantErr := referenceOffset(source, p, clamp)
					got, gotErr := offset(source, p, clamp)
					if got != want || fmt.Sprint(gotErr) != fmt.Sprint(wantErr) {
						t.Fatalf("source=%q p=%+v clamp=%t got=(%d,%v) want=(%d,%v)", source, p, clamp, got, gotErr, want, wantErr)
					}
				}
			}
		}
	}
	for _, clamp := range []bool{false, true} {
		if _, err := offset("😀", position{0, 1}, clamp); err == nil {
			t.Fatal("accepted a position inside a surrogate pair")
		}
	}
}

var benchmarkPosition position

func BenchmarkIndexedPositions(b *testing.B) {
	for _, n := range []int{1000, 2000, 4000, 8000} {
		b.Run(fmt.Sprint(n), func(b *testing.B) {
			source := strings.Repeat("# α😀\r\nfn answer() Int: 42\r\n", n)
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				positions := newSourcePositions(source)
				for at := 0; at < len(source); at += 30 {
					benchmarkPosition = positions.position(at)
				}
			}
		})
	}
}

func BenchmarkPositionLongLine(b *testing.B) {
	for _, unit := range []string{"a", "😀"} {
		b.Run(unit, func(b *testing.B) {
			source := strings.Repeat(unit, 8192)
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				benchmarkPosition = Position(source, len(source))
			}
		})
	}
}
