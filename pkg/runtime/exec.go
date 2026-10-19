package msruntime

import "context"

// Execution carries cancellation, call depth, and the services of one running
// task. Every generated function and native operation takes it first.
//
// Copies made for cancellation scopes (see Shield) share call state.
type Execution struct {
	Context context.Context
	State   *State
	calls   *callState

	comparing map[[2]any]struct{} // pairs under structural comparison (equality.go)
}

// State is the per-program runtime state an Execution reaches: host roots.
// Its fields are owned by the runtime core (host.go).
type State struct {
	Program *ProgramState // program arguments (program.go)
	Host    *HostRoots    // standard streams, arguments, environment (host.go)
}

// callState tracks one goroutine's nested calls. Copies of an Execution made
// for cancellation scopes share it.
type callState struct {
	depth int
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
		Context: ctx,
		State:   &State{Program: &ProgramState{Arguments: arguments}, Host: &HostRoots{}},
		calls:   &callState{},
	}
	if hostArguments != nil {
		hostArguments(e, arguments)
	}
	return e
}

// child is a new operation of the same program with its own call state.
func (e *Execution) child(ctx context.Context) *Execution {
	return &Execution{Context: ctx, State: e.State, calls: &callState{}}
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
		pollCancelled(ctx)
	}
}

// PollIndex is Poll for range loops, which already count their iterations.
func PollIndex(ctx *Execution, index int) {
	if index&63 == 63 {
		pollCancelled(ctx)
	}
}

// Keep periodic polling small enough to inline its counter and bit test into
// native traversals. Direct cancellation checks retain their ordinary inlining.
//
//go:noinline
func pollCancelled(ctx *Execution) { CheckCancelled(ctx) }
