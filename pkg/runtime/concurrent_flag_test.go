package msruntime

import "testing"

// A program that never starts work keeps lock-free record access: RunMain's
// signal goroutine and the diagnostics writer never touch records.
func TestRunMainWithoutWorkStaysSingleThreaded(t *testing.T) {
	concurrentWork.Store(false)
	t.Cleanup(func() { concurrentWork.Store(false) })
	main := NewFunction(nil, "Int", func(*Execution, []Value) Value { return int64(0) })
	if exit := RunMain(main, nil); exit != 0 {
		t.Fatalf("exit = %d", exit)
	}
	if concurrentWork.Load() {
		t.Fatal("RunMain marked concurrent work without spawning any")
	}
}
