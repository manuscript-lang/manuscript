package msruntime

import (
	"math"
	"testing"
)

func TestTestingAssertionsAndFaultBoundaries(t *testing.T) {
	ctx := RootExecution()
	call := func(name string, args ...Value) Value {
		return invokeLibrary(libraryFunctions["testing/"+name], ctx, "Unit", args)
	}
	call("expect_equal", int64(1), int64(1))
	call("expect_close", math.Inf(1), math.Inf(1), 0.0)
	for _, args := range [][]Value{{math.NaN(), 1.0, 0.1}, {1.0, 1.0, -0.1}, {1.0, 1.0, math.Inf(1)}} {
		_, caught := testingFault(ctx, NewFunction(nil, "Unit", func(*Execution, []Value) Value { return call("expect_close", args...) }))
		if !caught {
			t.Fatalf("accepted close %v", args)
		}
	}
	for _, failure := range []Value{testSkip{"reason"}, cancelled{}} {
		func() {
			defer func() {
				if got := recover(); got != failure {
					t.Fatalf("fault assertion swallowed %T: %v", failure, got)
				}
			}()
			call("expect_fault", NewFunction(nil, "Unit", func(*Execution, []Value) Value { panic(failure) }))
		}()
	}
}
