package e2e_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestTaskPreconditionDiagnostics(t *testing.T) {
	cases := []struct{ call, message string }{
		{"Scheduler(limit: 0)", "Scheduler: limit must be between 1 and 2147483647, found 0"},
		{"Scheduler(limit: -1)", "Scheduler: limit must be between 1 and 2147483647, found -1"},
		{"Scheduler(limit: -2147483648)", "Scheduler: limit must be between 1 and 2147483647, found -2147483648"},
		{"Scheduler(history_limit: -1)", "Scheduler: history_limit must be between 0 and 2147483647, found -1"},
		{"Scheduler(drain: duration(-1))", "Scheduler: drain (nanoseconds) must be between 0 and 9223372036854775807, found -1"},
		{"Scheduler(drain: duration(-9223372036854775808))", "Scheduler: drain (nanoseconds) must be between 0 and 9223372036854775807, found -9223372036854775808"},
		{"TaskGroup(timeout: duration(-1))", "TaskGroup: timeout (nanoseconds) must be between 0 and 9223372036854775807, found -1"},
		{"TaskGroup(timeout: duration(-9223372036854775808))", "TaskGroup: timeout (nanoseconds) must be between 0 and 9223372036854775807, found -9223372036854775808"},
		{"sleep(duration(-1))", "sleep: duration (nanoseconds) must be between 0 and 9223372036854775807, found -1"},
		{"sleep(duration(-9223372036854775808))", "sleep: duration (nanoseconds) must be between 0 and 9223372036854775807, found -9223372036854775808"},
	}
	source := "import {Scheduler, TaskGroup} from \"@std/tasks.ms\"\nimport {duration, sleep} from \"@std/time.ms\"\n"
	var frames []string
	for i, tc := range cases {
		name := fmt.Sprintf("task precondition %d", i)
		source += fmt.Sprintf("test %q:\n", name)
		line := strings.Count(source, "\n") + 1
		frames = append(frames, fmt.Sprintf("task-preconditions.ms:%d:22 in test %s", line, name))
		source += "    let impossible = " + tc.call + "\n"
	}
	source += "test \"continues after task preconditions\":\n    sleep(duration(0))\n"
	data, err := execute(t, compiler.CompileSource("task-preconditions.ms", source, compiler.Options{Tests: true}))
	if err == nil {
		t.Fatalf("expected programming faults:\n%s", data)
	}
	output := string(data)
	for i, tc := range cases {
		want := fmt.Sprintf("FAIL task-preconditions.ms::task precondition %d: %s\n  at %s\n", i, tc.message, frames[i])
		if !strings.Contains(output, want) {
			t.Errorf("missing diagnostic and source frame %q:\n%s", want, output)
		}
	}
	var actual []string
	for _, line := range strings.Split(output, "\n") {
		if frame, ok := strings.CutPrefix(line, "  at "); ok {
			actual = append(actual, frame)
		}
	}
	if strings.Join(actual, "\n") != strings.Join(frames, "\n") {
		t.Errorf("unexpected frames: %q, want %q", actual, frames)
	}
	if !strings.Contains(output, "PASS task-preconditions.ms::continues after task preconditions") || !strings.HasSuffix(strings.TrimSpace(output), "11 tests, 10 failed") {
		t.Errorf("runner did not continue after constructor/sleep faults:\n%s", output)
	}
}
