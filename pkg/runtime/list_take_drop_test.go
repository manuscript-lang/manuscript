package msruntime

import (
	"context"
	"testing"
)

func TestListTakeDropIdentityCancellationAndRawFaults(t *testing.T) {
	for _, name := range []string{"take", "drop"} {
		t.Run(name, func(t *testing.T) {
			payload := &List{Type: "@std/List[Int]", Items: []Value{int32(1)}}
			original := &List{Type: "@std/List[@std/List[Int]]", Items: []Value{payload}}
			ctx := RootExecution()
			count := int32(1)
			if name == "drop" {
				count = 0
			}
			bound := NativeMemberResult(original, name, "").(Function)
			copied := Invoke(ctx, bound, []Argument{{"count", count}}).(*List)
			if copied == original || copied.Type != original.Type || copied.Items[0] != payload || &copied.Items[0] == &original.Items[0] {
				t.Fatal("List copy changed shallow payload or outer storage")
			}
			spec, ok := NativeLibrarySpec("List", name)
			if !ok {
				t.Fatal("missing List copy ABI", name)
			}
			failure := recovered(func() { spec.Body(ctx, original.Type, []Value{original, int32(-7)}) })
			if fault, ok := failure.(Fault); !ok || fault.Message != "List."+name+": count must be nonnegative, found -7" {
				t.Fatalf("wrong copy count fault: %#v", failure)
			}
			cancelledContext, cancel := context.WithCancel(ctx.Context)
			cancel()
			ctx.Context = cancelledContext
			failure = recovered(func() { Invoke(ctx, bound, []Argument{{"count", int32(0)}}) })
			if _, ok := failure.(cancelled); !ok {
				t.Fatalf("entry cancellation became %#v", failure)
			}
			ctx = RootExecution()
			workContext, cancel := context.WithCancel(context.Background())
			defer cancel()
			work := &stringWorkCancellation{Context: workContext, cancel: cancel}
			ctx.Context = work
			items := make([]Value, 4096)
			for i := range items {
				items[i] = int32(i)
			}
			count = int32(len(items))
			if name == "drop" {
				count = 0
			}
			failure = recovered(func() { spec.Body(ctx, "@std/List[Int]", []Value{&List{Type: "@std/List[Int]", Items: items}, count}) })
			if _, ok := failure.(cancelled); !ok || work.checks < 2 {
				t.Fatalf("work cancellation became %#v (%d checks)", failure, work.checks)
			}
		})
	}
}
