package msruntime

import (
	"context"
	"strings"
	"testing"
)

func TestResultPayloadIdentityAndSpecialization(t *testing.T) {
	ctx := RootExecution()
	cause := &List{Type: "@std/List[Int]", Items: []Value{int64(1)}}
	failed := Alternative{Type: "@std/Result[Int][@std/List[Int]]", Tag: "error", Fields: []Value{cause}}
	success := Alternative{Type: failed.Type, Tag: "ok", Fields: []Value{int64(0)}}
	call := func(value Value, name, result string, args ...Argument) Value {
		return Invoke(ctx, NativeMemberResult(value, name, result), args)
	}
	if call(failed, "unwrap_error", "") != cause || call(success, "unwrap", "") != int64(0) {
		t.Fatal("extraction changed payload")
	}
	if call(failed, "is_error", "") != true || call(failed, "is_ok", "") != false || call(success, "is_ok", "") != true {
		t.Fatal("wrong Result predicates")
	}
	for _, name := range []string{"map", "and_then"} {
		calls := 0
		callback := NewFunction([]string{"value"}, "String", func(*Execution, []Value) Value {
			calls++
			return "mapped"
		})
		result := "@std/Result[String][@std/List[Int]]"
		got := call(failed, name, result, Argument{"transform", callback}).(Alternative)
		if calls != 0 || got.Type != result || got.Tag != "error" || got.Fields[0] != cause {
			t.Fatal("composition changed or invoked error", name, got)
		}
	}
	calls := 0
	create := NewFunction([]string{"cause"}, "Int", func(execution *Execution, args []Value) Value {
		if execution.Context != ctx.Context || execution.Lifetime != ctx.Lifetime || execution.Host != ctx.Host || args[0] != cause {
			t.Fatal("fallback lost caller context or original cause")
		}
		calls++
		return int64(9)
	})
	if call(success, "unwrap_or_else", "", Argument{"create", create}) != int64(0) || calls != 0 {
		t.Fatal("successful Result invoked fallback")
	}
	if call(failed, "unwrap_or_else", "", Argument{"create", create}) != int64(9) || calls != 1 {
		t.Fatal("failed Result must invoke fallback once")
	}
	bound := NativeMemberResult(failed, "unwrap_error", "").(Function)
	if bound.Result != cause.Type || Invoke(ctx, bound, nil) != cause {
		t.Fatal("bound method lost nested error type or identity")
	}
	for _, test := range []struct {
		value Alternative
		name  string
		want  string
	}{{failed, "unwrap", "called Result.unwrap() on error"}, {success, "unwrap_error", "called Result.unwrap_error() on ok"}} {
		fault, ok := recovered(func() { call(test.value, test.name, "") }).(Fault)
		if !ok || !strings.HasPrefix(fault.Message, test.want) {
			t.Fatalf("wrong extraction fault: %#v", fault)
		}
	}
	for _, typ := range []string{"local/Result[Int][String]", "local/Optional[Int]", "@std/ResultLike[Int][String]"} {
		if _, ok := nativeLibraryMember(Alternative{Type: typ, Tag: "ok", Fields: []Value{int64(0)}}, "unwrap", ""); ok {
			t.Fatal("native methods leaked to unrelated alternative", typ)
		}
	}
}

func TestCoreParityCallbacksPreserveFaultsAndCancellation(t *testing.T) {
	for _, test := range []struct {
		name     string
		receiver Value
		method   string
		argument string
		labels   []string
		result   string
	}{
		{"Result fallback", Alternative{"@std/Result[Int][String]", "error", []Value{"cause"}}, "unwrap_or_else", "create", []string{"cause"}, "Int"},
		{"Result map", Alternative{"@std/Result[Int][String]", "ok", []Value{int64(0)}}, "map", "transform", []string{"value"}, "@std/Result[Int][String]"},
		{"Result chain", Alternative{"@std/Result[Int][String]", "ok", []Value{int64(0)}}, "and_then", "transform", []string{"value"}, "@std/Result[Int][String]"},
		{"Optional map", optional("Int", int64(0), true), "map", "transform", []string{"value"}, "@std/Optional[Int]"},
		{"Optional chain", optional("Int", int64(0), true), "and_then", "transform", []string{"value"}, "@std/Optional[Int]"},
		{"Optional fallback", optional("Int", nil, false), "or_else", "create", nil, "@std/Optional[Int]"},
		{"Map filter", &Map{Type: "@std/Map[String][Int]", Entries: []Entry{{"a", int64(1)}, {"b", int64(2)}}}, "filter", "predicate", []string{"key", "value"}, "@std/Map[String][Int]"},
		{"Set filter", &Set{Type: "@std/Set[Int]", Items: []Value{int64(1), int64(2)}}, "filter", "predicate", []string{"value"}, "@std/Set[Int]"},
		{"Set map", &Set{Type: "@std/Set[Int]", Items: []Value{int64(1), int64(2)}}, "map", "transform", []string{"value"}, "@std/Set[Int]"},
	} {
		t.Run(test.name, func(t *testing.T) {
			for _, cancelCallback := range []bool{false, true} {
				ctx := RootExecution()
				var cancel context.CancelFunc
				ctx.Context, cancel = context.WithCancel(ctx.Context)
				defer cancel()
				calls := 0
				callback := NewFunction(test.labels, "Int", func(execution *Execution, _ []Value) Value {
					calls++
					if execution.Context != ctx.Context || execution.Lifetime != ctx.Lifetime || execution.Host != ctx.Host {
						t.Fatal("callback changed caller execution")
					}
					if cancelCallback {
						cancel()
						CheckCancelled(execution)
					}
					return Panic("callback failed")
				})
				failure := recovered(func() {
					Invoke(ctx, NativeMemberResult(test.receiver, test.method, test.result), []Argument{{test.argument, callback}})
				})
				if cancelCallback {
					if _, ok := failure.(cancelled); !ok {
						t.Fatalf("callback cancellation became %#v", failure)
					}
				} else if fault, ok := failure.(Fault); !ok || fault.Message != "callback failed" {
					t.Fatalf("callback fault became %#v", failure)
				}
				if calls != 1 {
					t.Fatal("callback must stop traversal immediately", calls)
				}
				failure = recovered(func() {
					cancel()
					Invoke(ctx, NativeMemberResult(test.receiver, test.method, test.result), []Argument{{test.argument, callback}})
				})
				if _, ok := failure.(cancelled); !ok || calls != 1 {
					t.Fatal("cancelled call invoked callback", failure, calls)
				}
			}
		})
	}
}
