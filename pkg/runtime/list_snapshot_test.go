package msruntime

import (
	"context"
	"reflect"
	"testing"
)

func TestListSnapshotsDetachEveryInPlaceMutation(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	for _, test := range []struct {
		name string
		args []Argument
		want []Value
	}{
		{"append", []Argument{{"value", int64(4)}}, []Value{int64(1), int64(2), int64(3), int64(4)}},
		{"prepend", []Argument{{"value", int64(4)}}, []Value{int64(4), int64(1), int64(2), int64(3)}},
		{"with_value", []Argument{{"index", int64(-1)}, {"value", int64(4)}}, []Value{int64(1), int64(2), int64(4)}},
		{"without", []Argument{{"index", int64(0)}}, []Value{int64(2), int64(3)}},
		{"with_values", []Argument{{"start", int64(1)}, {"delete_count", int64(1)}, {"replacement", &List{Type: "@std/List[Int]", Items: []Value{int64(4), int64(5)}}}}, []Value{int64(1), int64(4), int64(5), int64(3)}},
		{"fill", []Argument{{"value", int64(4)}, {"start", int64(0)}, {"end", int64(3)}}, []Value{int64(4), int64(4), int64(4)}},
		{"copy_within", []Argument{{"target", int64(1)}, {"start", int64(0)}, {"end", int64(2)}}, []Value{int64(1), int64(1), int64(2)}},
		{"reverse", nil, []Value{int64(3), int64(2), int64(1)}},
	} {
		for _, kind := range []string{"loop", "callback"} {
			t.Run(test.name+"/"+kind, func(t *testing.T) {
				list := &List{Type: "@std/List[Int]", Items: make([]Value, 3, 8)}
				copy(list.Items, []Value{int64(1), int64(2), int64(3)})
				alias := list
				// Bind before snapshot/growth; the callable must keep the handle.
				operation := NativeMember(list, test.name)
				var snapshot []Value
				if kind == "loop" {
					snapshot = Iterate(list)
				} else {
					snapshot = list.snapshot().Items
				}
				if &snapshot[0] != &list.Items[0] || cap(snapshot) != len(snapshot) {
					t.Fatal("snapshot eagerly copied or exposed append capacity")
				}
				if Invoke(ctx, operation, test.args) != list || alias != list || !reflect.DeepEqual(alias.Items, test.want) {
					t.Fatalf("alias/result: %#v, want %#v", alias.Items, test.want)
				}
				if !reflect.DeepEqual(snapshot, []Value{int64(1), int64(2), int64(3)}) {
					t.Fatalf("snapshot changed: %#v", snapshot)
				}
			})
		}
	}
}

func TestListCallbackSnapshotReentryAndExits(t *testing.T) {
	for _, exit := range []string{"normal", "fault", "cancel"} {
		t.Run(exit, func(t *testing.T) {
			ctx := RootExecution()
			var cancel context.CancelFunc
			ctx.Context, cancel = context.WithCancel(ctx.Context)
			defer cancel()
			defer FinishExecution(ctx)
			child := NewRecord("Child", []Argument{{"value", int64(1)}})
			list := &List{Type: "@std/List[Child]", Items: []Value{child, child}}
			clone := Clone(list).(*List)
			var seen []Value
			operation := NewFunction([]string{"value"}, "Unit", func(ctx *Execution, args []Value) Value {
				value := args[0]
				seen = append(seen, Field(value, "value"))
				SetField(value, "value", Field(value, "value").(int64)+1)
				Invoke(ctx, NativeMember(list, "fill"), []Argument{{"value", NewRecord("Child", []Argument{{"value", int64(9)}})}, {"start", int64(0)}, {"end", int64(2)}})
				if len(seen) == 1 {
					inner := NewFunction([]string{"value"}, "Unit", func(ctx *Execution, args []Value) Value {
						Invoke(ctx, NativeMember(list, "reverse"), nil)
						return Unit{}
					})
					Invoke(ctx, NativeMember(list, "for_each"), []Argument{{"operation", inner}})
					if exit == "fault" {
						return Panic("callback fault")
					}
					if exit == "cancel" {
						cancel()
					}
				}
				return Unit{}
			})
			failure := recovered(func() {
				Invoke(ctx, NativeMember(list, "for_each"), []Argument{{"operation", operation}})
			})
			if exit == "normal" {
				if failure != nil || !reflect.DeepEqual(seen, []Value{int64(1), int64(2)}) || Field(child, "value") != int64(3) {
					t.Fatalf("snapshot reentry: seen=%v, failure=%v", seen, failure)
				}
			} else {
				if failure == nil || !reflect.DeepEqual(seen, []Value{int64(1)}) {
					t.Fatalf("callback exit: seen=%v, failure=%v", seen, failure)
				}
				if exit == "fault" && failure.(Fault).Message != "callback fault" {
					t.Fatal(failure)
				}
				if exit == "cancel" && !reflect.DeepEqual(failure, recovered(func() { CheckCancelled(ctx) })) {
					t.Fatal("cancellation identity changed")
				}
			}
			if Field(clone.Items[0], "value") != Field(child, "value") {
				t.Fatal("nested reference identity changed")
			}
		})
	}
}

func TestListCallbackTraversalsMatchIndependentClone(t *testing.T) {
	for _, name := range []string{"map", "filter", "fold", "fold_right", "find", "find_last", "find_index", "find_last_index", "some", "every", "for_each", "flat_map", "group_by"} {
		t.Run(name, func(t *testing.T) {
			run := func(legacy bool) (Value, []Value, []Value) {
				ctx := RootExecution()
				defer FinishExecution(ctx)
				list := &List{Type: "@std/List[Int]", Items: []Value{int64(1), int64(2), int64(3)}}
				var seen []Value
				labels, result := []string{"value"}, "@std/List[Int]"
				if name == "fold" || name == "fold_right" {
					labels, result = []string{"accumulator", "value"}, "Int"
				}
				callback := NewFunction(labels, "Int", func(ctx *Execution, args []Value) Value {
					value := args[len(args)-1].(int64)
					seen = append(seen, value)
					Invoke(ctx, NativeMember(list, "fill"), []Argument{{"value", int64(9)}, {"start", int64(0)}, {"end", int64(3)}})
					ListAppend(ctx, list, int64(4))
					switch name {
					case "filter", "find", "find_last", "find_index", "find_last_index", "some", "every":
						return value%2 == 1
					case "fold", "fold_right":
						return args[0].(int64)*10 + value
					case "for_each":
						return Unit{}
					case "flat_map":
						return &List{Type: list.Type, Items: []Value{value, value}}
					case "group_by":
						return value % 2
					default:
						return value * 2
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
				args := []Value{list, callback}
				if name == "fold" || name == "fold_right" {
					args = []Value{list, int64(0), callback}
				}
				spec := libraryFunctions["collections/"+name]
				var out Value
				if legacy {
					// Independent oracle: previous membership-copy implementation.
					args[0] = Clone(list)
					out = spec.Body(ctx, result, args)
				} else {
					out = invokeLibrary(spec, ctx, result, args)
				}
				return out, seen, list.Items
			}
			want, wantSeen, wantItems := run(true)
			got, seen, items := run(false)
			if !Equal(got, want) || !reflect.DeepEqual(seen, wantSeen) || !reflect.DeepEqual(items, wantItems) {
				t.Fatalf("callback traversal differs from membership copy: result=%v/%v, seen=%v/%v, items=%v/%v", got, want, seen, wantSeen, items, wantItems)
			}
		})
	}
}

func BenchmarkListCallbackMembershipSnapshot(b *testing.B) {
	list := &List{Type: "@std/List[Int]", Items: make([]Value, 65536)}
	b.ReportAllocs()
	for b.Loop() {
		listSnapshotBenchmarkSink = list.snapshot()
	}
}

var listSnapshotBenchmarkSink *List
