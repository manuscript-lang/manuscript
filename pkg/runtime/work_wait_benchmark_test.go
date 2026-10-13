package msruntime

import (
	"crypto/sha256"
	"testing"
	"time"
)

func BenchmarkIssue148Uncontended(b *testing.B) {
	root := RootExecution()
	cell := synchronizedInt()
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		guard := lockCell(root, cell)
		guard.close()
	}
}
func BenchmarkIssue148TaskGroup(b *testing.B) {
	root := RootExecution()
	callback := NewFunction(nil, "Unit", func(*Execution, []Value) Value { return Unit{} })
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		group := NewTaskGroup(root, nil).(*TaskGroup)
		task := groupTask(root, group, callback)
		taskResult(root, task)
		group.close(root)
	}
}

func BenchmarkIssue148TaskGroupFanout(b *testing.B) {
	root := RootExecution()
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		gate := make(chan struct{})
		callback := NewFunction(nil, "Unit", func(*Execution, []Value) Value { <-gate; return Unit{} })
		group := NewTaskGroup(root, nil).(*TaskGroup)
		for range 8 {
			groupTask(root, group, callback)
		}
		close(gate)
		group.join(root, "@std/Result[Unit][ExecutionError]")
		group.close(root)
	}
}

func BenchmarkIssue148IndependentTaskThroughput(b *testing.B) {
	callback := NewFunction(nil, "Unit", func(*Execution, []Value) Value { return Unit{} })
	b.ReportAllocs()
	b.RunParallel(func(pb *testing.PB) {
		root := RootExecution()
		for pb.Next() {
			group := NewTaskGroup(root, nil).(*TaskGroup)
			task := groupTask(root, group, callback)
			taskResult(root, task)
			group.close(root)
		}
	})
}

// Run actual checked arithmetic and a bulk native CPU operation inside tasks,
// rather than inferring application cost from empty callbacks alone.
func BenchmarkIssue148TaskArithmetic1000(b *testing.B) {
	callback := NewFunction(nil, "Int", func(child *Execution, _ []Value) Value {
		var result int64
		for i := int64(0); i < 1000; i++ {
			CheckCancelled(child)
			result = IntAdd(result, i)
		}
		return result
	})
	benchmarkIssue148TaskValue(b, callback, int64(499500))
}
func BenchmarkIssue148TaskSHA25664KiB(b *testing.B) {
	data := make([]byte, 64*1024)
	expected := int64(sha256.Sum256(data)[0])
	callback := NewFunction(nil, "Int", func(*Execution, []Value) Value { return int64(sha256.Sum256(data)[0]) })
	benchmarkIssue148TaskValue(b, callback, expected)
}
func benchmarkIssue148TaskValue(b *testing.B, callback Function, expected int64) {
	b.Helper()
	b.ReportAllocs()
	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		root := RootExecution()
		for pb.Next() {
			group := NewTaskGroup(root, nil).(*TaskGroup)
			task := groupTask(root, group, callback)
			result := taskResult(root, task)
			group.close(root)
			if result.Tag != "ok" || result.Fields[0] != expected {
				b.Fatal(result)
			}
		}
	})
}

// This uses the reporter's original 20 ms child/100 ms holder timing and
// validates the result. The old ancestor-exclusion baseline fails it, so only
// revisions which already permit ancestor overlap can be compared for speed.
func BenchmarkIssue148OriginalContention(b *testing.B) {
	root := RootExecution()
	cell := synchronizedInt()
	callback := NewFunction(nil, "Int", func(child *Execution, _ []Value) Value {
		time.Sleep(20 * time.Millisecond)
		locked := lockCell(child, cell)
		defer locked.close()
		return locked.Operation("get").Body(child, nil)
	})
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		group := NewTaskGroup(root, nil).(*TaskGroup)
		task := groupTask(root, group, callback)
		locked := lockCell(root, cell)
		time.Sleep(100 * time.Millisecond)
		locked.Operation("set").Body(root, []Value{int64(7)})
		locked.close()
		result := taskResult(root, task)
		group.close(root)
		if result.Tag != "ok" || result.Fields[0] != int64(7) {
			b.Fatal(result)
		}
	}
}
