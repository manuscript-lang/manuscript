package msruntime

import "testing"

func benchCollectionContext() *Execution { return RootExecution() }

func BenchmarkMapPutGetInt(b *testing.B) {
	ctx := benchCollectionContext()
	const n = 8000
	for b.Loop() {
		m := &Map{Type: "@std/Map[Int][Int]"}
		for i := int32(0); i < n; i++ {
			mapPut(ctx, m, i, i)
		}
		for i := int32(0); i < n; i++ {
			if m.find(ctx, i) < 0 {
				b.Fatal("missing key")
			}
		}
	}
}

func BenchmarkSetAddString(b *testing.B) {
	ctx := benchCollectionContext()
	keys := make([]Value, 8000)
	for i := range keys {
		keys[i] = "key-" + Format(int32(i))
	}
	for b.Loop() {
		s := &Set{Type: "@std/Set[String]"}
		for _, k := range keys {
			s.add(ctx, k)
		}
	}
}

func BenchmarkEqualInt(b *testing.B) {
	ctx := benchCollectionContext()
	for b.Loop() {
		EqualIn(ctx, int32(1), int32(2))
	}
}
