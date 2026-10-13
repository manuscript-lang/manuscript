package msruntime

import (
	"context"
	"regexp"
	"testing"
)

func TestPreferredNamesCancellationPrecedesEffects(t *testing.T) {
	list := &List{Type: "@std/List[Int]", Items: []Value{int64(1)}}
	set := &Set{Type: "@std/Set[Int]", Items: []Value{int64(1)}}
	mapping := &Map{Type: "@std/Map[Int][Int]", Entries: []Entry{{int64(1), int64(2)}}}
	for _, tc := range []struct {
		receiver Value
		name     string
		args     []Argument
	}{
		{list, "reverse_in_place", nil},
		{list, "reversed", nil},
		{Bytes{[]byte{1}}, "reversed", nil},
		{list, "set", []Argument{{"index", int64(0)}, {"value", int64(2)}}},
		{list, "remove", []Argument{{"index", int64(0)}}},
		{list, "splice", []Argument{{"start", int64(0)}, {"delete_count", int64(1)}, {"replacement", &List{Type: list.Type}}}},
		{mapping, "remove", []Argument{{"key", int64(1)}}},
		{set, "add", []Argument{{"value", int64(2)}}},
		{set, "remove", []Argument{{"value", int64(1)}}},
		{"aa", "replace_first", []Argument{{"old", "a"}, {"new", "b"}, {"max_replacements", optional("Int", nil, false)}}},
		{libraryRegex{regexp.MustCompile("a")}, "replace_all", []Argument{{"text", "aa"}, {"replacement", "b"}, {"max_bytes", optional("Int", nil, false)}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx := RootExecution()
			cancelledContext, cancel := context.WithCancel(ctx.Context)
			ctx.Context = cancelledContext
			cancel()
			if _, ok := recovered(func() { Invoke(ctx, NativeMemberResult(tc.receiver, tc.name, ""), tc.args) }).(cancelled); !ok {
				t.Fatal("native cancellation was converted or ignored")
			}
			if len(list.Items) != 1 || list.Items[0] != int64(1) || len(set.Items) != 1 || set.Items[0] != int64(1) || len(mapping.Entries) != 1 {
				t.Fatal("cancelled mutation changed its receiver")
			}
		})
	}
	ctx := RootExecution()
	cancelledContext, cancel := context.WithCancel(ctx.Context)
	ctx.Context = cancelledContext
	cancel()
	for _, call := range []func(){
		func() { SetWithValue(ctx, set, int64(2), TypeScope{}) },
		func() { SetRemove(ctx, set, int64(1), TypeScope{}) },
		func() { MapRemove(ctx, mapping, int64(1), TypeScope{}) },
	} {
		if _, ok := recovered(call).(cancelled); !ok {
			t.Fatal("direct path ignored cancellation")
		}
	}
	if len(set.Items) != 1 || set.Items[0] != int64(1) {
		t.Fatal("direct cancelled mutation")
	}
}
