package msruntime

import (
	"fmt"
	"math"
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
