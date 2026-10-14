package msruntime

import "testing"

func benchCollectionContext() *Execution { return RootExecution() }

func BenchmarkMapPutGetInt(b *testing.B) {
	ctx := benchCollectionContext()
	const n = 8000
	for b.Loop() {
		m := &Map{Type: "@std/Map[Int][Int]"}
		for i := int64(0); i < n; i++ {
			mapPut(ctx, m, i, i)
		}
		for i := int64(0); i < n; i++ {
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
		keys[i] = "key-" + Format(int64(i))
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
		EqualIn(ctx, int64(1), int64(2))
	}
}

func BenchmarkMapRemoveFront(b *testing.B) {
	ctx := RootExecution()
	for i := 0; i < b.N; i++ {
		m := &Map{Type: "@std/Map[@std/Equal][Int]"}
		for k := int64(0); k < 20000; k++ {
			m.put(ctx, k, k)
		}
		for k := int64(0); k < 20000; k++ {
			m.removeAt(ctx, m.find(ctx, k))
		}
	}
}
