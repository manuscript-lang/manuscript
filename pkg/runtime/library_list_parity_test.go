package msruntime

import (
	"context"
	"math"
	"reflect"
	"testing"
)

func listParityCall(ctx *Execution, name, result string, args ...Value) Value {
	return libraryFunctions["collections/"+name].Body(ctx, result, args)
}

func listParityCompare() Function {
	return NewFunction([]string{"left", "right"}, "Int", func(_ *Execution, args []Value) Value {
		left, right := args[0].(int64), args[1].(int64)
		if left < right {
			return int64(-1)
		}
		if left > right {
			return int64(1)
		}
		return int64(0)
	})
}

func TestListParityCapturedQueries(t *testing.T) {
	for _, name := range []string{"count", "partition"} {
		for _, mutation := range []string{"pop", "append spare", "append reallocate"} {
			t.Run(name+"/"+mutation, func(t *testing.T) {
				capacity := 3
				if mutation == "append spare" {
					capacity = 6
				}
				items := make([]Value, 3, capacity)
				copy(items, []Value{int64(1), int64(2), int64(3)})
				list := &List{Type: "@std/List[Int]", Items: items}
				var seen []int64
				predicate := NewFunction([]string{"value"}, "Bool", func(ctx *Execution, args []Value) Value {
					value := args[0].(int64)
					seen = append(seen, value)
					if len(seen) == 1 {
						list.Items[0] = int64(9)
						if mutation == "pop" {
							listParityCall(ctx, "pop", "@std/Optional[Int]", list)
						} else {
							ListAppend(ctx, list, int64(4))
							list.Items[1] = int64(20)
						}
					}
					return value%2 != 0
				})
				result := "Int"
				if name == "partition" {
					result = "@std/ListPartition[Int]"
				}
				got := listParityCall(RootExecution(), name, result, list, predicate)
				wantSeen := []int64{1, 2, 3}
				remaining := int64(2)
				if mutation == "append spare" {
					wantSeen[1], remaining = 20, 20
				}
				if !reflect.DeepEqual(seen, wantSeen) {
					t.Fatalf("captured traversal = %v, want %v", seen, wantSeen)
				}
				if name == "count" {
					if got != int64(2) {
						t.Fatalf("count = %v", got)
					}
					return
				}
				partition := got.(Record)
				matching := partition.Fields["matching"].(*List)
				nonmatching := partition.Fields["remaining"].(*List)
				if partition.Type != result || matching.Type != list.Type || nonmatching.Type != list.Type || matching == list || nonmatching == list || matching == nonmatching {
					t.Fatal("partition lost record/list type or outer identity")
				}
				if !reflect.DeepEqual(matching.Boxed(), []Value{int64(1), int64(3)}) || !reflect.DeepEqual(nonmatching.Boxed(), []Value{remaining}) {
					t.Fatalf("partition reread payload after callback: %#v", partition)
				}
			})
		}
	}
}

func TestListParityZipAndPartitionShallowIdentity(t *testing.T) {
	payload := &List{Type: "@std/List[Int]", Items: []Value{int64(1)}}
	list := &List{Type: "@std/List[@std/List[Int]]", Items: []Value{payload, payload}}
	other := &List{Type: "@std/List[String]", Items: []Value{"a", "b", "c"}}
	result := "@std/List[@std/ListPair[@std/List[Int]][String]]"
	zip := listParityCall(RootExecution(), "zip", result, list, other).(*List)
	if zip == list || zip == other || zip.Type != result || len(zip.Items) != 2 {
		t.Fatal("zip length, type or outer identity")
	}
	pair := zip.Items[0].(Record)
	if pair.Type != typeArguments(result)[0] || pair.Fields["first"] != payload || pair.Fields["second"] != "a" {
		t.Fatal("zip lost full generic identity or payload")
	}
	pair.Fields["second"] = "changed"
	if zip.Items[1].(Record).Fields["second"] != "b" || other.Items[0] != "a" {
		t.Fatal("zip pair records share storage")
	}
	payload.Items[0] = int64(9)
	if zip.Items[1].(Record).Fields["first"].(*List).Items[0] != int64(9) {
		t.Fatal("zip cloned a shallow payload")
	}
	predicate := NewFunction([]string{"value"}, "Bool", func(_ *Execution, args []Value) Value { return args[0] == payload })
	partitionType := "@std/ListPartition[@std/List[Int]]"
	partition := listParityCall(RootExecution(), "partition", partitionType, list, predicate).(Record)
	matching := partition.Fields["matching"].(*List)
	if matching.Items[0] != payload || matching.Type != list.Type || partition.Fields["remaining"].(*List).Type != list.Type {
		t.Fatal("partition cloned payloads or lost nested generic identity")
	}
	matching.Items[0] = other
	if list.Items[0] != payload {
		t.Fatal("partition retained input outer storage")
	}
}

func init() {
	Register(Implementation{Receiver: "ListParityKey", Contract: "@std/Equal", Name: "equals", Scope: "list-parity.ms", Build: func(receiver Value, _ map[string]string, _ map[string]TypeScope) Function {
		return NewFunction([]string{"other"}, "Bool", func(_ *Execution, args []Value) Value {
			return receiver.(Record).Fields["id"] == ContractReceiver(args[0]).(Record).Fields["id"]
		})
	}})
}

func TestListParityDistinctScopedEquality(t *testing.T) {
	first := Record{Type: "ListParityKey", Fields: map[string]Value{"id": int64(1), "label": "first"}}
	duplicate := Record{Type: "ListParityKey", Fields: map[string]Value{"id": int64(1), "label": "duplicate"}}
	last := Record{Type: "ListParityKey", Fields: map[string]Value{"id": int64(2), "label": "last"}}
	list := &List{Type: "@std/List[ListParityKey]", Items: []Value{first, duplicate, last}}
	ctx := RootExecution()
	ctx.EqualityScope = TypeScope{Module: "list-parity.ms"}
	result := listParityCall(ctx, "distinct", list.Type, list).(*List)
	if result == list || len(result.Items) != 2 || result.Items[0].(Record).Fields["label"] != "first" || result.Items[1].(Record).Fields["label"] != "last" {
		t.Fatal("distinct ignored scoped Equal or first payload retention")
	}
	result.Items[0].(Record).Fields["label"] = "shared"
	if first.Fields["label"] != "shared" {
		t.Fatal("distinct copied payload storage")
	}
	if got := listParityCall(RootExecution(), "distinct", list.Type, list).(*List); len(got.Items) != 3 {
		t.Fatal("distinct leaked a scoped implementation into another module")
	}
}

func TestListParityExtremaRetainVisitedPayloads(t *testing.T) {
	for _, name := range []string{"min", "max"} {
		items := []Value{int64(3), int64(2)}
		if name == "max" {
			items = []Value{int64(2), int64(3)}
		}
		list := &List{Type: "@std/List[Int]", Items: items}
		candidate := items[1]
		compare := NewFunction([]string{"left", "right"}, "Int", func(ctx *Execution, args []Value) Value {
			list.Items[1] = int64(99)
			return Invoke(ctx, listParityCompare(), []Argument{{"left", args[0]}, {"right", args[1]}})
		})
		result := listParityCall(RootExecution(), name, "@std/Optional[Int]", list, compare).(Alternative)
		if result.Tag != "some" || result.Fields[0] != candidate {
			t.Fatalf("%s reread candidate after comparator: %#v", name, result)
		}
	}
	first, second := &List{Type: "@std/List[Int]"}, &List{Type: "@std/List[Int]"}
	list := &List{Type: "@std/List[@std/List[Int]]", Items: []Value{first, second}}
	tie := NewFunction([]string{"left", "right"}, "Int", func(*Execution, []Value) Value { return int64(0) })
	for _, name := range []string{"min", "max"} {
		if got := listParityCall(RootExecution(), name, "@std/Optional[@std/List[Int]]", list, tie).(Alternative); got.Fields[0] != first {
			t.Fatal("extrema did not retain the first tie payload")
		}
	}
	for _, name := range []string{"min", "max"} {
		for _, capacity := range []int{3, 6} {
			items := make([]Value, 3, capacity)
			initial, appended, rewritten, want := []Value{int64(3), int64(2), int64(1)}, int64(0), int64(99), int64(1)
			if name == "max" {
				initial, appended, rewritten, want = []Value{int64(1), int64(2), int64(3)}, 4, -99, 3
			}
			if capacity == 6 {
				want = 2
			}
			copy(items, initial)
			values := &List{Type: "@std/List[Int]", Items: items}
			comparisons := 0
			compare := NewFunction([]string{"left", "right"}, "Int", func(ctx *Execution, args []Value) Value {
				comparisons++
				if comparisons == 1 {
					ListAppend(ctx, values, appended)
					values.Items[2] = rewritten
				}
				return Invoke(ctx, listParityCompare(), []Argument{{"left", args[0]}, {"right", args[1]}})
			})
			got := listParityCall(RootExecution(), name, "@std/Optional[Int]", values, compare).(Alternative)
			if comparisons != 2 || got.Fields[0] != want {
				t.Fatalf("%s capacity %d: captured result %#v (%d comparisons), want %d", name, capacity, got, comparisons, want)
			}
		}
	}
}

func TestListParityInsertPopAndStableSort(t *testing.T) {
	list := &List{Type: "@std/List[Int]", Items: []Value{int64(3), int64(1), int64(2)}}
	alias := list
	if listParityCall(RootExecution(), "insert", list.Type, list, int64(0), int64(4)) != list ||
		listParityCall(RootExecution(), "insert", list.Type, list, int64(len(list.Items)), int64(5)) != list {
		t.Fatal("insert lost receiver identity")
	}
	if !reflect.DeepEqual(alias.Items, []Value{int64(4), int64(3), int64(1), int64(2), int64(5)}) {
		t.Fatal("insert endpoint order")
	}
	captured, capacity := CaptureList(list), list.Cap()
	if got := listParityCall(RootExecution(), "pop", "@std/Optional[Int]", list).(Alternative); got.Tag != "some" || got.Fields[0] != int64(5) || captured.Get(4) != int64(5) || list.Cap() != capacity {
		t.Fatal("pop cleared captured tail, released capacity or lost payload")
	}
	if listParityCall(RootExecution(), "sort_in_place", list.Type, list, listParityCompare()) != list || !reflect.DeepEqual(alias.Items, []Value{int64(1), int64(2), int64(3), int64(4)}) {
		t.Fatal("sort did not mutate the original receiver")
	}
	for _, index := range []int64{math.MinInt64, -1, 5, math.MaxInt64} {
		failure := recovered(func() { listParityCall(RootExecution(), "insert", list.Type, list, index, int64(0)) })
		fault, ok := failure.(Fault)
		if !ok || fault.Message != "List.insert: index must be between 0 and 4, found "+Format(index) {
			t.Fatalf("insert bounds fault = %#v", failure)
		}
	}
	first := Record{Type: "Item", Fields: map[string]Value{"rank": int64(1), "label": "first"}}
	second := Record{Type: "Item", Fields: map[string]Value{"rank": int64(1), "label": "second"}}
	last := Record{Type: "Item", Fields: map[string]Value{"rank": int64(2), "label": "last"}}
	records := &List{Type: "@std/List[Item]", Items: []Value{last, first, second}}
	compare := NewFunction([]string{"left", "right"}, "Int", func(_ *Execution, args []Value) Value {
		return args[0].(Record).Fields["rank"].(int64) - args[1].(Record).Fields["rank"].(int64)
	})
	listParityCall(RootExecution(), "sort_in_place", records.Type, records, compare)
	if records.Items[0].(Record).Fields["label"] != "first" || records.Items[1].(Record).Fields["label"] != "second" {
		t.Fatal("in-place sorting is not stable")
	}
}

func TestListParityEmptyFaultsAndCancellation(t *testing.T) {
	list := &List{Type: "@std/List[Int]"}
	predicate := NewFunction([]string{"value"}, "Bool", func(*Execution, []Value) Value { return true })
	compare := listParityCompare()
	for _, name := range []string{"min", "max", "pop"} {
		args := []Value{list}
		if name != "pop" {
			args = append(args, compare)
		}
		if result := listParityCall(RootExecution(), name, "@std/Optional[Int]", args...).(Alternative); result.Tag != "none" {
			t.Fatal("empty List operation did not return none")
		}
	}
	if listParityCall(RootExecution(), "count", "Int", list, predicate) != int64(0) || len(listParityCall(RootExecution(), "distinct", list.Type, list).(*List).Items) != 0 {
		t.Fatal("empty List count/distinct")
	}
	if result := listParityCall(RootExecution(), "zip", "@std/List[@std/ListPair[Int][Int]]", list, list).(*List); len(result.Items) != 0 {
		t.Fatal("empty zip")
	}
	if result := listParityCall(RootExecution(), "partition", "@std/ListPartition[Int]", list, predicate).(Record); len(result.Fields["matching"].(*List).Items) != 0 || len(result.Fields["remaining"].(*List).Items) != 0 {
		t.Fatal("empty partition")
	}
	if listParityCall(RootExecution(), "sort_in_place", list.Type, list, compare) != list {
		t.Fatal("empty sort lost receiver")
	}
	for name, args := range map[string][]Value{
		"count": {list, predicate}, "zip": {list, list}, "distinct": {list}, "partition": {list, predicate},
		"min": {list, compare}, "max": {list, compare}, "pop": {list}, "insert": {list, int64(0), int64(1)}, "sort_in_place": {list, compare},
	} {
		ctx := RootExecution()
		lifetime, cancel := context.WithCancel(ctx.Context)
		cancel()
		ctx.Context = lifetime
		failure := recovered(func() { listParityCall(ctx, name, "unused", args...) })
		if _, ok := failure.(cancelled); !ok {
			t.Fatalf("%s cancellation became %#v", name, failure)
		}
	}
	for _, name := range []string{"min", "max", "sort_in_place"} {
		values := &List{Type: list.Type, Items: []Value{int64(2), int64(1)}}
		faulting := NewFunction([]string{"left", "right"}, "Int", func(*Execution, []Value) Value {
			values.Items[0] = int64(99)
			return Panic("comparator failed")
		})
		failure := recovered(func() {
			listParityCall(RootExecution(), name, "unused", values, faulting)
		})
		if fault, ok := failure.(Fault); !ok || fault.Message != "comparator failed" {
			t.Fatalf("%s swallowed comparator fault: %#v", name, failure)
		}
		if values.Items[0] != int64(99) {
			t.Fatal("comparator fault rolled back a callback mutation")
		}
	}
}

func TestListParityBoundTypeAndWorkCancellation(t *testing.T) {
	list := &List{Type: "@std/List[Int]", Items: []Value{int64(2), int64(1)}}
	bound := NativeMemberResult(list, "min", "").(Function)
	if bound.Result != "@std/Optional[Int]" || Invoke(RootExecution(), bound, []Argument{{"compare", listParityCompare()}}).(Alternative).Fields[0] != int64(1) {
		t.Fatal("bound List generic receiver identity")
	}
	for _, name := range []string{"count", "distinct", "partition", "min", "max", "zip", "sort_in_place"} {
		ctx := RootExecution()
		workContext, cancel := context.WithCancel(context.Background())
		defer cancel()
		work := &stringWorkCancellation{Context: workContext, cancel: cancel}
		ctx.Context = work
		items := make([]Value, 4)
		for i := range items {
			items[i] = int64(len(items) - i)
		}
		values := &List{Type: list.Type, Items: items}
		args := []Value{values}
		switch name {
		case "count", "partition":
			args = append(args, NewFunction([]string{"value"}, "Bool", func(*Execution, []Value) Value { return true }))
		case "min", "max", "sort_in_place":
			args = append(args, listParityCompare())
		case "zip":
			args = append(args, values)
		}
		result := list.Type
		if name == "zip" {
			result = "@std/List[@std/ListPair[Int][Int]]"
		} else if name == "partition" {
			result = "@std/ListPartition[Int]"
		}
		failure := recovered(func() { listParityCall(ctx, name, result, args...) })
		if _, ok := failure.(cancelled); !ok || work.checks < 2 {
			t.Fatalf("%s work cancellation became %#v (%d checks)", name, failure, work.checks)
		}
	}
	for _, name := range []string{"insert", "pop"} {
		ctx := RootExecution()
		workContext, cancel := context.WithCancel(context.Background())
		defer cancel()
		ctx.Context = &stringWorkCancellation{Context: workContext, cancel: cancel}
		values := &List{Type: list.Type, Items: []Value{int64(1)}}
		captured := CaptureList(values)
		args := []Value{values}
		wantLength := 0
		if name == "insert" {
			args = append(args, int64(1), int64(2))
			wantLength = 2
		}
		failure := recovered(func() { listParityCall(ctx, name, list.Type, args...) })
		if _, ok := failure.(cancelled); !ok || len(values.Items) != wantLength || captured.Get(0) != int64(1) {
			t.Fatalf("%s post-effect cancellation lost mutation or captured payload: %#v", name, failure)
		}
	}
}
