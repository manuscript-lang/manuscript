package msruntime

import "testing"

func BenchmarkSourceCallDispatch(b *testing.B) {
	ctx := RootExecution()
	var callee Value = NewSourceFunction([]string{"a", "b"}, "Int", "benchmark.ms:1:1", func(_ *Execution, args []Value) Value {
		return IntAdd(IntValue(args[0]), IntValue(args[1]))
	})
	b.Run("Named", func(b *testing.B) {
		b.ReportAllocs()
		for b.Loop() {
			if value := Invoke(ctx, callee, []Argument{{"a", int64(300)}, {"b", int64(301)}}); value != int64(601) {
				b.Fatal(value)
			}
		}
	})
	b.Run("Prepared", func(b *testing.B) {
		b.ReportAllocs()
		for b.Loop() {
			if value := callee.(Function).Body(ctx, []Value{int64(300), int64(301)}); value != int64(601) {
				b.Fatal(value)
			}
		}
	})
}

func BenchmarkSourceDirectDispatch(b *testing.B) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	direct := SourceDirect("benchmark.ms:1:1", "Int", func(_ *Execution, receiver Value, args []Value) Value {
		return IntAdd(receiver.(int64), args[0].(int64))
	})
	args := []Value{int64(301)}
	b.ReportAllocs()
	for b.Loop() {
		if value := direct(ctx, int64(300), args); value != int64(601) {
			b.Fatal(value)
		}
	}
}
