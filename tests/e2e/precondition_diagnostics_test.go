package e2e_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// Compile one failing-test program so every diagnostic and call-site frame is
// checked independently, including continuation after each programming fault.
func TestPreconditionDiagnostics(t *testing.T) {
	cases := []struct{ setup, call, message string }{
		{"", "bytes.|with_value(index: 2, value: 0)", "Bytes.with_value: index must be between -2 and 1 (negative indexes count from the end), found 2"},
		{"", "bytes.|with_value(index: -3, value: 0)", "Bytes.with_value: index must be between -2 and 1 (negative indexes count from the end), found -3"},
		{"", "bytes.|with_value(index: -9223372036854775808, value: 0)", "Bytes.with_value: index must be between -2 and 1 (negative indexes count from the end), found -9223372036854775808"},
		{"", "bytes.|with_value(index: 0, value: -1)", "Bytes.with_value: value must be between 0 and 255, found -1"},
		{"", "bytes.|with_value(index: -1, value: 256)", "Bytes.with_value: value must be between 0 and 255, found 256"},
		{"", "bytes.|with_value(index: 2, value: 300)", "Bytes.with_value: index must be between -2 and 1 (negative indexes count from the end), found 2"},
		{"    let empty = Bytes(values: [])\n", "empty.|with_value(index: 0, value: 0)", "Bytes.with_value: index has no valid value for an empty collection, found 0"},
		{"    let update = bytes.with_value\n", "|update(index: 0, value: 300)", "Bytes.with_value: value must be between 0 and 255, found 300"},
		{"", "|Bytes(values: [0, 300])", "Bytes: values[1] must be between 0 and 255, found 300"},
		{"    let builder = BytesBuilder()\n", "builder.|append(-1)", "BytesBuilder.append: value must be between 0 and 255, found -1"},
		{"", "list.|with_value(index: -3, value: 1)", "List.with_value: index must be between -2 and 1 (negative indexes count from the end), found -3"},
		{"", "list.|without(2)", "List.without: index must be between -2 and 1 (negative indexes count from the end), found 2"},
		{"    let empty: List[Int] = []\n", "empty.|without(-1)", "List.without: index has no valid value for an empty collection, found -1"},
		{"", "list.|fill(value: 0, start: -1, end: 2)", "List.fill: start/end must satisfy 0 <= start <= end <= 2; found start -1 and end 2"},
		{"", "list.|fill(value: 0, start: 1, end: 3)", "List.fill: start/end must satisfy 0 <= start <= end <= 2; found start 1 and end 3"},
		{"", "list.|copy_within(target: 0, start: 2, end: 1)", "List.copy_within: start/end must satisfy 0 <= start <= end <= 2; found start 2 and end 1"},
		{"", "list.|copy_within(target: -1, start: 0, end: 2)", "List.copy_within: target must be between 0 and 2, found -1"},
		{"", "list.|copy_within(target: 3, start: 0, end: 2)", "List.copy_within: target must be between 0 and 2, found 3"},
		{"", "list.|with_values(start: -1, delete_count: 0, replacement: [])", "List.with_values: start must be between 0 and 2, found -1"},
		{"", "list.|with_values(start: 3, delete_count: 0, replacement: [])", "List.with_values: start must be between 0 and 2, found 3"},
		{"", "list.|with_values(start: 1, delete_count: -1, replacement: [])", "List.with_values: delete_count must be between 0 and 1, found -1"},
		{"", "list.|with_values(start: 1, delete_count: 9223372036854775807, replacement: [])", "List.with_values: delete_count must be between 0 and 1, found 9223372036854775807"},
		{"", "(1).|to_string(radix: 1)", "Int.to_string: radix must be between 2 and 36, found 1"},
		{"", "(1).|to_string(radix: 37)", "Int.to_string: radix must be between 2 and 36, found 37"},
		{"    let big = from_int(1)\n", "big.|to_string(radix: -1)", "BigInt.to_string: radix must be between 2 and 36, found -1"},
		{"", "|Queue[Int](capacity: 0)", "Queue: capacity must be between 1 and 9223372036854775807, found 0"},
		{"", "|Queue[Int](capacity: -1)", "Queue: capacity must be between 1 and 9223372036854775807, found -1"},
		{"", "|PriorityQueue[Int](compare: compare, capacity: -1)", "PriorityQueue: capacity must be between 1 and 9223372036854775807, found -1"},
		{"", "|PriorityQueue[Int](compare: compare, capacity: 0)", "PriorityQueue: capacity must be between 1 and 9223372036854775807, found 0"},
	}
	source := `import {Bytes, BytesBuilder} from "@std/bytes.ms"
import {Queue, PriorityQueue} from "@std/queues.ms"
import from_int from "@std/bigint.ms"
fn compare(left: Int, right: Int) -> Int: left - right
`
	var frames []string
	for i, tc := range cases {
		name := fmt.Sprintf("precondition %d", i)
		source += fmt.Sprintf("test %q:\n    let bytes = Bytes(values: [0, 255])\n    let list = [0, 1]\n%s", name, tc.setup)
		line := strings.Count(source, "\n") + 1
		call := "    let impossible = " + tc.call
		column := strings.IndexByte(call, '|') + 1
		frames = append(frames, fmt.Sprintf("preconditions.ms:%d:%d in test %s", line, column, name))
		source += strings.ReplaceAll(call, "|", "") + "\n"
	}
	source += "test \"continues after preconditions\":\n    let valid = 1\n"
	data, err := execute(t, compiler.CompileSource("preconditions.ms", source, compiler.Options{Tests: true}))
	if err == nil {
		t.Fatalf("expected programming faults:\n%s", data)
	}
	output := string(data)
	for i, tc := range cases {
		want := fmt.Sprintf("FAIL preconditions.ms::precondition %d: %s\n  at %s\n", i, tc.message, frames[i])
		if !strings.Contains(output, want) {
			t.Errorf("missing diagnostic and exact frame %q:\n%s", want, output)
		}
	}
	var actualFrames []string
	for _, line := range strings.Split(output, "\n") {
		if frame, ok := strings.CutPrefix(line, "  at "); ok {
			actualFrames = append(actualFrames, frame)
		}
	}
	if strings.Join(actualFrames, "\n") != strings.Join(frames, "\n") {
		t.Errorf("unexpected extra/missing source frames: %q; want %q", actualFrames, frames)
	}
	if !strings.Contains(output, "PASS preconditions.ms::continues after preconditions") || !strings.HasSuffix(strings.TrimSpace(output), fmt.Sprintf("%d tests, %d failed", len(cases)+1, len(cases))) {
		t.Errorf("runner did not continue after every fault:\n%s", output)
	}
}
