package msruntime

import (
	"strings"
	"testing"
)

func BenchmarkStringCollections(b *testing.B) {
	for _, tt := range []struct {
		name, text   string
		chars, lines int
	}{
		{"empty", "", 0, 0},
		{"short", "aé🙂\nb", 5, 2},
		{"long", strings.Repeat("aé🙂\nb\n", 256), 1536, 512},
	} {
		b.Run(tt.name, func(b *testing.B) {
			b.Run("ScalarValues", func(b *testing.B) {
				b.ReportAllocs()
				for i := 0; i < b.N; i++ {
					if got := len(String_ScalarValues(tctx, tt.text).Items); got != tt.chars {
						b.Fatalf("got %d scalars, want %d", got, tt.chars)
					}
				}
			})
			b.Run("Chars", func(b *testing.B) {
				b.ReportAllocs()
				for i := 0; i < b.N; i++ {
					if got := len(String_Chars(tctx, tt.text).Items); got != tt.chars {
						b.Fatalf("got %d characters, want %d", got, tt.chars)
					}
				}
			})
			b.Run("Lines", func(b *testing.B) {
				b.ReportAllocs()
				for i := 0; i < b.N; i++ {
					if got := len(String_Lines(tctx, tt.text).Items); got != tt.lines {
						b.Fatalf("got %d lines, want %d", got, tt.lines)
					}
				}
			})
		})
	}
}
