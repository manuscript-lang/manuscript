package msruntime

import (
	"fmt"
	"testing"
)

var clonedMap *Map[int, int]
var clonedSet *Set[int]

func BenchmarkCollectionClone(b *testing.B) {
	for _, n := range []int{0, 1, 32, 1024} {
		m, s := NewMap[int, int](), NewSet[int]()
		for i := 0; i < n; i++ {
			m.Put(i, i)
			s.Add(i)
		}
		b.Run(fmt.Sprintf("Map/%d", n), func(b *testing.B) {
			b.ReportAllocs()
			for i := 0; i < b.N; i++ {
				clonedMap = Map_Clone(tctx, m)
			}
		})
		b.Run(fmt.Sprintf("Set/%d", n), func(b *testing.B) {
			b.ReportAllocs()
			for i := 0; i < b.N; i++ {
				clonedSet = Set_Clone(tctx, s)
			}
		})
	}
}
