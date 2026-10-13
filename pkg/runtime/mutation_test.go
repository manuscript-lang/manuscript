package msruntime

import (
	"sync"
	"testing"
)

func TestMutableListReusesCapacityAndBoundMethodSeesCurrentStorage(t *testing.T) {
	list := &List{Type: "@std/List[Int]", Items: make([]Value, 0, 8)}
	alias := list
	appendValue := NativeMember(list, "append")
	ctx := RootExecution()
	Invoke(ctx, appendValue, []Argument{{"value", int32(1)}})
	first := &list.Items[0]
	Invoke(ctx, appendValue, []Argument{{"value", int32(2)}})
	if &list.Items[0] != first || len(alias.Items) != 2 {
		t.Fatal("append copied storage or lost identity")
	}
	copy := Clone(list).(*List)
	Invoke(ctx, appendValue, []Argument{{"value", int32(3)}})
	if len(copy.Items) != 2 {
		t.Fatal("clone retained list header")
	}
	copy.Items[0] = int32(9)
	if list.Items[0] != int32(1) {
		t.Fatal("clone retained backing storage")
	}
	Invoke(ctx, NativeMember(list, "with_values"), []Argument{{"start", int32(1)}, {"delete_count", int32(1)}, {"replacement", list}})
	if !Equal(list, libraryList("Int", []Value{int32(1), int32(1), int32(2), int32(3), int32(3)})) {
		t.Fatal(list)
	}
	if &list.Items[0] != first {
		t.Fatal("splice ignored available capacity")
	}
}

func TestRecordCloneSharesNestedResourcesWithoutDuplicatingThem(t *testing.T) {
	handle := &Queue{typ: "@std/Queue[Int]"}
	child := NewRecord("Child", []Argument{{"value", int32(0)}})
	record := NewRecord("Record", []Argument{{"value", int32(1)}, {"child", child}, {"handle", handle}})
	copy := Clone(record)
	SetField(copy, "value", int32(2))
	SetField(Field(copy, "child"), "value", int32(3))
	if Field(record, "value") != int32(1) || Field(Field(record, "child"), "value") != int32(3) || Field(copy, "handle") != handle {
		t.Fatal("clone was not a shallow data copy")
	}
	if _, ok := recovered(func() { Clone(handle) }).(Fault); !ok {
		t.Fatal("cloned a service handle")
	}
}

func TestEqualityTerminatesOnMutableCycles(t *testing.T) {
	left, right := &List{Type: "@std/List[Node]"}, &List{Type: "@std/List[Node]"}
	a := NewRecord("Node", []Argument{{"value", int32(1)}, {"children", left}})
	b := NewRecord("Node", []Argument{{"value", int32(1)}, {"children", right}})
	left.Items, right.Items = []Value{a}, []Value{b}
	if !Equal(a, b) {
		t.Fatal("equal cycles differ")
	}
	SetField(b, "value", int32(2))
	if Equal(a, b) {
		t.Fatal("cycle suppressed unequal fields")
	}
}

func TestSynchronizedMutableRecordAndList(t *testing.T) {
	value := NewRecord("Counter", []Argument{{"value", int32(0)}, {"items", &List{Type: "@std/List[Int]"}}})
	root := RootExecution()
	cell := ConstructWithContext(root, "@std/Synchronized[Counter]", []Argument{{"value", value}})
	var workers sync.WaitGroup
	for range 8 {
		workers.Add(1)
		go func() {
			defer workers.Done()
			ctx := RootExecution()
			for range 100 {
				guard := Invoke(ctx, NativeMember(cell, "lock"), nil).(*SynchronizedGuard)
				current := Invoke(ctx, guard.Operation("get"), nil)
				n := Field(current, "value").(int32) + 1
				SetField(current, "value", n)
				Invoke(ctx, NativeMember(Field(current, "items"), "append"), []Argument{{"value", n}})
				guard.close()
			}
		}()
	}
	workers.Wait()
	if Field(value, "value") != int32(800) || len(Field(value, "items").(*List).Items) != 800 {
		t.Fatal("lost protected updates")
	}
}
