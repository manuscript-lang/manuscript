package rt

import "context"

// Execution carries cancellation, call depth, and the services of one running
// task. Every generated function and native operation takes it first.
type Execution struct {
	Context context.Context
	State   *State
	calls   *callState
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
	return &Execution{Context: context.Background(), State: &State{Tasks: &TaskState{}, Host: &HostRoots{}}, calls: &callState{}}
}

// CheckCancelled unwinds the task if its context is done.
func CheckCancelled(ctx *Execution) {
	if ctx != nil && ctx.Context.Err() != nil {
		panic(cancelled{})
	}
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
