package msruntime

import (
	"strings"
	"testing"
)

var scalarString Result[string, StringError]

func BenchmarkStringFromScalars(b *testing.B) {
	for _, tt := range []struct{ name, text string }{
		{"empty", ""}, {"short", "aé🙂"},
		{"ASCII", strings.Repeat("a", 4096)}, {"Unicode", strings.Repeat("🙂", 4096)},
	} {
		values := String_ScalarValues(tctx, tt.text)
		b.Run(tt.name, func(b *testing.B) {
			b.ReportAllocs()
			for i := 0; i < b.N; i++ {
				scalarString = String_FromScalars(tctx, values)
			}
		})
	}
}
