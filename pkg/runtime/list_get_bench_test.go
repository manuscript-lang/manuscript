package msruntime

import "testing"

var benchmarkListGetSink int

// Keep both wrappers visible to ordinary caller inlining. This measures the
// complete List.get(...) path, including bounds checks.
func BenchmarkListGetVsGo(b *testing.B) {
	b.Run("Manuscript", func(b *testing.B) {
		values := NewList(1, 2, 3, 4, 5, 6, 7, 8)
		b.ReportAllocs()
		b.ResetTimer()
		sum := 0
		for n := 0; n < b.N; n++ {
			sum += List_Get(nil, values, n&7, None[int]())
		}
		benchmarkListGetSink = sum
	})
	b.Run("Go", func(b *testing.B) {
		values := []int{1, 2, 3, 4, 5, 6, 7, 8}
		b.ReportAllocs()
		b.ResetTimer()
		sum := 0
		for n := 0; n < b.N; n++ {
			sum += values[n&7]
		}
		benchmarkListGetSink = sum
	})
}

func BenchmarkListGetPaths(b *testing.B) {
	for _, tc := range []struct {
		name  string
		start int
	}{
		{"positive", 0},
		{"negative", -8},
		{"default positive", 8},
		{"default negative", -16},
	} {
		b.Run(tc.name, func(b *testing.B) {
			values := NewList(1, 2, 3, 4, 5, 6, 7, 8)
			b.ReportAllocs()
			b.ResetTimer()
			sum := 0
			for n := 0; n < b.N; n++ {
				sum += List_Get(nil, values, tc.start+(n&7), Some(9))
			}
			benchmarkListGetSink = sum
		})
	}
}
