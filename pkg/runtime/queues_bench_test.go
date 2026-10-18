package msruntime

import (
	"strconv"
	"testing"
)

// The queue stays at size n: dequeue follows a full heap path and enqueue
// restores the maximum. Setup and construction allocations are excluded.
func BenchmarkPriorityQueueCycle(b *testing.B) {
	for _, n := range []int{1, 16, 1024, 65536} {
		b.Run(strconv.Itoa(n), func(b *testing.B) {
			ctx := RootExecution()
			q := NewPriorityQueue(func(_ *Execution, a, z int) int {
				if a < z {
					return -1
				}
				if a > z {
					return 1
				}
				return 0
			}, None[int]())
			for i := 0; i < n; i++ {
				PriorityQueue_Enqueue(ctx, q, i)
			}
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				if !PriorityQueue_Dequeue(ctx, q).Some {
					b.Fatal("empty queue")
				}
				PriorityQueue_Enqueue(ctx, q, n+i)
			}
		})
	}
}

// Equal priorities exercise stable sequence tie breaking at every level.
func BenchmarkPriorityQueueEqualPriorities(b *testing.B) {
	ctx := RootExecution()
	q := NewPriorityQueue(func(*Execution, int, int) int { return 0 }, None[int]())
	for i := 0; i < 1024; i++ {
		PriorityQueue_Enqueue(ctx, q, i)
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		v := PriorityQueue_Dequeue(ctx, q)
		PriorityQueue_Enqueue(ctx, q, v.Val)
	}
}

// Empty dequeue is a negative control with no path or payload allocation.
func BenchmarkPriorityQueueEmpty(b *testing.B) {
	q := NewPriorityQueue(func(*Execution, int, int) int { return 0 }, None[int]())
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		if PriorityQueue_Dequeue(nil, q).Some {
			b.Fatal("nonempty queue")
		}
	}
}
