package msruntime

import (
	"context"
	"testing"
)

func TestNativeDispatchBoundBytesValues(t *testing.T) {
	ctx := RootExecution()
	data := Bytes{[]byte{0, 1, 255}}
	bound := NativeMemberResult(data, "values", "").(Function)
	if len(bound.Labels) != 0 || bound.Result != "@std/List[Int]" {
		t.Fatalf("unexpected callable: %#v", bound)
	}
	first := Invoke(ctx, bound, nil).(*List)
	if !Equal(first, &List{Type: "@std/List[Int]", Items: []Value{int64(0), int64(1), int64(255)}}) {
		t.Fatalf("unexpected byte extraction: %#v", first)
	}
	first.Items[0] = int64(99)
	if got := Invoke(ctx, bound, nil).(*List); got.Items[0] != int64(0) || data.Items[0] != 0 {
		t.Fatal("byte extraction aliases storage")
	}
	cancelledContext, cancel := context.WithCancel(ctx.Context)
	cancel()
	if _, ok := recovered(func() { Invoke(&Execution{Context: cancelledContext}, bound, nil) }).(cancelled); !ok {
		t.Fatal("native byte extraction ignored cancellation")
	}
}

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

func TestDirectNativeListAtAndUnwrap(t *testing.T) {
	ctx := RootExecution()
	payload := Record{Type: "local/Item", Fields: map[string]Value{"value": int64(7)}}
	list := &List{Type: "@std/List[local/Item]", Items: []Value{payload}}
	result := "@std/Optional[local/Item]"
	for _, index := range []int64{0, -1, 1, -2, -1 << 63, 1<<63 - 1} {
		got := ListAt(ctx, list, index, result).(Alternative)
		wantPresent := index == 0 || index == -1
		if got.Type != result || (got.Tag == "some") != wantPresent {
			t.Fatalf("index %d: %#v", index, got)
		}
		ordinary := Invoke(ctx, NativeMemberResult(list, "at", result), []Argument{{"index", index}})
		if !Equal(got, ordinary) {
			t.Fatalf("direct/ordinary mismatch at %d", index)
		}
		if wantPresent {
			unwrapped := OptionalUnwrap(ctx, got).(Record)
			unwrapped.Fields["value"] = int64(9)
			if payload.Fields["value"] != int64(9) {
				t.Fatal("unwrap copied payload")
			}
		} else {
			directFault := recovered(func() { OptionalUnwrap(ctx, got) }).(Fault)
			ordinaryFault := recovered(func() { Invoke(ctx, NativeMemberResult(got, "unwrap", "local/Item"), nil) }).(Fault)
			if directFault.Message != ordinaryFault.Message {
				t.Fatal("unwrap fault changed")
			}
		}
	}
	empty := &List{Type: list.Type}
	for _, method := range []string{"first", "last", "at"} {
		args := []Argument(nil)
		if method == "at" {
			args = []Argument{{"index", int64(-1)}}
		}
		if Invoke(ctx, NativeMemberResult(empty, method, result), args).(Alternative).Tag != "none" {
			t.Fatalf("empty %s", method)
		}
	}
	nested := optional("Int", nil, false)
	if !Equal(OptionalUnwrap(ctx, optional("@std/Optional[Int]", nested, true)), nested) {
		t.Fatal("nested optional flattened")
	}
	cancelledContext, cancel := context.WithCancel(ctx.Context)
	cancel()
	stopped := &Execution{Context: cancelledContext}
	for _, call := range []func(){
		func() { ListAt(stopped, list, int64(0), result) },
		func() { OptionalUnwrap(stopped, optional("Int", int64(1), true)) },
		func() { OptionalUnwrap(stopped, optional("Int", nil, false)) },
	} {
		if _, ok := recovered(call).(cancelled); !ok {
			t.Fatal("direct call ignored cancellation")
		}
	}
}

func TestNativeDispatchMapAddCancellation(t *testing.T) {
	ctx := RootExecution()
	cancelledContext, cancel := context.WithCancel(ctx.Context)
	cancel()
	child := &Execution{Context: cancelledContext}
	m := &Map{Type: "@std/Map[String][Int]"}
	bound := NativeMemberResult(m, "add", "").(Function)
	if bound.Result != m.Type || len(bound.Labels) != 2 || bound.Labels[0] != "key" || bound.Labels[1] != "value" {
		t.Fatal(bound)
	}
	for _, call := range []func(){
		func() { MapWithEntry(child, m, "a", int64(1), TypeScope{}) },
		func() { Invoke(child, bound, []Argument{{"value", int64(1)}, {"key", "a"}}) },
	} {
		if _, ok := recovered(call).(cancelled); !ok {
			t.Fatal("map add ignored cancellation")
		}
		if len(m.Entries) != 0 {
			t.Fatal("cancelled add changed map")
		}
	}
}
