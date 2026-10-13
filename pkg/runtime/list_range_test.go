package msruntime

import (
	"context"
	"reflect"
	"slices"
	"testing"
)

// The reference uses ordinary Go slice mutation, independent of runtime writers.
func TestListTraversalMatchesGoRange(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	for _, test := range []struct {
		name   string
		op     string
		args   []Argument
		mutate func([]Value) []Value
	}{
		{"replace", "with_value", []Argument{{"index", int64(1)}, {"value", int64(9)}}, func(v []Value) []Value { v[1] = int64(9); return v }},
		{"fill", "fill", []Argument{{"value", int64(9)}, {"start", int64(0)}, {"end", int64(3)}}, func(v []Value) []Value {
			for i := range v {
				v[i] = int64(9)
			}
			return v
		}},
		{"reverse", "reverse", nil, func(v []Value) []Value { slices.Reverse(v); return v }},
		{"prepend", "prepend", []Argument{{"value", int64(9)}}, func(v []Value) []Value { v = append(v, nil); copy(v[1:], v[:len(v)-1]); v[0] = int64(9); return v }},
		{"remove", "without", []Argument{{"index", int64(0)}}, func(v []Value) []Value { return append(v[:0], v[1:]...) }},
		{"copy backward", "copy_within", []Argument{{"target", int64(0)}, {"start", int64(1)}, {"end", int64(3)}}, func(v []Value) []Value { copy(v, v[1:3]); return v }},
		{"copy truncated", "copy_within", []Argument{{"target", int64(2)}, {"start", int64(0)}, {"end", int64(3)}}, func(v []Value) []Value { copy(v[2:], v[:3]); return v }},
		{"splice shrink", "with_values", []Argument{{"start", int64(1)}, {"delete_count", int64(2)}, {"replacement", &List{Type: "@std/List[Int]", Items: []Value{int64(9)}}}}, func(v []Value) []Value { v[1] = int64(9); return v[:2] }},
	} {
		for _, capacity := range []int{3, 8} {
			for _, callback := range []bool{false, true} {
				t.Run(test.name+Format(int64(capacity))+Format(callback), func(t *testing.T) {
					initial := []Value{int64(1), int64(2), int64(3)}
					ref := make([]Value, len(initial), capacity)
					copy(ref, initial)
					var want []Value
					for _, v := range ref {
						want = append(want, v)
						if len(want) == 1 {
							ref = test.mutate(ref)
						}
					}
					list := &List{Type: "@std/List[Int]", Items: make([]Value, len(initial), capacity)}
					copy(list.Items, initial)
					alias := list
					writer := NativeMember(list, test.op)
					var seen []Value
					visit := func(v Value) {
						seen = append(seen, v)
						if len(seen) == 1 {
							if Invoke(ctx, writer, test.args) != alias {
								t.Fatal("mutation lost receiver")
							}
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
					if !reflect.DeepEqual(seen, want) || !reflect.DeepEqual(alias.Items, ref) {
						t.Fatalf("seen %v / %v; contents %v / %v", seen, want, alias.Items, ref)
					}
				})
			}
		}
	}
}

func TestListRangeAppendAndSelfSplice(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	for _, capacity := range []int{3, 8} {
		for _, splice := range []bool{false, true} {
			initial := []Value{int64(1), int64(2), int64(3)}
			ref := make([]Value, 3, capacity)
			copy(ref, initial)
			var want []Value
			for _, v := range ref {
				want = append(want, v)
				if len(want) == 1 {
					if splice {
						replacement := slices.Clone(ref)
						old := len(ref)
						ref = slices.Grow(ref, 2)[:5]
						copy(ref[4:], ref[2:old])
						copy(ref[1:], replacement)
					} else {
						ref = append(ref, int64(4))
						ref[1] = int64(9)
					}
				}
			}
			list := &List{Type: "@std/List[Int]", Items: make([]Value, 3, capacity)}
			copy(list.Items, initial)
			var seen []Value
			for _, v := range Iterate(list) {
				seen = append(seen, v)
				if len(seen) == 1 {
					if splice {
						Invoke(ctx, NativeMember(list, "with_values"), []Argument{{"start", int64(1)}, {"delete_count", int64(1)}, {"replacement", list}})
					} else {
						ListAppend(ctx, list, int64(4))
						Invoke(ctx, NativeMember(list, "with_value"), []Argument{{"index", int64(1)}, {"value", int64(9)}})
					}
				}
			}
			if !reflect.DeepEqual(seen, want) || !reflect.DeepEqual(list.Items, ref) || len(seen) != 3 {
				t.Fatalf("cap %d splice %v: %v/%v, %v/%v", capacity, splice, seen, want, list.Items, ref)
			}
		}
	}
}

func TestListRangeNestedAndCallbackExits(t *testing.T) {
	for _, exit := range []string{"normal", "fault", "cancel"} {
		t.Run(exit, func(t *testing.T) {
			ctx := RootExecution()
			var cancel context.CancelFunc
			ctx.Context, cancel = context.WithCancel(ctx.Context)
			defer cancel()
			defer FinishExecution(ctx)
			list := &List{Type: "@std/List[Int]", Items: []Value{int64(1), int64(2), int64(3)}}
			var seen, inner []Value
			cb := NewFunction([]string{"value"}, "Unit", func(ctx *Execution, a []Value) Value {
				seen = append(seen, a[0])
				if len(seen) == 1 {
					Invoke(ctx, NativeMember(list, "fill"), []Argument{{"value", int64(9)}, {"start", int64(0)}, {"end", int64(3)}})
					//lint:ignore S1011 Exercise a nested Go range explicitly.
					for _, v := range Iterate(list) {
						inner = append(inner, v)
					}
					if exit == "fault" {
						return Panic("callback fault")
					}
					if exit == "cancel" {
						cancel()
					}
				}
				return Unit{}
			})
			failure := recovered(func() { Invoke(ctx, NativeMember(list, "for_each"), []Argument{{"operation", cb}}) })
			if exit == "normal" {
				if failure != nil || !reflect.DeepEqual(seen, []Value{int64(1), int64(9), int64(9)}) {
					t.Fatal(seen, failure)
				}
			} else {
				if failure == nil || !reflect.DeepEqual(seen, []Value{int64(1)}) {
					t.Fatal(seen, failure)
				}
				if exit == "fault" && failure.(Fault).Message != "callback fault" {
					t.Fatal(failure)
				}
				if exit == "cancel" && !reflect.DeepEqual(failure, recovered(func() { CheckCancelled(ctx) })) {
					t.Fatal("cancellation changed")
				}
			}
			if !reflect.DeepEqual(inner, []Value{int64(9), int64(9), int64(9)}) {
				t.Fatal("nested range missed backing updates")
			}
		})
	}
}

func TestListCallbackTraversalsUseCapturedBacking(t *testing.T) {
	for _, name := range []string{"map", "filter", "fold", "fold_right", "find", "find_last", "find_index", "find_last_index", "some", "every", "for_each", "flat_map", "group_by"} {
		t.Run(name, func(t *testing.T) {
			run := func(reference bool) (Value, []Value, []Value) {
				ctx := RootExecution()
				defer FinishExecution(ctx)
				list := &List{Type: "@std/List[Int]", Items: []Value{int64(1), int64(2), int64(3)}}
				var seen []Value
				labels, result := []string{"value"}, "@std/List[Int]"
				if name == "fold" || name == "fold_right" {
					labels, result = []string{"accumulator", "value"}, "Int"
				}
				cb := NewFunction(labels, "Int", func(ctx *Execution, a []Value) Value {
					v := a[len(a)-1].(int64)
					seen = append(seen, v)
					Invoke(ctx, NativeMember(list, "fill"), []Argument{{"value", int64(9)}, {"start", int64(0)}, {"end", int64(3)}})
					ListAppend(ctx, list, int64(4))
					switch name {
					case "filter", "find", "find_last", "find_index", "find_last_index", "some", "every":
						return v%2 == 1
					case "fold", "fold_right":
						return a[0].(int64)*10 + v
					case "for_each":
						return Unit{}
					case "flat_map":
						return &List{Type: list.Type, Items: []Value{v, v}}
					case "group_by":
						return v % 2
					default:
						return v * 2
					}
				})
				switch name {
				case "find", "find_last", "find_index", "find_last_index":
					result = "@std/Optional[Int]"
				case "some", "every":
					result = "Bool"
				case "for_each":
					result = "Unit"
				case "group_by":
					result = "@std/Map[Int][@std/List[Int]]"
				}
				a := []Value{list, cb}
				if name == "fold" || name == "fold_right" {
					a = []Value{list, int64(0), cb}
				}
				spec := libraryFunctions["collections/"+name]
				var out Value
				if reference {
					out = spec.Body(ctx, result, a)
				} else {
					out = invokeLibrary(spec, ctx, result, a)
				}
				return out, seen, list.Items
			}
			want, ws, wi := run(true)
			got, gs, gi := run(false)
			if !Equal(got, want) || !reflect.DeepEqual(gs, ws) || !reflect.DeepEqual(gi, wi) {
				t.Fatal("native boundary copied or changed traversal", gs, ws)
			}
		})
	}
}

func TestListTraversalDoesNotAllocateOrMutateHeader(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	list := &List{Type: "@std/List[Int]", Items: make([]Value, 0, 8)}
	fn := NewFunction([]string{"value"}, "Unit", func(*Execution, []Value) Value { return Unit{} })
	args := []Value{list, fn}
	spec := libraryFunctions["collections/for_each"]
	if n := testing.AllocsPerRun(100, func() { listRangeBenchmarkSink = CaptureList(list); invokeLibrary(spec, ctx, "Unit", args) }); n != 0 {
		t.Fatalf("traversal allocates %v", n)
	}
	if len(list.Items) != 0 || cap(list.Items) != 8 {
		t.Fatal("traversal changed receiver header")
	}
}

func BenchmarkListRangeCapture(b *testing.B) {
	list := &List{Type: "@std/List[Int]", Items: make([]Value, 65536)}
	b.ReportAllocs()
	for b.Loop() {
		listRangeBenchmarkSink = CaptureList(list)
	}
}

var listRangeBenchmarkSink ListRange
