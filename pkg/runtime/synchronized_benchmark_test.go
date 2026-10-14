package msruntime

import "testing"

func BenchmarkSynchronizedUncontended(b *testing.B) {
	root, cell := RootExecution(), synchronizedInt()
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		guard := lockCell(root, cell)
		guard.close()
	}
}

func BenchmarkSynchronizedTaskLifecycle(b *testing.B) {
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

func BenchmarkSynchronizedIndependentTasks(b *testing.B) {
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
