package rt

import (
	msruntime "github.com/manuscript-lang/manuscript/pkg/runtime"
)

// Test is one test block of the generated program.
type Test struct {
	Name string
	Run  func(*Execution) Unit
}

// RunMain runs the program's main function and returns its exit status.
func RunMain(main func(*Execution) int64, args []string) int {
	return msruntime.RunMain(msruntime.NewFunction(nil, "Int", func(ctx *msruntime.Execution, _ []msruntime.Value) msruntime.Value {
		return main(ctx)
	}), args)
}

// RunTests runs the test blocks and returns the number that failed.
func RunTests(tests []Test, args []string) int {
	wrapped := make([]msruntime.Test, len(tests))
	for i, t := range tests {
		run := t.Run
		wrapped[i] = msruntime.Test{Name: t.Name, Run: msruntime.NewFunction(nil, "Unit", func(ctx *msruntime.Execution, _ []msruntime.Value) msruntime.Value {
			run(ctx)
			return msruntime.Unit{}
		})}
	}
	return msruntime.RunTestsArgs(wrapped, args)
}

// Poll counts a loop iteration and checks for cancellation on every 64th.
func Poll(ctx *Execution, tick *uint32) {
	if *tick++; *tick&63 == 0 {
		msruntime.CheckCancelled(ctx)
	}
}

// Unreachable marks code a checked program cannot reach.
func Unreachable() { Fault("runtime invariant: unreachable") }

// Zero is the zero value of T.
func Zero[T any]() T {
	var zero T
	return zero
}

// Panic raises a programming fault with message; it never returns.
func Panic(_ *Execution, message string) Unit {
	Fault(message)
	return Unit{}
}
