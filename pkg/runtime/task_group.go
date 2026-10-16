package msruntime

import (
	"context"
	"fmt"
	"sync"
	"time"
)

// TaskGroup starts child tasks and joins them. It owns a fixed parent
// execution (the execution of its first use, because the lowerer's
// New<Type> carries none) and seals admission at its first join. All state
// transitions and outcome publication share mu; cleanup finishes before a task
// publishes its result or contributes to the group's joined outcome.
type TaskGroup struct {
	timeout Option[Duration]

	mu                                sync.Mutex
	parent                            *Execution
	context                           context.Context
	cancel                            context.CancelFunc
	timer                             *time.Timer
	expired                           bool
	active                            int
	sealed, closing, closed, observed bool
	failure                           ExecutionError
	workers                           sync.WaitGroup
	joined                            chan struct{}
	closedDone                        chan struct{}
}

// Task is a handle to a child task of a group.
type Task[T any] struct {
	group     *TaskGroup
	id        *OperationId
	done      chan struct{}
	value     T
	committed bool
}

// NewTaskGroup constructs a TaskGroup with an optional time budget.
func NewTaskGroup(timeout Option[Duration]) *TaskGroup {
	if timeout.Some && timeout.Val < 0 {
		durationFault("TaskGroup", "timeout", int(timeout.Val))
	}
	return &TaskGroup{timeout: timeout}
}

// adopt fixes the group's parent execution on first use.
func (g *TaskGroup) adopt(ctx *Execution) {
	g.mu.Lock()
	if g.parent != nil {
		g.mu.Unlock()
		return
	}
	g.parent = ctx
	g.context, g.cancel = context.WithCancel(ctx.Context)
	g.closedDone = make(chan struct{})
	g.mu.Unlock()
	registerResource(ctx, g)
}

func (g *TaskGroup) stopLocked(failure ExecutionError) {
	if g.failure == nil {
		g.failure = failure
	}
	g.cancel()
}

// TaskGroup_Start starts operation as a concurrent child task.
func TaskGroup_Start[T any](ctx *Execution, g *TaskGroup, operation func(*Execution) T) *Task[T] {
	CheckCancelled(ctx)
	g.adopt(ctx)
	task := &Task[T]{group: g, id: newOperationId(), done: make(chan struct{})}
	g.mu.Lock()
	if g.sealed || g.closing {
		g.mu.Unlock()
		Raise("TaskGroup is joined or closed; start tasks before join/close, or create a new TaskGroup")
	}
	if g.timeout.Some && g.timer == nil && !g.expired {
		if g.timeout.Val == 0 {
			g.expired = true
		} else {
			g.timer = time.AfterFunc(time.Duration(g.timeout.Val), func() {
				g.mu.Lock()
				defer g.mu.Unlock()
				g.expired = true
				if g.active > 0 {
					g.stopLocked(ExecutionError_Timeout{})
				}
			})
		}
	}
	if g.expired {
		g.stopLocked(ExecutionError_Timeout{})
	}
	if g.context.Err() != nil && g.failure == nil {
		g.stopLocked(ExecutionError_Cancelled{})
	}
	if g.failure != nil {
		close(task.done)
		g.mu.Unlock()
		return task
	}
	g.active++
	g.workers.Add(1)
	g.mu.Unlock()
	go func() {
		defer g.workers.Done()
		var value T
		var fault any
		func() {
			defer func() { fault = recover() }()
			child := g.parent.child(g.context).inGroup(g)
			defer FinishExecution(child)
			value = operation(child)
		}()
		g.mu.Lock()
		defer g.mu.Unlock()
		if fault != nil {
			if _, stopped := fault.(cancelled); stopped {
				if g.failure == nil {
					g.stopLocked(ExecutionError_Cancelled{})
				}
			} else {
				// A programming fault takes precedence over a timeout/cancellation.
				if _, crashed := g.failure.(ExecutionError_Crashed); !crashed {
					g.failure = ExecutionError_Crashed{Operation: task.id, Message: fmt.Sprint(fault)}
				}
				g.cancel()
			}
		} else if g.context.Err() == nil {
			task.value, task.committed = value, true
		} else if g.failure == nil {
			g.stopLocked(ExecutionError_Cancelled{})
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
	if ctx.isInGroup(g) {
		Raise("a TaskGroup operation or descendant cannot join or close its own group")
	}
}

func (g *TaskGroup) wait(ctx *Execution) {
	g.rejectSelf(ctx)
	g.adopt(ctx)
	g.mu.Lock()
	done := g.sealLocked()
	g.mu.Unlock()
	select {
	case <-done:
	case <-ctx.Context.Done():
		g.mu.Lock()
		g.stopLocked(ExecutionError_Cancelled{})
		g.mu.Unlock()
		<-done
	}
	CheckCancelled(ctx)
}

func (g *TaskGroup) join(ctx *Execution) Result[Unit, ExecutionError] {
	g.wait(ctx)
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.failure != nil {
		g.observed = true
		return Fail[Unit, ExecutionError](g.failure)
	}
	return Ok[Unit, ExecutionError](Unit{})
}

// TaskGroup_Join seals admission and waits for every task and its cleanup.
func TaskGroup_Join(ctx *Execution, g *TaskGroup) Result[Unit, ExecutionError] {
	return g.join(ctx)
}

// Task_Join waits for the task and returns its result, or the group failure.
func Task_Join[T any](ctx *Execution, t *Task[T]) Result[T, ExecutionError] {
	g := t.group
	g.rejectSelf(ctx)
	select {
	case <-t.done:
	case <-ctx.Context.Done():
		g.mu.Lock()
		g.stopLocked(ExecutionError_Cancelled{})
		g.mu.Unlock()
		g.wait(ctx)
	}
	if ctx.Context.Err() != nil {
		g.mu.Lock()
		g.stopLocked(ExecutionError_Cancelled{})
		g.mu.Unlock()
		g.wait(ctx)
	}
	CheckCancelled(ctx)
	g.mu.Lock()
	if t.committed {
		value := t.value
		g.mu.Unlock()
		return Ok[T, ExecutionError](value)
	}
	g.mu.Unlock()
	// Failure reporting is a group boundary: siblings finish cleanup first.
	failed := g.join(ctx)
	return Fail[T, ExecutionError](failed.Err)
}

// TaskGroup_Close cancels unfinished tasks, waits for them and releases the
// group. Calling it again waits for the first close.
func TaskGroup_Close(ctx *Execution, g *TaskGroup) Unit {
	g.close(ctx)
	return Unit{}
}

func (g *TaskGroup) closeWork(ctx *Execution) { g.close(ctx) }

func (g *TaskGroup) close(ctx *Execution) {
	g.rejectSelf(ctx)
	g.adopt(ctx)
	g.mu.Lock()
	if g.closing {
		done := g.closedDone
		g.mu.Unlock()
		<-done
		return
	}
	g.closing = true
	if g.active > 0 {
		g.stopLocked(ExecutionError_Cancelled{})
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
	if fault, ok := failure.(ExecutionError_Crashed); ok && !observed {
		if g.parent.Context.Err() != nil {
			reportDiagnostic("TaskGroup fault during cancellation: " + fault.Message)
			return
		}
		Raise("unobserved TaskGroup fault: " + fault.Message)
	}
}
