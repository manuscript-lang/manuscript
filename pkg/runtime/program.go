package msruntime

import (
	"fmt"
	"math"
	"os"
	"sync"
)

// ProgramState is what the whole program shares through its Executions.
type ProgramState struct {
	// Arguments are the program arguments given to RunMain. The host module
	// reads them from here (or from the hostArguments hook, run at startup).
	Arguments []string
}

// hostArguments is set by the host module. RunMain/RunTests call it with the
// program arguments when they create the root execution, before main runs, so
// the host can fill State.Host. Arguments are also kept in State.Program.
var hostArguments func(*Execution, []string)

// hostShutdown is set by the host module. RunMain/RunTests call it after main
// and every joined operation finished, to close standard streams and
// network roots. It runs shielded and a fault in it is reported like any
// cleanup fault.
var hostShutdown func(*Execution)

// minRangeFault raises the fault for an out-of-range integer parameter.
func minRangeFault(operation, parameter string, minimum, value int) {
	Raise(fmt.Sprintf("%s: %s must be between %d and %d, found %d", operation, parameter, minimum, math.MaxInt, value))
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
