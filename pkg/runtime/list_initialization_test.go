package msruntime

import "testing"

func TestStrictPrimitiveListInitialization(t *testing.T) {
	for _, test := range []struct {
		name string
		new  func(int) *List
		init func(*List, int)
		want Value
	}{
		{"Int", func(n int) *List { return NewSizedIntList("@std/List[Int]", n) }, func(l *List, i int) { InitListInt(l, i, 10000) }, int64(10000)},
		{"Float", func(n int) *List { return NewSizedFloatList("@std/List[Float]", n) }, func(l *List, i int) { InitListFloat(l, i, 3.5) }, 3.5},
		{"Bool", func(n int) *List { return NewSizedBoolList("@std/List[Bool]", n) }, func(l *List, i int) { InitListBool(l, i, true) }, true},
		{"String", func(n int) *List { return NewSizedStringList("@std/List[String]", n) }, func(l *List, i int) { InitListString(l, i, "text") }, "text"},
	} {
		t.Run(test.name, func(t *testing.T) {
			list := test.new(2)
			test.init(list, 0)
			test.init(list, 1)
			FinishListInitialization(list)
			if list.Len() != 2 || list.Get(0) != test.want || list.Get(1) != test.want || list.Items != nil {
				t.Fatal("typed initializer changed backing or contents")
			}
			for name, call := range map[string]func(){
				"published": func() { test.init(list, 0) },
				"negative":  func() { test.init(test.new(2), -1) },
				"end":       func() { test.init(test.new(2), 2) },
				"empty":     func() { test.init(test.new(0), 0) },
				"boxed":     func() { test.init(NewSizedList("@std/List[Unit]", 2), 0) },
				"mismatch":  func() { test.init(NewSizedList("@std/List[Other]", 2), 0) },
			} {
				t.Run(name, func(t *testing.T) {
					if _, ok := recovered(call).(Fault); !ok {
						t.Fatal("invalid initialization accepted")
					}
				})
			}
			var sink *List
			if allocations := testing.AllocsPerRun(100, func() {
				fresh := test.new(4096)
				for i := 0; i < 4096; i++ {
					test.init(fresh, i)
				}
				sink = FinishListInitialization(fresh)
			}); allocations != 2 {
				t.Fatalf("fresh typed construction allocated %g, want 2", allocations)
			}
			if sink.Get(4095) != test.want {
				t.Fatal("allocation control lost its writes")
			}
		})
	}
	// Type-kind checks must reject another primitive kind as well as boxed data.
	for _, call := range []func(){
		func() { InitListInt(NewSizedFloatList("@std/List[Float]", 1), 0, 1) },
		func() { InitListFloat(NewSizedIntList("@std/List[Int]", 1), 0, 1) },
		func() { InitListBool(NewSizedStringList("@std/List[String]", 1), 0, true) },
		func() { InitListString(NewSizedBoolList("@std/List[Bool]", 1), 0, "text") },
	} {
		if _, ok := recovered(call).(Fault); !ok {
			t.Fatal("wrong primitive kind accepted")
		}
	}
}

var sizedListBenchmarkSink *List

func BenchmarkSizedIntListInitialization(b *testing.B) {
	b.ReportAllocs()
	for b.Loop() {
		list := NewSizedIntList("@std/List[Int]", 65536)
		for i := 0; i < 65536; i++ {
			InitListInt(list, i, int64(i)+10000)
		}
		sizedListBenchmarkSink = FinishListInitialization(list)
	}
}
