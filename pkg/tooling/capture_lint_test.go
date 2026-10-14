package tooling

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestConcurrentCaptureLintReproduction(t *testing.T) {
	source := `import Map from "@std/collections.ms"
import TaskGroup from "@std/tasks.ms"
fn run() -> Unit:
    let counters = {"hits": 0}
    with tasks = TaskGroup():
        let _task = tasks.start(fn():
            counters.add(key: "hits", value: 1)
        )
`
	checked := compiler.CompileSource("capture.ms", source, compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	for _, finding := range LintProgram(checked.Program) {
		if finding.Code == "MSL105" {
			return
		}
	}
	t.Fatal("concurrent mutation of captured Map has no advisory")
}

func TestConcurrentCaptureLint(t *testing.T) {
	imports := `import { Map, List } from "@std/collections.ms"
import { TaskGroup, Scheduler } from "@std/tasks.ms"
import Synchronized from "@std/sync.ms"
import duration from "@std/time.ms"
import network from "@std/net.ms"
type Counter:
    value: Int
`
	cases := []struct {
		name, body string
		count      int
	}{
		{"map update", `    let values = {"hits": 0}
    with tasks = TaskGroup():
        let _task = tasks.start(fn():
            values.add(key: "hits", value: 1)
        )
`, 1},
		{"list update", `    let values = [0]
    with tasks = TaskGroup():
        let _task = tasks.start(fn():
            values.append(1)
        )
`, 1},
		{"list reverse in place", `    let values = [0]
    with tasks = TaskGroup():
        let _task = tasks.start(fn(): values.reverse_in_place())
`, 1},
		{"list reversed copy", `    let values = [0]
    with tasks = TaskGroup():
        let _task = tasks.start(fn(): values.reversed())
`, 0},
		{"list set", `    let values = [0]
    with tasks = TaskGroup():
        let _task = tasks.start(fn(): values.set(0, 1))
`, 1},
		{"list remove", `    let values = [0]
    with tasks = TaskGroup():
        let _task = tasks.start(fn(): values.remove(0))
`, 1},
		{"list splice", `    let values = [0]
    with tasks = TaskGroup():
        let _task = tasks.start(fn(): values.splice(0, 1, [1]))
`, 1},
		{"map remove", `    let values = Map[Int, Int]().add(0, 1)
    with tasks = TaskGroup():
        let _task = tasks.start(fn(): values.remove(0))
`, 1},
		{"set add", `    let values = [0].to_set()
    with tasks = TaskGroup():
        let _task = tasks.start(fn(): values.add(1))
`, 1},
		{"set remove", `    let values = [0].to_set()
    with tasks = TaskGroup():
        let _task = tasks.start(fn(): values.remove(0))
`, 1},
		{"set update", `    let values = [0].to_set()
    with tasks = TaskGroup():
        let _task = tasks.start(fn():
            values.add(1)
        )
`, 1},
		{"read only record", `    let counter = Counter(0)
    with tasks = TaskGroup():
        let _task = tasks.start(fn(): counter.value)
`, 0},
		{"record update", `    let counter = Counter(0)
    with tasks = TaskGroup():
        let _task = tasks.start(fn():
            counter.value = 1
        )
`, 1},
		{"read only", `    let values = {"hits": 0}
    with tasks = TaskGroup():
        let _task = tasks.start(fn(): values.get("hits"))
`, 0},
		{"synchronized update", `    let values = Synchronized({"hits": 0})
    with tasks = TaskGroup():
        let _task = tasks.start(fn():
            with locked = values.lock():
                locked.get().add(key: "hits", value: 1)
        )
`, 0},
		{"guard local update", `    let values = Synchronized({"hits": 0})
    with tasks = TaskGroup():
        let _task = tasks.start(fn():
            with locked = values.lock():
                let protected = locked.get()
                protected.add(key: "hits", value: 1)
        )
`, 0},
		{"local mutation", `    let values = [0]
    with tasks = TaskGroup():
        let _task = tasks.start(fn():
            let values = [1]
            values.append(2)
        )
`, 0},
		{"clone mutation", `    let values = [0]
    with tasks = TaskGroup():
        let _task = tasks.start(fn(): values.clone().append(2))
`, 0},
		{"sequential closure", `    let values = [0]
    let operation = fn(): values.append(1)
    let _result = operation()
`, 0},
		{"unrelated nested closure", `    let values = [0]
    with tasks = TaskGroup():
        let _task = tasks.start(fn():
            let _later = fn(): values.append(1)
        )
`, 0},
		{"nested concurrent callback", `    let values = [0]
    with tasks = TaskGroup():
        let _task = tasks.start(fn():
            with children = TaskGroup():
                let _child = children.start(fn(): values.append(1))
        )
`, 1},
		{"scheduler start", `    let values = [0]
    with jobs = Scheduler():
        let _started = jobs.start(fn() -> Result[Unit, Error]:
            values.append(1)
            return ok(unit)
        )
`, 1},
		{"scheduler after", `    let values = [0]
    with jobs = Scheduler():
        let _started = jobs.after(duration: duration(1), operation: fn() -> Result[Unit, Error]:
            values.append(1)
            return ok(unit)
        )
`, 1},
		{"scheduler every", `    let values = [0]
    with jobs = Scheduler():
        let _started = jobs.every(interval: duration(1), operation: fn() -> Result[Unit, Error]:
            values.append(1)
            return ok(unit)
        )
`, 1},
		{"unrelated lock does not hide mutation", `    let values = [0]
    let unrelated = Synchronized(0)
    with tasks = TaskGroup():
        let _task = tasks.start(fn():
            with locked = unrelated.lock():
                values.append(1)
        )
`, 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			checked := compiler.CompileSource("capture.ms", imports+"fn run() -> Unit:\n"+tc.body, compiler.Options{AnalyzeOnly: true})
			if !checked.Success() {
				t.Fatal(checked.Diagnostics)
			}
			findings := lintSharedCaptures(checked.Program)
			if len(findings) != tc.count {
				t.Fatalf("got %v, want %d findings", findings, tc.count)
			}
			for _, finding := range findings {
				if finding.Code != "MSL105" || finding.Position.File != "capture.ms" || finding.Position.Line < 9 {
					t.Fatal(finding)
				}
			}
		})
	}
}

func TestConcurrentCaptureLintDoesNotGuessMethodNames(t *testing.T) {
	source := `import List from "@std/collections.ms"
interface Starter:
    fn start(operation: fn() -> Unit) -> Unit
type Sequential:
impl Starter for Sequential:
    fn start(operation: fn() -> Unit) -> Unit:
        operation()
fn run() -> Unit:
    let values = [0]
    Sequential().start(fn():
        values.append(1)
    )
`
	checked := compiler.CompileSource("capture.ms", source, compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	if findings := lintSharedCaptures(checked.Program); len(findings) != 0 {
		t.Fatal(findings)
	}
}

func TestConcurrentCaptureLintHTTPHandlers(t *testing.T) {
	prefix := `import List from "@std/collections.ms"
import network from "@std/net.ms"
import { HttpResponse, HttpServerOptions } from "@std/http.ms"
import panic from "@std/faults.ms"
fn run() -> Unit:
    let values = [0]
`
	for _, body := range []string{
		`    let _server = network().serve(address: "127.0.0.1:0", handler: fn(request) -> HttpResponse:
        values.append(1)
        return panic("not executed by lint")
    )
`,
		`    let _server = network().serve_stream(address: "127.0.0.1:0", handler: fn(exchange):
        values.append(1)
        return ok(unit)
    , options: HttpServerOptions(tls: none))
`,
	} {
		checked := compiler.CompileSource("capture.ms", prefix+body, compiler.Options{AnalyzeOnly: true})
		if !checked.Success() {
			t.Fatal(checked.Diagnostics)
		}
		if findings := lintSharedCaptures(checked.Program); len(findings) != 1 {
			t.Fatal(findings)
		}
	}
}

func TestConcurrentCaptureLintDocumentationFragments(t *testing.T) {
	for _, tc := range []struct {
		declaration, operation string
		count                  int
	}{
		{`let counts = {"hits": 0}`, `counts.add(key: "hits", value: counts.get("hits").unwrap_or(0) + 1)`, 1},
		{`let counts = Synchronized({"hits": 0})`, `with locked = counts.lock():
                let values = locked.get()
                values.add(key: "hits", value: values.get("hits").unwrap_or(0) + 1)`, 0},
	} {
		source := `import Map from "@std/collections.ms"
import TaskGroup from "@std/tasks.ms"
import Synchronized from "@std/sync.ms"
fn run() -> Unit:
    ` + tc.declaration + `
    with tasks = TaskGroup():
        let task = tasks.start(fn():
            ` + tc.operation + `
        )
`
		checked := compiler.CompileSource("capture.ms", source, compiler.Options{AnalyzeOnly: true})
		if !checked.Success() {
			t.Fatal(checked.Diagnostics)
		}
		if findings := lintSharedCaptures(checked.Program); len(findings) != tc.count {
			t.Fatal(findings)
		}
	}
}
