package compiler_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

func TestTaskGroupTypeBoundaries(t *testing.T) {
	prefix := `import { TaskGroup, Task, ExecutionError } from "@std/tasks.ms"
`
	for _, tt := range []struct{ name, body, want string }{
		{"task constructor", "fn f() -> Unit:\n    let task = Task[Int]()\n", "no source constructor"},
		{"callback arity", "fn work(value: Int) -> Int: return value\nfn f(group: TaskGroup) -> Unit:\n    group.start(work)\n", "expected fn()"},
		{"nonfunction callback", "fn f(group: TaskGroup) -> Unit:\n    group.start(3)\n", "cannot infer"},
		{"result mismatch", "fn f(group: TaskGroup) -> Unit:\n    let task: Task[String] = group.start(fn() -> Int: return 3)\n", "expected fn()->String, found fn()->Int"},
		{"group result is Unit", "fn f(group: TaskGroup) -> Result[Int, ExecutionError]:\n    return group.join()\n", "expected Result[Int"},
		{"no task equality", "fn f(task: Task[Int]) -> Bool:\n    return task == task\n", "equality requires Equal"},
		{"no group cloning", "fn f(group: TaskGroup) -> Unit:\n    group.clone()\n", "unknown or ambiguous member"},
		{"unspecialized start value", "fn f(group: TaskGroup) -> Unit:\n    let start = group.start\n", "requires explicit specialization"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			result := compiler.CompileSource("tasks.ms", prefix+tt.body, compiler.Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("accepted invalid task usage")
			}
			found := false
			for _, d := range result.Diagnostics {
				if strings.Contains(d.Message, tt.want) {
					found = true
				}
			}
			if !found {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}
