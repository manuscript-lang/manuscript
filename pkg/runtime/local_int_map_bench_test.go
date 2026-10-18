package msruntime

import "testing"

var localIntMapBenchSink int

// The batch includes construction/growth and consumes every lookup. Raw Go is
// an ordinary map control; ordered maps retain their full public semantics.
func BenchmarkLocalIntMapBatch(b *testing.B) {
	for _, version := range []string{"Go", "Ordered", "ClosedLocal"} {
		b.Run(version, func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				sum := 0
				switch version {
				case "Go":
					m := make(map[int]int)
					for i := 0; i < 8000; i++ {
						m[i] = i * 2
					}
					for i := 0; i < 8000; i++ {
						sum += m[i]
					}
				case "Ordered":
					m := NewMap[int, int]()
					for i := 0; i < 8000; i++ {
						Map_Add(tctx, m, i, i*2)
					}
					for i := 0; i < 8000; i++ {
						sum += Map_Get(tctx, m, i).Val
					}
				case "ClosedLocal":
					m := NewLocalIntMap()
					for i := 0; i < 8000; i++ {
						LocalIntMap_Add(tctx, m, i, i*2)
					}
					for i := 0; i < 8000; i++ {
						sum += LocalIntMap_Get(tctx, m, i).Val
					}
				}
				if sum != 63992000 {
					b.Fatalf("checksum %d", sum)
				}
				localIntMapBenchSink = sum
			}
		})
	}
}
