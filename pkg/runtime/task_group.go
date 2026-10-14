package msruntime

import (
	"context"
	"fmt"
	"sync"
	"time"
)

// TaskGroup owns a fixed parent execution and seals admission at its first join.
// All state transitions and outcome publication share mu; cleanup finishes before
// a task publishes its result or contributes to the group's joined outcome.
type TaskGroup struct {
	mu                                sync.Mutex
	parent                            *Execution
	context                           context.Context
	cancel                            context.CancelFunc
	timeout                           *Duration
	timer                             *time.Timer
	expired                           bool
	active                            int
	sealed, closing, closed, observed bool
	failure                           Value
	workers                           sync.WaitGroup
	joined                            chan struct{}
	closedDone                        chan struct{}
}

type Task struct {
	typ       string
	group     *TaskGroup
	id        OperationId
	done      chan struct{}
	value     Value
	committed bool
}

func NewTaskGroup(ctx *Execution, args []Argument) Value {
	CheckCancelled(ctx)
	var timeout *Duration
	for _, a := range args {
		if a.Name == "timeout" {
			value, valid := nativeOption(a.Value, "Duration", nil)
			if !valid {
				return durationParameterFault("TaskGroup", "timeout", a.Value)
			}
			if value != nil {
				duration := value.(Duration)
				if duration < 0 {
					return durationParameterFault("TaskGroup", "timeout", a.Value)
				}
				timeout = &duration
			}
		}
	}
	groupContext, cancel := context.WithCancel(ctx.Context)
	group := &TaskGroup{parent: ctx, context: groupContext, cancel: cancel, timeout: timeout, closedDone: make(chan struct{})}
	registerResource(ctx, group)
	return group
}

func (g *TaskGroup) Operation(name string) Function {
	function, ok := nativeLibraryMember(g, name, "")
	if !ok {
		Panic("unknown TaskGroup operation " + name)
	}
	return function.(Function)
}
func (t *Task) Operation(name string) Function {
	function, ok := nativeLibraryMember(t, name, "")
	if !ok {
		Panic("unknown Task operation " + name)
	}
	return function.(Function)
}

func (g *TaskGroup) stopLocked(failure Value) {
	if g.failure == nil {
		g.failure = failure
	}
	g.cancel()
}
func executionCancelled() Value { return Alternative{Type: "@std/ExecutionError", Tag: "Cancelled"} }
func executionTimeout() Value   { return Alternative{Type: "@std/ExecutionError", Tag: "Timeout"} }

func (g *TaskGroup) start(ctx *Execution, typ string, operation Value) Value {
	CheckCancelled(ctx)
	task := &Task{typ: typ, group: g, id: newOperationId(), done: make(chan struct{})}
	g.mu.Lock()
	if g.sealed || g.closing {
		g.mu.Unlock()
		return Panic("TaskGroup is joined or closed; start tasks before join/close, or create a new TaskGroup")
	}
	if g.timeout != nil && g.timer == nil && !g.expired {
		if *g.timeout == 0 {
			g.expired = true
		} else {
			g.timer = time.AfterFunc(time.Duration(*g.timeout), func() {
				g.mu.Lock()
				defer g.mu.Unlock()
				g.expired = true
				if g.active > 0 {
					g.stopLocked(executionTimeout())
				}
			})
		}
	}
	if g.expired {
		g.stopLocked(executionTimeout())
	}
	if g.context.Err() != nil && g.failure == nil {
		g.stopLocked(executionCancelled())
	}
	if g.failure != nil {
		close(task.done)
		g.mu.Unlock()
		return task
	}
	g.active++
	g.workers.Add(1)
	g.mu.Unlock()
	markConcurrent()
	go func() {
		defer g.workers.Done()
		var value Value
		var fault any
		func() {
			defer func() { fault = recover() }()
			child := newExecution(g.parent, g.context)
			child.TaskGroups = make(map[*TaskGroup]bool, len(g.parent.TaskGroups)+1)
			for ancestor, owned := range g.parent.TaskGroups {
				child.TaskGroups[ancestor] = owned
			}
			child.TaskGroups[g] = true
			defer FinishExecution(child)
			value = profileWork(child, "task_group.operation", fmt.Sprint(task.id.number), func(execution *Execution) Value { return Invoke(execution, operation, nil) })
		}()
		g.mu.Lock()
		defer g.mu.Unlock()
		if fault != nil {
			if _, cancelled := fault.(cancelled); cancelled {
				if g.failure == nil {
					g.stopLocked(executionCancelled())
				}
			} else {
				failure := Alternative{Type: "@std/ExecutionError", Tag: "Crashed", Fields: []Value{task.id, fmt.Sprint(fault)}}
				// A programming fault takes precedence over a timeout/cancellation.
				if previous, ok := g.failure.(Alternative); !ok || previous.Tag != "Crashed" {
					g.failure = failure
				}
				g.cancel()
			}
		} else if g.context.Err() == nil {
			task.value, task.committed = value, true
		} else if g.failure == nil {
			g.stopLocked(executionCancelled())
		}
		g.active--
		close(task.done)
	}()
	return task
}

func (g *TaskGroup) sealLocked() chan struct{} {
	if !g.sealed {
		g.sealed = true
		g.joined = make(chan struct{})
		markConcurrent()
		go func() {
			g.workers.Wait()
			g.mu.Lock()
			if g.timer != nil {
				g.timer.Stop()
			}
			close(g.joined)
			g.mu.Unlock()
		}()
	}
	return g.joined
}
func (g *TaskGroup) rejectSelf(ctx *Execution) {
	if ctx.TaskGroups[g] {
		Panic("a TaskGroup operation or descendant cannot join or close its own group")
	}
}
func (g *TaskGroup) wait(ctx *Execution) {
	g.rejectSelf(ctx)
	g.mu.Lock()
	done := g.sealLocked()
	g.mu.Unlock()
	select {
	case <-done:
	case <-ctx.Context.Done():
		g.mu.Lock()
		g.stopLocked(executionCancelled())
		g.mu.Unlock()
		<-done
	}
	CheckCancelled(ctx)
}
func (g *TaskGroup) join(ctx *Execution, result string) Value {
	defer profileRegion(ctx, "task_group.join")()
	g.wait(ctx)
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.failure != nil {
		g.observed = true
		return Alternative{result, "error", []Value{g.failure}}
	}
	return Alternative{result, "ok", []Value{Unit{}}}
}
func (t *Task) join(ctx *Execution, result string) Value {
	t.group.rejectSelf(ctx)
	select {
	case <-t.done:
	case <-ctx.Context.Done():
		t.group.mu.Lock()
		t.group.stopLocked(executionCancelled())
		t.group.mu.Unlock()
		t.group.wait(ctx)
	}
	if ctx.Context.Err() != nil {
		t.group.mu.Lock()
		t.group.stopLocked(executionCancelled())
		t.group.mu.Unlock()
		t.group.wait(ctx)
	}
	CheckCancelled(ctx)
	t.group.mu.Lock()
	if t.committed {
		value := t.value
		t.group.mu.Unlock()
		return Alternative{result, "ok", []Value{value}}
	}
	t.group.mu.Unlock()
	// Failure reporting is a group boundary: siblings finish cleanup first.
	return t.group.join(ctx, result)
}
func (g *TaskGroup) close(ctx *Execution) {
	g.rejectSelf(ctx)
	g.mu.Lock()
	if g.closing {
		done := g.closedDone
		g.mu.Unlock()
		<-done
		return
	}
	g.closing = true
	if g.active > 0 {
		g.stopLocked(executionCancelled())
	} else {
		g.cancel()
	}
	done := g.sealLocked()
	g.mu.Unlock()
	<-done
	g.mu.Lock()
	g.closed = true
	failure, observed := g.failure, g.observed
	close(g.closedDone)
	g.mu.Unlock()
	unregisterResource(g.parent, g)
	if fault, ok := failure.(Alternative); ok && fault.Tag == "Crashed" && !observed {
		if g.parent.Context.Err() != nil {
			reportDiagnostic("TaskGroup fault during cancellation: " + fault.Fields[1].(string))
			return
		}
		Panic("unobserved TaskGroup fault: " + fault.Fields[1].(string))
	}
}

func init() {
	libraryGeneric("tasks", "task_group_start", "Task[T]", []LibraryParam{{"T", ""}}, []LibraryParam{{"group", "TaskGroup"}, {"operation", "fn()->T"}}, func(ctx *Execution, result string, args []Value) Value {
		// Direct runtime callers may omit specialization; the callback still has
		// its exact runtime result identity.
		if result == "@std/Task[@std/T]" {
			result = "@std/Task[" + args[1].(Function).Result + "]"
		}
		return args[0].(*TaskGroup).start(ctx, result, args[1])
	})
	libraryAdd("tasks", "task_group_join", "Result[Unit][ExecutionError]", []LibraryParam{{"group", "TaskGroup"}}, func(ctx *Execution, result string, args []Value) Value {
		return args[0].(*TaskGroup).join(ctx, result)
	})
	libraryAdd("tasks", "task_group_close", "Unit", []LibraryParam{{"group", "TaskGroup"}}, func(ctx *Execution, _ string, args []Value) Value {
		args[0].(*TaskGroup).close(ctx)
		return Unit{}
	})
	libraryGeneric("tasks", "task_join", "Result[T][ExecutionError]", []LibraryParam{{"T", ""}}, []LibraryParam{{"task", "Task[T]"}}, func(ctx *Execution, result string, args []Value) Value {
		return args[0].(*Task).join(ctx, result)
	})
}
