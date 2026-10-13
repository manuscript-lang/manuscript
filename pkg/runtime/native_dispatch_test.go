package msruntime

import (
	"context"
	"testing"
)

func TestNativeDispatchBoundList(t *testing.T) {
	ctx := RootExecution()
	list := &List{Type: "@std/List[@std/Optional[Int]]", Items: []Value{optional("Int", int64(1), true)}}
	for _, result := range []string{"", "@std/Optional[@std/Optional[Int]]"} {
		bound := NativeMemberResult(list, "at", result, TypeScope{Args: []TypeScope{{Module: "local"}}}).(Function)
		if bound.Result != "@std/Optional[@std/Optional[Int]]" {
			t.Fatalf("result = %s", bound.Result)
		}
		// A bound method must read the original receiver's current contents.
		list.Items[0] = optional("Int", int64(2), true)
		got := Invoke(ctx, bound, []Argument{{"index", int64(0)}}).(Alternative)
		if !Equal(got.Fields[0], list.Items[0]) {
			t.Fatal("bound receiver lost payload")
		}
		missing := Invoke(ctx, bound, []Argument{{"index", int64(1)}}).(Alternative)
		if missing.Tag != "none" || missing.Type != bound.Result {
			t.Fatal("out-of-range access changed")
		}
		cancelledContext, cancel := context.WithCancel(ctx.Context)
		cancel()
		if _, ok := recovered(func() { Invoke(&Execution{Context: cancelledContext}, bound, []Argument{{"index", int64(0)}}) }).(cancelled); !ok {
			t.Fatal("native call ignored cancellation")
		}
	}
}

func TestNativeOptionAdapterClassification(t *testing.T) {
	// Every concrete option schema must continue to pass through normalization.
	for typ := range nativeOptionRecords {
		if !nativeParamsNeedOptions([]LibraryParam{{Name: "options", Type: typ[len("@std/"):]}}) {
			t.Fatalf("missing adapter for %s", typ)
		}
	}
	for _, typ := range []string{"Optional[Int]", "Optional[Duration]", "Optional[JsonLimits]", "Optional[HtmlLimits]", "Optional[ArchiveLimits]"} {
		if !nativeParamsNeedOptions([]LibraryParam{{Name: "limit", Type: typ}}) {
			t.Fatalf("missing adapter for %s", typ)
		}
	}
	if nativeParamsNeedOptions([]LibraryParam{{Name: "fallback", Type: "T"}}) {
		t.Fatal("generic payload must not be normalized")
	}
}
