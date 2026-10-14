package msruntime

import (
	"reflect"
	"testing"
)

func TestListParityPrimitiveStorage(t *testing.T) {
	for _, test := range []struct {
		typ    string
		values []Value
		less   func(Value, Value) bool
	}{
		{"Int", []Value{int64(3), int64(1), int64(3)}, func(a, b Value) bool { return a.(int64) < b.(int64) }},
		{"Float", []Value{3.5, 1.5, 3.5}, func(a, b Value) bool { return a.(float64) < b.(float64) }},
		{"Bool", []Value{true, false, true}, func(a, b Value) bool { return !a.(bool) && b.(bool) }},
		{"String", []Value{"é", "a", "é"}, func(a, b Value) bool { return a.(string) < b.(string) }},
	} {
		t.Run(test.typ, func(t *testing.T) {
			typ := "@std/List[" + test.typ + "]"
			input := NewList(typ, test.values)
			kind := input.kind
			if kind == listBoxed || input.Items != nil {
				t.Fatal("fixture is not authoritative primitive storage")
			}
			predicate := NewFunction([]string{"value"}, "Bool", func(_ *Execution, args []Value) Value { return args[0] == test.values[0] })
			compare := NewFunction([]string{"left", "right"}, "Int", func(_ *Execution, args []Value) Value {
				if test.less(args[0], args[1]) {
					return int64(-1)
				}
				if test.less(args[1], args[0]) {
					return int64(1)
				}
				return int64(0)
			})
			ctx := RootExecution()
			if listParityCall(ctx, "count", "Int", input, predicate) != int64(2) {
				t.Fatal("count skipped typed values")
			}
			distinct := listParityCall(ctx, "distinct", typ, input).(*List)
			if distinct == input || distinct.kind != kind || distinct.Items != nil || !reflect.DeepEqual(distinct.Boxed(), test.values[:2]) {
				t.Fatal("distinct lost typed fresh storage or order")
			}
			partition := listParityCall(ctx, "partition", "@std/ListPartition["+test.typ+"]", input, predicate).(Record)
			for field, want := range map[string][]Value{"matching": {test.values[0], test.values[2]}, "remaining": {test.values[1]}} {
				got := partition.Fields[field].(*List)
				if got == input || got.kind != kind || got.Items != nil || !reflect.DeepEqual(got.Boxed(), want) {
					t.Fatalf("partition %s lost storage or values", field)
				}
			}
			for name, want := range map[string]Value{"min": test.values[1], "max": test.values[0]} {
				got := listParityCall(ctx, name, "@std/Optional["+test.typ+"]", input, compare).(Alternative)
				if got.Tag != "some" || got.Fields[0] != want {
					t.Fatalf("%s skipped typed values: %#v", name, got)
				}
			}
			zipped := listParityCall(ctx, "zip", "@std/List[@std/ListPair["+test.typ+"]["+test.typ+"]]", input, distinct).(*List)
			if zipped.Len() != 2 || zipped.Get(1).(Record).Fields["first"] != test.values[1] {
				t.Fatal("zip skipped primitive backing")
			}
			if listParityCall(ctx, "insert", typ, input, int64(input.Len()), test.values[1]) != input || input.kind != kind {
				t.Fatal("insert lost header/storage identity")
			}
			captured, capacity := input.Capture(), input.Cap()
			popped := listParityCall(ctx, "pop", "@std/Optional["+test.typ+"]", input).(Alternative)
			if popped.Fields[0] != test.values[1] || input.Len() != 3 || captured.Get(3) != test.values[1] || input.Cap() != capacity || input.kind != kind {
				t.Fatal("pop lost captured tail or primitive backing")
			}
			if listParityCall(ctx, "sort_in_place", typ, input, compare) != input || input.kind != kind || !reflect.DeepEqual(input.Boxed(), []Value{test.values[1], test.values[0], test.values[2]}) {
				t.Fatal("typed in-place sort lost identity or order")
			}
			distinct.Set(0, test.values[1])
			if input.Get(1) != test.values[0] {
				t.Fatal("fresh output aliases input backing")
			}
		})
	}
}

func TestListParityTypedCapturedHeaderMatchesGoRange(t *testing.T) {
	for _, name := range []string{"count", "partition"} {
		for _, mutation := range []string{"pop", "append spare", "append reallocate", "insert spare"} {
			t.Run(name+"/"+mutation, func(t *testing.T) {
				capacity := 3
				if mutation == "append spare" || mutation == "insert spare" {
					capacity = 6
				}
				oracle := make([]int64, 3, capacity)
				copy(oracle, []int64{1, 2, 3})
				var want []int64
				for _, v := range oracle {
					want = append(want, v)
					if len(want) == 1 {
						switch mutation {
						case "pop":
							oracle = oracle[:len(oracle)-1]
						case "insert spare":
							oracle = append(oracle, 0)
							copy(oracle[2:], oracle[1:])
							oracle[1] = 7
						default:
							oracle = append(oracle, 4)
							oracle[1] = 20
						}
					}
				}
				backing := make([]int64, 3, capacity)
				copy(backing, []int64{1, 2, 3})
				input := &List{Type: "@std/List[Int]", kind: listInt, ints: backing}
				var seen []int64
				predicate := NewFunction([]string{"value"}, "Bool", func(ctx *Execution, args []Value) Value {
					seen = append(seen, args[0].(int64))
					if len(seen) == 1 {
						switch mutation {
						case "pop":
							listParityCall(ctx, "pop", "@std/Optional[Int]", input)
						case "insert spare":
							listParityCall(ctx, "insert", input.Type, input, int64(1), int64(7))
						default:
							input.Append(int64(4))
							input.Set(1, int64(20))
						}
					}
					return true
				})
				result := "Int"
				if name == "partition" {
					result = "@std/ListPartition[Int]"
				}
				got := listParityCall(RootExecution(), name, result, input, predicate)
				if !reflect.DeepEqual(seen, want) {
					t.Fatalf("captured values=%v, Go range=%v", seen, want)
				}
				if name == "partition" {
					output := got.(Record).Fields["matching"].(*List)
					expected := make([]Value, len(want))
					for i, v := range want {
						expected[i] = v
					}
					if output.kind != listInt || !reflect.DeepEqual(output.Boxed(), expected) {
						t.Fatal("partition reread mutated payload or lost primitive backing")
					}
				}
			})
		}
	}
}
