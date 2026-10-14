package msruntime

import (
	"context"
	"strings"
	"testing"
)

func TestBytesSplitSharesImmutableViewsAndCopiesOuterStorage(t *testing.T) {
	ctx := RootExecution()
	data := Bytes{[]byte{1, 0, 2}}
	bound := NativeMemberResult(data, "split", "").(Function)
	if strings.Join(bound.Labels, ",") != "separator,max_parts" || bound.Result != "@std/List[@std/Bytes]" {
		t.Fatal("wrong bound Bytes.split metadata", bound.Labels, bound.Result)
	}
	call := func() *List { return Invoke(ctx, bound, []Argument{{"separator", Bytes{[]byte{0}}}}).(*List) }
	first, second := call(), call()
	if first == second || &first.Items[0] == &second.Items[0] {
		t.Fatal("byte parts share outer storage")
	}
	for i, offset := range []int{0, 2} {
		part := first.Items[i].(Bytes)
		if len(part.Items) != 1 || &part.Items[0] != &data.Items[offset] {
			t.Fatal("byte part copied immutable backing storage", i)
		}
	}
}

func TestBytesSplitFaultsAndCancellation(t *testing.T) {
	spec, ok := NativeLibrarySpec("Bytes", "split")
	if !ok {
		t.Fatal("missing byte split ABI")
	}
	for _, limit := range []Value{int64(-7), optional("Int", int64(-7), true)} {
		failure := recovered(func() { spec.Body(RootExecution(), "@std/List[@std/Bytes]", []Value{Bytes{}, Bytes{[]byte{0}}, limit}) })
		if fault, ok := failure.(Fault); !ok || fault.Message != "split: max_parts must be nonnegative, found -7" {
			t.Fatalf("wrong split limit fault: %#v", failure)
		}
	}
	for _, limit := range []int64{0, 1} {
		ctx := RootExecution()
		cancelledContext, cancel := context.WithCancel(ctx.Context)
		cancel()
		ctx.Context = cancelledContext
		failure := recovered(func() {
			Invoke(ctx, NativeMemberResult(Bytes{}, "split", ""), []Argument{{"separator", Bytes{}}, {"max_parts", optional("Int", limit, true)}})
		})
		if _, ok := failure.(cancelled); !ok {
			t.Fatalf("cancelled byte split became %#v", failure)
		}
	}
	for _, separator := range []Bytes{{}, {[]byte{0}}} {
		ctx := RootExecution()
		workContext, cancel := context.WithCancel(context.Background())
		defer cancel()
		work := &stringWorkCancellation{Context: workContext, cancel: cancel}
		ctx.Context = work
		failure := recovered(func() {
			spec.Body(ctx, "@std/List[@std/Bytes]", []Value{Bytes{[]byte(strings.Repeat("a\x00", 4096))}, separator, optional("Int", nil, false)})
		})
		if _, ok := failure.(cancelled); !ok || work.checks < 2 {
			t.Fatalf("byte splitting lost work cancellation: %#v (%d checks)", failure, work.checks)
		}
	}
}
