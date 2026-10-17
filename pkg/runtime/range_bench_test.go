package msruntime

import "testing"

func BenchmarkCollectionsRangeBy(b *testing.B) {
	ctx := RootExecution()
	for _, tt := range []struct {
		name             string
		start, end, step int
		count            int
	}{
		{"empty", 0, 0, 1, 0},
		{"8", 0, 16, 2, 8},
		{"1024", 0, 2048, 2, 1024},
		{"65536", 0, 131072, 2, 65536},
		{"descending-65536", 131072, 0, -2, 65536},
	} {
		b.Run(tt.name, func(b *testing.B) {
			b.ReportAllocs()
			for b.Loop() {
				result := Collections_RangeBy(ctx, tt.start, tt.end, tt.step, Some(tt.count))
				if result.Failed || len(result.Val.Items) != tt.count {
					b.Fatal(result)
				}
			}
		})
	}
}
