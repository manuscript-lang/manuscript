package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// Unsynchronized field writes from tasks may lose updates, but they must not
// crash the process with Go's "concurrent map writes".
func TestConcurrentRecordFieldWritesDoNotCrash(t *testing.T) {
	result := compiler.CompileSource("fields.ms", `import TaskGroup from "@std/tasks.ms"

export type Counter:
    hits: Int
    last: String

export fn main() Int:
    let counter = Counter(hits: 0, last: "")
    with tasks = TaskGroup():
        var t = 0
        while t < 8:
            let id = t
            tasks.start(fn() Int:
                var i = 0
                while i < 2000:
                    counter.hits = counter.hits + 1
                    counter.last = "t{id}"
                    i = i + 1
                return id
            )
            t = t + 1

        tasks.join()

    return 0
`, compiler.Options{Entry: true})
	data, err := execute(t, result)
	if err != nil || strings.Contains(string(data), "fatal error") {
		t.Fatalf("concurrent writes failed: %v\n%.2000s", err, data)
	}
}
