package msruntime

import (
	"context"
	"testing"
)

func TestPreconditionCallsPreserveCancellation(t *testing.T) {
	for _, tc := range []struct {
		receiver Value
		method   string
		args     []Argument
	}{
		{Bytes{[]byte{0}}, "with_value", []Argument{{"index", int64(0)}, {"value", int64(300)}}},
		{Bytes{[]byte{0}}, "slice", []Argument{{"start", int64(-1)}, {"end", int64(1)}}},
		{&List{Type: "@std/List[Int]", Items: []Value{int64(0)}}, "set", []Argument{{"index", int64(2)}, {"value", int64(0)}}},
		{&List{Type: "@std/List[Int]", Items: []Value{int64(0)}}, "remove", []Argument{{"index", int64(2)}}},
		{&List{Type: "@std/List[Int]", Items: []Value{int64(0)}}, "fill", []Argument{{"value", int64(1)}, {"start", int64(-1)}, {"end", int64(1)}}},
		{&List{Type: "@std/List[Int]", Items: []Value{int64(0)}}, "copy_within", []Argument{{"target", int64(2)}, {"start", int64(0)}, {"end", int64(1)}}},
		{&List{Type: "@std/List[Int]", Items: []Value{int64(0)}}, "splice", []Argument{{"start", int64(-1)}, {"delete_count", int64(0)}, {"replacement", &List{Type: "@std/List[Int]"}}}},
		{int64(1), "to_string", []Argument{{"radix", int64(1)}}},
	} {
		ctx, cancel := context.WithCancel(context.Background())
		execution := newExecution(RootExecution(), ctx)
		cancel()
		failure := recovered(func() { Invoke(execution, NativeMember(tc.receiver, tc.method), tc.args) })
		if _, ok := failure.(cancelled); !ok {
			t.Fatalf("%s cancellation became %#v", tc.method, failure)
		}
	}
}
