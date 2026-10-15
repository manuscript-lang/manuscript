package msruntime

import (
	"context"
	"strings"
	"testing"
)

func TestOptionalReceiverMethods(t *testing.T) {
	ctx := RootExecution()
	call := func(value Value, method string, args ...Argument) Value {
		if method == "is_some" || method == "is_none" {
			return NativeAccessorRead(ctx, value, method)
		}
		return Invoke(ctx, NativeMemberResult(value, method, ""), args)
	}
	for _, test := range []struct {
		typ      string
		payload  Value
		fallback Value
	}{{"Int", int64(0), int64(9)}, {"Bool", false, true}, {"Unit", Unit{}, Unit{}}} {
		payload := test.payload
		present := optional(test.typ, payload, true)
		missing := optional(test.typ, nil, false)
		if call(present, "is_some") != true || call(present, "is_none") != false || call(missing, "is_some") != false || call(missing, "is_none") != true {
			t.Fatal("presence must test the case, not payload truthiness")
		}
		if !Equal(call(present, "unwrap"), payload) || !Equal(call(present, "unwrap_or", Argument{"fallback", test.fallback}), payload) {
			t.Fatal("present payload changed")
		}
		if !Equal(call(missing, "unwrap_or", Argument{"fallback", test.fallback}), test.fallback) {
			t.Fatal("missing fallback lost")
		}
	}
	var calls int
	create := NewFunction(nil, "Int", func(_ *Execution, _ []Value) Value {
		calls++
		return int64(42)
	})
	if call(optional("Int", int64(0), true), "unwrap_or_else", Argument{"create", create}) != int64(0) || calls != 0 {
		t.Fatal("some evaluated fallback")
	}
	if call(optional("Int", nil, false), "unwrap_or_else", Argument{"create", create}) != int64(42) || calls != 1 {
		t.Fatal("none must evaluate fallback once")
	}
	fault, ok := recovered(func() { call(optional("Int", nil, false), "unwrap") }).(Fault)
	if !ok || !strings.HasPrefix(fault.Message, "called Optional.unwrap() on none") {
		t.Fatalf("unexpected absent extraction fault: %#v", fault)
	}
	create = NewFunction(nil, "Int", func(_ *Execution, _ []Value) Value { return Panic("fallback failed") })
	fault, ok = recovered(func() { call(optional("Int", nil, false), "unwrap_or_else", Argument{"create", create}) }).(Fault)
	if !ok || fault.Message != "fallback failed" {
		t.Fatalf("fallback fault was changed: %#v", fault)
	}
	cancelledContext, cancel := context.WithCancel(ctx.Context)
	cancel()
	create = NewFunction(nil, "Int", func(_ *Execution, _ []Value) Value {
		CheckCancelled(&Execution{Context: cancelledContext})
		return int64(0)
	})
	if _, ok := recovered(func() { call(optional("Int", nil, false), "unwrap_or_else", Argument{"create", create}) }).(cancelled); !ok {
		t.Fatal("lazy fallback cancellation was changed")
	}
	inner := optional("Int", nil, false)
	outer := optional("@std/Optional[Int]", inner, true)
	bound := NativeMemberResult(outer, "unwrap", "").(Function)
	if bound.Result != "@std/Optional[Int]" || !Equal(Invoke(ctx, bound, nil), inner) {
		t.Fatal("nested Optional result was flattened or incorrectly specialized")
	}
	limits := Record{Type: "@std/JsonLimits", Fields: map[string]Value{"max_bytes": optional("Int", int64(-1), true), "max_depth": optional("Int", nil, false), "max_values": optional("Int", nil, false)}}
	got := call(optional("@std/JsonLimits", nil, false), "unwrap_or", Argument{"fallback", limits}).(Record)
	if !Equal(got, limits) {
		t.Fatal("generic fallback normalized options instead of preserving the record")
	}
	got.Fields["max_values"] = optional("Int", int64(7), true)
	if !Equal(got, limits) {
		t.Fatal("generic fallback copied the payload")
	}
	if _, ok := nativeLibraryMember(Alternative{Type: "local/Optional[Int]", Tag: "none"}, "unwrap", ""); ok {
		t.Fatal("Optional methods leaked to a user alternative")
	}
}
