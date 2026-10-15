package rt

import "context"

// Execution carries cancellation, call depth, and the services of one running
// task. Every generated function and native operation takes it first.
//
// Copies made for cancellation scopes (see Shield) share calls, lifetime and
// ownership, so a shielded cleanup is the same operation as its initiator for
// the purposes of lock reentry and self-join checks.
type Execution struct {
	Context context.Context
	State   *State
	calls   *callState

	lifetime *workLifetime // services opened by this operation (lifetime.go)
	owners   []*Scheduler  // schedulers whose operation or reporter this is
	groups   []*TaskGroup  // task groups this operation runs inside

	comparing map[[2]any]struct{} // pairs under structural comparison (equality.go)
}

// State is the per-program runtime state an Execution reaches: work
// lifetimes, schedulers, task groups, and host roots. Its fields are owned by
// the runtime core (lifetime.go, scheduler.go, host.go).
type State struct {
	Tasks *TaskState // schedulers, task groups, work lifetime (tasks.go)
	Host  *HostRoots // standard streams, arguments, environment (host.go)
}

// callState tracks one goroutine's nested calls. Copies of an Execution made
// for cancellation scopes share it.
type callState struct {
	depth int64
	ticks uint8
}

// cancelled is the panic payload that unwinds a cancelled task.
type cancelled struct{}

// RootExecution is the execution of a program's main task.
func RootExecution() *Execution {
	return rootExecution(context.Background(), nil)
}

func rootExecution(ctx context.Context, arguments []string) *Execution {
	e := &Execution{
		Context:  ctx,
		State:    &State{Tasks: &TaskState{Arguments: arguments}, Host: &HostRoots{}},
		calls:    &callState{},
		lifetime: &workLifetime{},
	}
	if hostArguments != nil {
		hostArguments(e, arguments)
	}
	return e
}

// child is a new operation of the same program: its own call state and work
// lifetime, and the ownership of its parent.
func (e *Execution) child(ctx context.Context) *Execution {
	return &Execution{Context: ctx, State: e.State, calls: &callState{}, lifetime: &workLifetime{parent: e.lifetime}, owners: e.owners, groups: e.groups}
}

func (e *Execution) ownedBy(owner *Scheduler) *Execution {
	e.owners = append(e.owners[:len(e.owners):len(e.owners)], owner)
	return e
}

func (e *Execution) inGroup(group *TaskGroup) *Execution {
	e.groups = append(e.groups[:len(e.groups):len(e.groups)], group)
	return e
}

func (e *Execution) isOwnedBy(owner *Scheduler) bool {
	for _, o := range e.owners {
		if o == owner {
			return true
		}
	}
	return false
}

func (e *Execution) isInGroup(group *TaskGroup) bool {
	for _, g := range e.groups {
		if g == group {
			return true
		}
	}
	return false
}

func isDone(ctx context.Context) bool { return ctx.Err() != nil }

// CheckCancelled unwinds the task if its context is done.
func CheckCancelled(ctx *Execution) Unit {
	if ctx != nil && isDone(ctx.Context) {
		panic(cancelled{})
	}
	return Unit{}
}

// Shield returns an execution that keeps running through cancellation, for
// cleanup.
func Shield(ctx *Execution) *Execution {
	c := *ctx
	c.Context = context.WithoutCancel(ctx.Context)
	return &c
}

// Poll counts a loop iteration and checks for cancellation on every 64th.
func Poll(ctx *Execution, tick *uint32) {
	if *tick++; *tick&63 == 0 {
		CheckCancelled(ctx)
	}
}

// PollIndex is Poll for range loops, which already count their iterations.
func PollIndex(ctx *Execution, index int) {
	if index&63 == 63 {
		CheckCancelled(ctx)
	}
}
