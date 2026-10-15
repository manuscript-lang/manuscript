package msruntime

import (
	"fmt"
	"os"
	goruntime "runtime"
	"sync"
	"sync/atomic"
	"time"
)

// TaskState is the per-program task state an Execution reaches. The work
// lifetime, schedulers and task groups of an operation hang off its
// Execution (lifetime.go); TaskState holds what the whole program shares.
type TaskState struct {
	// Arguments are the program arguments given to RunMain. The host module
	// reads them from here (or from the hostArguments hook, run at startup).
	Arguments []string
}

// hostArguments is set by the host module. RunMain/RunTests call it with the
// program arguments when they create the root execution, before main runs, so
// the host can fill State.Host. Arguments are also kept in State.Tasks.
var hostArguments func(*Execution, []string)

// hostShutdown is set by the host module. RunMain/RunTests call it after main
// and every joined operation finished, to close standard streams and
// network roots. It runs shielded and a fault in it is reported like any
// cleanup fault.
var hostShutdown func(*Execution)

// OperationId identifies work for diagnostics, status and cancellation. It
// has identity: each id is a distinct pointer and ids are never reused.
type OperationId struct{ number uint64 }

var nextOperation atomic.Uint64

func newOperationId() *OperationId { return &OperationId{nextOperation.Add(1)} }

// Tasks_YieldNow suspends the current task briefly so other ready work runs.
func Tasks_YieldNow(ctx *Execution) Unit {
	CheckCancelled(ctx)
	goruntime.Gosched()
	CheckCancelled(ctx)
	return Unit{}
}

// sleepFor waits for d or until the execution is cancelled.
func sleepFor(ctx *Execution, d time.Duration) {
	if d <= 0 {
		CheckCancelled(ctx)
		return
	}
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-timer.C:
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	}
}

// durationFault raises the fault for an out-of-range duration parameter.
func durationFault(operation, parameter string, nanoseconds int64) {
	Raise(fmt.Sprintf("%s: %s (nanoseconds) must be between 0 and %d, found %d", operation, parameter, int64(^uint64(0)>>1), nanoseconds))
}

// minRangeFault raises the fault for an out-of-range integer parameter.
func minRangeFault(operation, parameter string, minimum, value int64) {
	Raise(fmt.Sprintf("%s: %s must be between %d and %d, found %d", operation, parameter, minimum, int64(^uint64(0)>>1), value))
}

// Errors_Message_ExecutionError is the Error message of an ExecutionError.
func Errors_Message_ExecutionError(_ *Execution, e ExecutionError) string {
	switch e := e.(type) {
	case ExecutionError_Crashed:
		return e.Message
	case ExecutionError_Timeout:
		return "task execution: operation timed out"
	}
	return "task execution: operation cancelled"
}

// Errors_Message_StartError is the Error message of a StartError.
func Errors_Message_StartError(_ *Execution, e StartError) string {
	switch e.(type) {
	case StartError_Closed:
		return "scheduler: resource is closed"
	case StartError_Full:
		return "scheduler: capacity exhausted"
	}
	return "scheduler: invalid input"
}

// diagnosticOutput writes one diagnostic line; tests replace it.
var diagnosticOutput = func(message string) { fmt.Fprintln(os.Stderr, message) }

// diagnostics serializes runtime diagnostics to standard error so scheduler
// failure reports never interleave. The writer touches only strings.
var diagnostics = struct {
	once  sync.Once
	queue chan string
	work  sync.WaitGroup
}{queue: make(chan string, 128)}

func reportDiagnostic(message string) {
	diagnostics.once.Do(func() {
		go func() {
			for m := range diagnostics.queue {
				diagnosticOutput(m)
				diagnostics.work.Done()
			}
		}()
	})
	diagnostics.work.Add(1)
	select {
	case diagnostics.queue <- message:
	default:
		diagnostics.work.Done()
		diagnosticOutput("runtime diagnostic buffer overflow")
	}
}

// FlushDiagnostics waits until every queued diagnostic has been written.
func FlushDiagnostics() { diagnostics.work.Wait() }
