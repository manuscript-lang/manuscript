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
		{Bytes{[]byte{0}}, "with_value", []Argument{{"index", int32(0)}, {"value", int32(300)}}},
		{Bytes{[]byte{0}}, "slice", []Argument{{"start", int32(-1)}, {"end", int32(1)}}},
		{&List{Type: "@std/List[Int]", Items: []Value{int32(0)}}, "with_value", []Argument{{"index", int32(2)}, {"value", int32(0)}}},
		{&List{Type: "@std/List[Int]", Items: []Value{int32(0)}}, "without", []Argument{{"index", int32(2)}}},
		{&List{Type: "@std/List[Int]", Items: []Value{int32(0)}}, "fill", []Argument{{"value", int32(1)}, {"start", int32(-1)}, {"end", int32(1)}}},
		{&List{Type: "@std/List[Int]", Items: []Value{int32(0)}}, "copy_within", []Argument{{"target", int32(2)}, {"start", int32(0)}, {"end", int32(1)}}},
		{&List{Type: "@std/List[Int]", Items: []Value{int32(0)}}, "with_values", []Argument{{"start", int32(-1)}, {"delete_count", int32(0)}, {"replacement", &List{Type: "@std/List[Int]"}}}},
		{int32(1), "to_string", []Argument{{"radix", int32(1)}}},
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
