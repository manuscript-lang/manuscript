package msruntime

import (
	"context"
	"testing"
)

func TestNativeDefaultsPreservePayloadAndCancellation(t *testing.T) {
	ctx := RootExecution()
	calls, defaults := 0, 0
	native := NewFunction([]string{"value"}, "@std/Box", func(_ *Execution, args []Value) Value { calls++; return args[0] })
	prepare := NewSourceFunction(native.Labels, native.Result, "defaults.ms:1:1", func(_ *Execution, args []Value) Value {
		if args[0] == nil {
			defaults++
			args[0] = Record{Type: "@std/Box", Fields: map[string]Value{"count": int32(0)}}
		}
		return PreparedDefaults(args)
	})
	callable := WithDefaults(native, prepare, []int{0})
	first := Invoke(ctx, callable, nil).(Record)
	second := Invoke(ctx, callable, nil).(Record)
	first.Fields["count"] = int32(4)
	if second.Fields["count"] != int32(0) || defaults != 2 {
		t.Fatal("shared mutable default storage", defaults)
	}
	present := Invoke(ctx, callable, []Argument{{"value", first}}).(Record)
	present.Fields["count"] = int32(7)
	if first.Fields["count"] != int32(7) || defaults != 2 {
		t.Fatal("present payload was copied or default ran")
	}
	for _, value := range []Value{false, int32(0), Unit{}, optional("Int", nil, false), Bytes{}} {
		_ = Invoke(ctx, callable, []Argument{{"value", value}})
	}
	if defaults != 2 || calls != 8 {
		t.Fatal("concrete absence was treated as omitted", calls, defaults)
	}
	parent, cancel := context.WithCancel(ctx.Context)
	stopped := *ctx
	stopped.Context = parent
	cancel()
	if _, ok := recovered(func() { Invoke(&stopped, callable, nil) }).(cancelled); !ok || defaults != 2 || calls != 8 {
		t.Fatal("cancelled entry evaluated defaults or body")
	}
	parent, cancel = context.WithCancel(ctx.Context)
	stopped.Context = parent
	cancelling := NewFunction(native.Labels, native.Result, func(_ *Execution, args []Value) Value { cancel(); return PreparedDefaults(args) })
	if _, ok := recovered(func() { Invoke(&stopped, WithDefaults(native, cancelling, []int{0}), nil) }).(cancelled); !ok || calls != 8 {
		t.Fatal("cancelled default reached native body")
	}
}

func TestNativeDefaultFailureAndAcquisitionDelivery(t *testing.T) {
	ctx := RootExecution()
	called := false
	native := NewFunction([]string{"value"}, "Result[Int][String]", func(*Execution, []Value) Value { called = true; return int32(1) })
	failure := Alternative{Type: native.Result, Tag: "error", Fields: []Value{"failed"}}
	prepare := NewFunction(native.Labels, native.Result, func(*Execution, []Value) Value { return failure })
	if got := Invoke(ctx, WithDefaults(native, prepare, []int{0}), nil); !Equal(got, failure) || called {
		t.Fatal("propagation reached native body", got)
	}
	prepare = NewFunction(native.Labels, native.Result, func(*Execution, []Value) Value { return Panic("default fault") })
	if fault, ok := recovered(func() { Invoke(ctx, WithDefaults(native, prepare, []int{0}), nil) }).(Fault); !ok || fault.Message != "default fault" || called {
		t.Fatal("default fault changed", fault)
	}
	parent, cancel := context.WithCancel(ctx.Context)
	stopped := *ctx
	stopped.Context = parent
	disposed := 0
	acquire := NewAcquisition([]string{"value"}, "Resource", func(*Execution, []Value) Value { cancel(); return Record{Type: "Resource"} }, func(*Execution, Value) { disposed++ })
	prepare = NewFunction(acquire.Labels, "Resource", func(_ *Execution, args []Value) Value { return PreparedDefaults(args) })
	if _, ok := recovered(func() { Invoke(&stopped, WithDefaults(acquire, prepare, []int{0}), nil) }).(cancelled); !ok || disposed != 1 {
		t.Fatal("native acquisition disposal changed", disposed)
	}
}

func TestPresentNewDefaultsKeepOldOmissionSlots(t *testing.T) {
	ctx := RootExecution()
	prepared := 0
	native := NewFunction([]string{"flag", "limit"}, "Bool", func(_ *Execution, args []Value) Value {
		return args[0] == false && args[1] == nil
	})
	prepare := NewFunction(native.Labels, native.Result, func(_ *Execution, args []Value) Value {
		prepared++
		return PreparedDefaults{false, optional("Int", nil, false)}
	})
	if Invoke(ctx, WithDefaults(native, prepare, []int{0}), []Argument{{"flag", false}}) != true || prepared != 0 {
		t.Fatal("supplying the new default changed the old native omission path", prepared)
	}
}

func BenchmarkNativeDefaultPreparation(b *testing.B) {
	ctx := RootExecution()
	native := NewFunction([]string{"value"}, "Bool", func(_ *Execution, args []Value) Value { return args[0] })
	prepare := NewSourceFunction(native.Labels, native.Result, "defaults.ms:1:1", func(_ *Execution, args []Value) Value {
		value := args[0]
		if value == nil {
			value = false
		}
		return PreparedDefaults{value}
	})
	for _, name := range []string{"native", "present", "omitted"} {
		b.Run(name, func(b *testing.B) {
			callable := Value(native)
			args := []Argument{{"value", false}}
			if name != "native" {
				callable = WithDefaults(native, prepare, []int{0})
			}
			if name == "omitted" {
				args = nil
			}
			b.ReportAllocs()
			for b.Loop() {
				if Invoke(ctx, callable, args) != false {
					b.Fatal("wrong value")
				}
			}
		})
	}
}
