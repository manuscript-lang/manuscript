package msruntime

import (
	"testing"
	"time"
)

func BenchmarkIssue148ContendedLock(b *testing.B) {
	owner, contender := RootExecution(), RootExecution()
	cell := synchronizedInt()
	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		guard := lockCell(owner, cell)
		waiting := &synchronizedLockWaitContext{Context: contender.Context, cell: cell, lifetime: contender.Lifetime, entered: make(chan struct{})}
		done := synchronizedCall(func() Value { locked := lockCell(inherit(contender, waiting), cell); locked.close(); return Unit{} })
		timer.Reset(2 * time.Second)
		select {
		case <-waiting.entered:
		case <-timer.C:
			guard.close()
			b.Fatal("contender did not register")
		}
		guard.close()
		select {
		case result := <-done:
			if result.failure != nil {
				b.Fatal(result.failure)
			}
		case <-timer.C:
			b.Fatal("contender did not finish")
		}
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
	}
}
func BenchmarkIssue148ContendedTask(b *testing.B) {
	root := RootExecution()
	cell := synchronizedInt()
	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		guard := lockCell(root, cell)
		group := NewTaskGroup(root, nil).(*TaskGroup)
		entered := make(chan struct{})
		task := groupTask(root, group, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
			waiting := &synchronizedLockWaitContext{Context: child.Context, cell: cell, lifetime: child.Lifetime, entered: entered}
			locked := lockCell(inherit(child, waiting), cell)
			locked.close()
			return Unit{}
		}))
		timer.Reset(2 * time.Second)
		select {
		case <-entered:
		case <-timer.C:
			guard.close()
			b.Fatal("task did not register")
		}
		guard.close()
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
		result := taskResult(root, task)
		if result.Tag != "ok" {
			b.Fatal(result)
		}
		group.close(root)
	}
}
