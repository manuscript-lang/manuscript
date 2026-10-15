package rt

// Scheduler is implemented by the tasks module.
type Scheduler struct{}

// OperationId is implemented by the tasks module.
type OperationId struct{}

// TaskGroup is implemented by the tasks module.
type TaskGroup struct{}

// Task is implemented by the tasks module.
type Task[T any] struct{}

// TaskState is the per-program task state an Execution reaches: the work
// lifetime, schedulers and task groups the program has opened.
type TaskState struct{}
