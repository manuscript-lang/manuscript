package msruntime

import (
	"context"
	"testing"
)

func TestTaskPreconditionFaultValuesAndCancellation(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []Argument
		want string
	}{
		{"limit", []Argument{{"limit", int32(-1)}}, "Scheduler: limit must be between 1 and 2147483647, found -1"},
		{"history_limit", []Argument{{"history_limit", int32(-2)}}, "Scheduler: history_limit must be between 0 and 2147483647, found -2"},
		{"drain", []Argument{{"drain", Duration(-1)}}, "Scheduler: drain (nanoseconds) must be between 0 and 9223372036854775807, found -1"},
	} {
		fault, ok := recovered(func() { NewScheduler(RootExecution(), tc.args) }).(Fault)
		if !ok || fault.Message != tc.want {
			t.Fatalf("%s native fault = %#v, want %q", tc.name, fault, tc.want)
		}
	}
	// Keep the existing internal -1 history sentinel and zero unlimited limit.
	ctx := RootExecution()
	scheduler := NewScheduler(ctx, []Argument{{"history_limit", int32(-1)}}).(*Scheduler)
	if scheduler.historyLimit != -1 || scheduler.limit != 0 {
		t.Fatal("internal omitted-bound sentinels changed")
	}
	scheduler.close(ctx)
	for _, raw := range []Value{Duration(-1), optional("@std/Duration", Duration(-1), true)} {
		fault, ok := recovered(func() { NewTaskGroup(RootExecution(), []Argument{{"timeout", raw}}) }).(Fault)
		if !ok || fault.Message != "TaskGroup: timeout (nanoseconds) must be between 0 and 9223372036854775807, found -1" {
			t.Fatalf("TaskGroup fault = %#v", fault)
		}
		cancelledContext, cancel := context.WithCancel(context.Background())
		execution := newExecution(RootExecution(), cancelledContext)
		cancel()
		if _, ok := recovered(func() { NewTaskGroup(execution, []Argument{{"timeout", raw}}) }).(cancelled); !ok {
			t.Fatal("cancelled TaskGroup constructor became a precondition/domain failure")
		}
	}
	cancelledContext, cancel := context.WithCancel(context.Background())
	execution := newExecution(RootExecution(), cancelledContext)
	cancel()
	if _, ok := recovered(func() { Invoke(execution, StandardFunction("sleep", "Unit"), []Argument{{"duration", Duration(-1)}}) }).(cancelled); !ok {
		t.Fatal("cancelled sleep became a precondition/domain failure")
	}
}
