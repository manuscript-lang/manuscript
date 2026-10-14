package msruntime

import (
	"context"
	"testing"
)

func TestListInsertPopIdentityAndRawFaults(t *testing.T) {
	ctx := RootExecution()
	payload := &List{Type: "@std/List[Int]", Items: []Value{int64(1)}}
	original := &List{Type: "@std/List[@std/List[Int]]", Items: []Value{payload}}
	insert, ok := NativeLibrarySpec("List", "insert")
	if !ok {
		t.Fatal("missing List.insert ABI")
	}
	if insert.Body(ctx, original.Type, []Value{original, int64(0), payload}) != original || len(original.Items) != 2 || original.Items[0] != payload {
		t.Fatal("List.insert did not mutate and return its receiver")
	}
	for index, want := range map[int64]string{
		3:  "List.insert: index must be between -2 and 2 (negative indexes count from the end), found 3",
		-3: "List.insert: index must be between -2 and 2 (negative indexes count from the end), found -3",
	} {
		failure := recovered(func() { insert.Body(ctx, original.Type, []Value{original, index, payload}) })
		if fault, ok := failure.(Fault); !ok || fault.Message != want {
			t.Fatalf("wrong insert fault for %d: %#v", index, failure)
		}
	}
	pop, ok := NativeLibrarySpec("List", "pop")
	if !ok {
		t.Fatal("missing List.pop ABI")
	}
	result := pop.Body(ctx, "@std/Optional[@std/List[Int]]", []Value{original}).(Alternative)
	if result.Tag != "some" || result.Fields[0] != payload || len(original.Items) != 1 {
		t.Fatalf("List.pop returned %#v", result)
	}
	pop.Body(ctx, "@std/Optional[@std/List[Int]]", []Value{original})
	if result := pop.Body(ctx, "@std/Optional[@std/List[Int]]", []Value{original}).(Alternative); result.Tag != "none" {
		t.Fatalf("empty List.pop returned %#v", result)
	}
}

func TestListCountDistinctCancellation(t *testing.T) {
	for _, name := range []string{"count", "distinct"} {
		t.Run(name, func(t *testing.T) {
			ctx := RootExecution()
			bound := NativeMemberResult(&List{Type: "@std/List[Int]", Items: []Value{int64(1)}}, name, "").(Function)
			var arguments []Argument
			if name == "count" {
				arguments = []Argument{{"predicate", Function{Labels: []string{"value"}, Result: "Bool", Body: func(_ *Execution, _ []Value) Value { return true }}}}
			}
			cancelledContext, cancel := context.WithCancel(ctx.Context)
			cancel()
			ctx.Context = cancelledContext
			failure := recovered(func() { Invoke(ctx, bound, arguments) })
			if _, ok := failure.(cancelled); !ok {
				t.Fatalf("entry cancellation became %#v", failure)
			}
		})
	}
}
