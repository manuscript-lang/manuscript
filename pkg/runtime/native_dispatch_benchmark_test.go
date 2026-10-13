package msruntime

import "testing"

// Match generated native member calls, including their lexical type scopes.
func BenchmarkNativeListAtUnwrap(b *testing.B) {
	ctx := RootExecution()
	list := &List{Type: "@std/List[Int]", Items: []Value{int64(42)}}
	scope := TypeScope{Args: []TypeScope{{}}}
	b.ReportAllocs()
	for b.Loop() {
		item := Invoke(ctx, NativeMemberResult(list, "at", "@std/Optional[Int]", scope), []Argument{{"index", int64(0)}})
		value := Invoke(ctx, NativeMemberResult(item, "unwrap", "Int", scope), nil)
		if value != int64(42) {
			b.Fatal(value)
		}
	}
}

func BenchmarkDirectListAtUnwrap(b *testing.B) {
	ctx := RootExecution()
	list := &List{Type: "@std/List[Int]", Items: []Value{int64(42)}}
	b.ReportAllocs()
	for b.Loop() {
		item := ListAt(ctx, list, int64(0), "@std/Optional[Int]")
		if value := OptionalUnwrap(ctx, item); value != int64(42) {
			b.Fatal(value)
		}
	}
}
