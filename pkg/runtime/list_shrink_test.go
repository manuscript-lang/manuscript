package msruntime

import (
	"reflect"
	"testing"
)

func TestListShrinkingRetainsTypedGoValues(t *testing.T) {
	t.Run("Int", func(t *testing.T) {
		testListShrinking(t, "Int", []int64{1, 2, 3}, int64(9), func(v int64) Value { return v + 1 })
	})
	t.Run("Float", func(t *testing.T) {
		testListShrinking(t, "Float", []float64{1.5, 2.5, 3.5}, 9.5, func(v float64) Value { return v + 1 })
	})
	t.Run("String", func(t *testing.T) {
		testListShrinking(t, "String", []string{"a", "bb", "ccc"}, "replacement", func(v string) Value { return len(v) })
	})
	record := func(n int64) *Record { return &Record{Type: "Payload", Fields: map[string]Value{"value": n}} }
	t.Run("record", func(t *testing.T) {
		testListShrinking(t, "Payload", []*Record{record(1), record(2), record(3)}, record(9), func(v *Record) Value { return v.Fields["value"].(int64) + 1 })
	})
	alternative := func(n int64) Alternative { return Alternative{Type: "Choice", Tag: "item", Fields: []Value{n}} }
	t.Run("alternative", func(t *testing.T) {
		testListShrinking(t, "Choice", []Alternative{alternative(1), alternative(2), alternative(3)}, alternative(9), func(v Alternative) Value { return v.Fields[0].(int64) + 1 })
	})
	inner := func(n int64) *List { return &List{Type: "@std/List[Int]", Items: []Value{n}} }
	t.Run("nested", func(t *testing.T) {
		testListShrinking(t, "@std/List[Int]", []*List{inner(1), inner(2), inner(3)}, inner(9), func(v *List) Value { return v.Items[0].(int64) + 1 })
	})
}

func testListShrinking[T any](t *testing.T, typ string, initial []T, replacement T, consume func(T) Value) {
	t.Helper()
	for _, capacity := range []int{3, 8} {
		for _, callback := range []bool{false, true} {
			for _, mode := range []string{"remove", "splice", "clear", "clear append", "reset append"} {
				t.Run(mode+Format(int64(capacity))+Format(callback), func(t *testing.T) {
					ctx := RootExecution()
					defer FinishExecution(ctx)
					ref := make([]T, len(initial), capacity)
					copy(ref, initial)
					var want []Value
					for _, v := range ref {
						want = append(want, consume(v))
						if len(want) == 1 {
							switch mode {
							case "remove":
								ref = append(ref[:0], ref[1:]...)
							case "splice":
								ref = append(ref[:1], replacement)
							case "clear":
								ref = ref[:0]
							case "clear append":
								ref = append(ref[:0], replacement, replacement)
							case "reset append":
								ref = nil
								ref = append(ref, replacement, replacement)
							}
						}
					}
					list := &List{Type: "@std/List[" + typ + "]", Items: make([]Value, len(initial), capacity)}
					for i, v := range initial {
						list.Items[i] = v
					}
					alias, clone := list, Clone(list).(*List)
					var seen []Value
					visit := func(v Value) {
						seen = append(seen, consume(v.(T)))
						if len(seen) != 1 {
							return
						}
						var result Value = alias
						switch mode {
						case "remove":
							result = Invoke(ctx, NativeMember(list, "without"), []Argument{{"index", int64(0)}})
						case "splice", "clear", "clear append":
							start, count, items := int64(0), int64(3), []Value(nil)
							if mode == "splice" {
								start, count, items = 1, 2, []Value{replacement}
							}
							result = Invoke(ctx, NativeMember(list, "with_values"), []Argument{{"start", start}, {"delete_count", count}, {"replacement", &List{Type: list.Type, Items: items}}})
							if mode == "clear append" {
								ListAppend(ctx, list, replacement)
								ListAppend(ctx, list, replacement)
							}
						case "reset append":
							list.Items = nil // An external Go header reset releases receiver backing.
							ListAppend(ctx, list, replacement)
							ListAppend(ctx, list, replacement)
						}
						if result != alias {
							t.Fatal("mutation lost receiver identity")
						}
					}
					if callback {
						fn := NewFunction([]string{"value"}, "Unit", func(_ *Execution, a []Value) Value { visit(a[0]); return Unit{} })
						Invoke(ctx, NativeMember(list, "for_each"), []Argument{{"operation", fn}})
					} else {
						for _, v := range Iterate(list) {
							visit(v)
						}
					}
					if !reflect.DeepEqual(seen, want) || len(seen) != len(initial) || len(alias.Items) != len(ref) {
						t.Fatalf("observed %v, want %v; receiver length %d/%d", seen, want, len(alias.Items), len(ref))
					}
					for i, v := range ref {
						if !reflect.DeepEqual(alias.Items[i], v) {
							t.Fatal("receiver diverged from Go slice")
						}
					}
					for i, v := range initial {
						if !reflect.DeepEqual(clone.Items[i], v) {
							t.Fatal("explicit clone outer storage changed")
						}
					}
					if mode == "clear" && cap(list.Items) != capacity {
						t.Fatal("splice-to-empty released capacity")
					}
				})
			}
		}
	}
}
