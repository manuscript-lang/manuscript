package msruntime

import "testing"

func sortBenchData(n int) []int {
	out := make([]int, n)
	for i := range out {
		out[i] = (i * 7919) % 10007
	}
	return out
}

func BenchmarkSortStable100k(b *testing.B) {
	data := sortBenchData(100000)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		items := append([]int(nil), data...)
		sortStable(items, func(a, b int) bool { return a < b })
	}
}

func TestSortStableIsStableAndOrdered(t *testing.T) {
	type pair struct{ key, seq int }
	for _, n := range []int{0, 1, 2, 11, 12, 13, 100, 1000, 4097} {
		items := make([]pair, n)
		for i := range items {
			items[i] = pair{key: (i * 7919) % 17, seq: i}
		}
		sortStable(items, func(a, b pair) bool { return a.key < b.key })
		for i := 1; i < n; i++ {
			a, b := items[i-1], items[i]
			if a.key > b.key || a.key == b.key && a.seq > b.seq {
				t.Fatalf("n=%d: out of order at %d: %v %v", n, i, a, b)
			}
		}
	}
}
