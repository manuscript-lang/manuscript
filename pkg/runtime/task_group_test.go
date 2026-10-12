package msruntime

import (
	"context"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func groupTask(ctx *Execution, group *TaskGroup, f Function) *Task {
	return Invoke(ctx, NativeMemberResult(group, "start", "@std/Task["+f.Result+"]"), []Argument{{"operation", f}}).(*Task)
}
func taskResult(ctx *Execution, task *Task) Alternative {
	return Invoke(ctx, task.Operation("join"), nil).(Alternative)
}
func groupResult(ctx *Execution, group *TaskGroup) Alternative {
	return Invoke(ctx, group.Operation("join"), nil).(Alternative)
}
func TestTaskGroupTypedResultsAndRepeatedJoins(t *testing.T) {
	root := RootExecution()
	group := NewTaskGroup(root, nil).(*TaskGroup)
	defer group.close(root)
	var calls atomic.Int64
	domain := Alternative{"@std/Result[Int][String]", "error", []Value{"domain failure"}}
	first := groupTask(root, group, NewFunction(nil, "@std/Result[Int][String]", func(*Execution, []Value) Value { calls.Add(1); return domain }))
	second := groupTask(root, group, NewFunction(nil, "String", func(*Execution, []Value) Value { calls.Add(1); return "hello" }))
	for range 3 {
		if outcome := groupResult(root, group); outcome.Tag != "ok" {
			t.Fatal(outcome)
		}
		if outcome := taskResult(root, first); outcome.Type != "@std/Result[@std/Result[Int][String]][@std/ExecutionError]" || outcome.Fields[0].(Alternative).Tag != "error" {
			t.Fatal(outcome)
		}
		if outcome := taskResult(root, second); outcome.Fields[0] != "hello" {
			t.Fatal(outcome)
		}
	}
	if calls.Load() != 2 {
		t.Fatal("a join reran a callback")
	}
	if _, ok := recovered(func() {
		groupTask(root, group, NewFunction(nil, "Unit", func(*Execution, []Value) Value { return Unit{} }))
	}).(Fault); !ok {
		t.Fatal("admission after join")
	}
	group.close(root)
	if taskResult(root, second).Fields[0] != "hello" {
		t.Fatal("close erased a committed result")
	}
}
func TestTaskJoinAllowsFurtherAdmission(t *testing.T) {
	root := RootExecution()
	group := NewTaskGroup(root, nil).(*TaskGroup)
	defer group.close(root)
	first := groupTask(root, group, NewFunction(nil, "Int", func(*Execution, []Value) Value { return int64(1) }))
	if taskResult(root, first).Fields[0] != int64(1) {
		t.Fatal("first result")
	}
	second := groupTask(root, group, NewFunction(nil, "Int", func(*Execution, []Value) Value { return int64(2) }))
	if taskResult(root, second).Fields[0] != int64(2) {
		t.Fatal("second result")
	}
}
func TestTaskGroupCloseAndExecutionExitJoinCleanup(t *testing.T) {
	for _, executionExit := range []bool{false, true} {
		root := RootExecution()
		group := NewTaskGroup(root, nil).(*TaskGroup)
		started, cleaned := make(chan struct{}), make(chan struct{})
		task := groupTask(root, group, NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
			defer close(cleaned)
			close(started)
			<-ctx.Context.Done()
			CheckCancelled(ctx)
			return Unit{}
		}))
		<-started
		var callers sync.WaitGroup
		for range 8 {
			callers.Add(1)
			go func() { defer callers.Done(); group.close(root) }()
		}
		if executionExit {
			FinishExecution(root)
		}
		callers.Wait()
		select {
		case <-cleaned:
		default:
			t.Fatal("close returned before cleanup")
		}
		if outcome := taskResult(root, task); outcome.Tag != "error" || outcome.Fields[0].(Alternative).Tag != "Cancelled" {
			t.Fatal(outcome)
		}
		group.mu.Lock()
		closed := group.closed
		group.mu.Unlock()
		if !closed {
			t.Fatal("close did not commit")
		}
	}
}
func TestTaskGroupCannotJoinOrCloseAncestor(t *testing.T) {
	for _, action := range []string{"group join", "task join", "group close", "descendant join"} {
		t.Run(action, func(t *testing.T) {
			root := RootExecution()
			group := NewTaskGroup(root, nil).(*TaskGroup)
			defer group.close(root)
			release := make(chan struct{})
			var self *Task
			f := NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
				<-release
				switch action {
				case "group join":
					groupResult(ctx, group)
				case "task join":
					taskResult(ctx, self)
				case "group close":
					group.close(ctx)
				case "descendant join":
					nested := NewTaskGroup(ctx, nil).(*TaskGroup)
					defer nested.close(Shield(ctx))
					groupTask(ctx, nested, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value { groupResult(child, group); return Unit{} }))
					outcome := groupResult(ctx, nested)
					if outcome.Tag != "error" {
						return Panic("ancestor join accepted")
					}
					return Panic("descendant join rejected")
				}
				return Unit{}
			})
			self = groupTask(root, group, f)
			close(release)
			outcome := groupResult(root, group)
			if outcome.Tag != "error" || outcome.Fields[0].(Alternative).Tag != "Crashed" {
				t.Fatal(outcome)
			}
		})
	}
}
func TestTaskGroupTimeoutAndFixedParent(t *testing.T) {
	root := RootExecution()
	group := NewTaskGroup(root, []Argument{{"timeout", Duration(20 * time.Millisecond)}}).(*TaskGroup)
	defer group.close(root)
	submitContext, cancelSubmit := context.WithCancel(root.Context)
	submit := inherit(root, submitContext)
	entered, cleaned := make(chan struct{}), make(chan struct{})
	task := groupTask(submit, group, NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
		defer close(cleaned)
		close(entered)
		<-ctx.Context.Done()
		CheckCancelled(ctx)
		return Unit{}
	}))
	<-entered
	cancelSubmit()
	if group.context.Err() != nil {
		t.Fatal("submission reparented work")
	}
	outcome := taskResult(root, task)
	if outcome.Tag != "error" || outcome.Fields[0].(Alternative).Tag != "TimedOut" {
		t.Fatal(outcome)
	}
	select {
	case <-cleaned:
	default:
		t.Fatal("timeout skipped cleanup")
	}
	if recovered(func() { NewTaskGroup(root, []Argument{{"timeout", Duration(-1)}}) }) == nil {
		t.Fatal("negative timeout")
	}
}
func TestTaskGroupCancelledTaskJoinWaitsForSiblings(t *testing.T) {
	root := RootExecution()
	group := NewTaskGroup(root, nil).(*TaskGroup)
	defer group.close(root)
	cleaned := make(chan struct{})
	fast := groupTask(root, group, NewFunction(nil, "Int", func(*Execution, []Value) Value { return int64(1) }))
	entered := make(chan struct{})
	groupTask(root, group, NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
		defer close(cleaned)
		close(entered)
		<-ctx.Context.Done()
		CheckCancelled(ctx)
		return Unit{}
	}))
	<-entered
	<-fast.done
	cancelledContext, cancel := context.WithCancel(root.Context)
	cancel()
	// Invoke would checkpoint before entering join; call the join primitive to
	// exercise cancellation racing with an already available task result.
	failure := recovered(func() { fast.join(inherit(root, cancelledContext), "result") })
	if _, ok := failure.(cancelled); !ok {
		t.Fatal(failure)
	}
	select {
	case <-cleaned:
	default:
		t.Fatal("cancelled join skipped sibling cleanup")
	}
}
func TestTaskGroupUnobservedFaultSurfacesAtClose(t *testing.T) {
	root := RootExecution()
	group := NewTaskGroup(root, nil).(*TaskGroup)
	task := groupTask(root, group, NewFunction(nil, "Unit", func(*Execution, []Value) Value { return Panic("lost fault") }))
	<-task.done
	failure := recovered(func() { group.close(root) })
	if fault, ok := failure.(Fault); !ok || !strings.Contains(fault.Message, "lost fault") {
		t.Fatal(failure)
	}
	group.close(root)
}

func TestTaskGroupAdmissionRacesCloseAndJoin(t *testing.T) {
	for _, join := range []bool{false, true} {
		for range 20 {
			root := RootExecution()
			group := NewTaskGroup(root, nil).(*TaskGroup)
			gate := make(chan struct{})
			var callers sync.WaitGroup
			for range 16 {
				callers.Add(1)
				go func() {
					defer callers.Done()
					<-gate
					failure := recovered(func() {
						groupTask(root, group, NewFunction(nil, "Unit", func(*Execution, []Value) Value { return Unit{} }))
					})
					if failure != nil {
						if fault, ok := failure.(Fault); !ok || !strings.Contains(fault.Message, "joined or closed") {
							t.Errorf("unexpected admission outcome: %v", failure)
						}
					}
				}()
			}
			callers.Add(1)
			go func() {
				defer callers.Done()
				<-gate
				if join {
					groupResult(root, group)
				} else {
					group.close(root)
				}
			}()
			close(gate)
			callers.Wait()
			group.close(root)
			group.mu.Lock()
			active := group.active
			group.mu.Unlock()
			if active != 0 {
				t.Fatal("work escaped shutdown")
			}
		}
	}
}
func TestTaskGroupFaultPreservesCompletedTaskAndStopsNewBodies(t *testing.T) {
	root := RootExecution()
	group := NewTaskGroup(root, nil).(*TaskGroup)
	defer group.close(root)
	completed := groupTask(root, group, NewFunction(nil, "Int", func(*Execution, []Value) Value { return int64(9) }))
	if taskResult(root, completed).Fields[0] != int64(9) {
		t.Fatal("completion")
	}
	failed := groupTask(root, group, NewFunction(nil, "Unit", func(*Execution, []Value) Value { return Panic("primary") }))
	<-failed.done
	var invoked atomic.Bool
	stopped := groupTask(root, group, NewFunction(nil, "Unit", func(*Execution, []Value) Value { invoked.Store(true); return Unit{} }))
	outcome := taskResult(root, stopped)
	if outcome.Tag != "error" || outcome.Fields[0].(Alternative).Tag != "Crashed" || invoked.Load() {
		t.Fatal(outcome)
	}
	if taskResult(root, completed).Fields[0] != int64(9) {
		t.Fatal("a sibling fault overwrote a committed result")
	}
}
func TestTaskGroupCleanupFaultTakesPrecedenceOverTimeout(t *testing.T) {
	root := RootExecution()
	group := NewTaskGroup(root, []Argument{{"timeout", Duration(10 * time.Millisecond)}}).(*TaskGroup)
	defer group.close(root)
	entered := make(chan struct{})
	task := groupTask(root, group, NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
		close(entered)
		<-ctx.Context.Done()
		return Panic("cleanup failure")
	}))
	<-entered
	outcome := taskResult(root, task)
	if outcome.Tag != "error" || outcome.Fields[0].(Alternative).Tag != "Crashed" {
		t.Fatal(outcome)
	}
}
