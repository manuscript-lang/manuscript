package msruntime

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/manuscript-lang/manuscript/internal/nativeabi"
)

func TestStructuredTestEventsRetainFailuresTimeoutsAndDuplicateNames(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.jsonl")
	t.Setenv(nativeabi.TestEventsEnv, path)
	pass := func(*Execution, []Value) Value { return Unit{} }
	tests := []Test{
		{"same.ms::duplicate", NewFunction(nil, "Unit", pass)},
		{"same.ms::duplicate", NewFunction(nil, "Unit", func(*Execution, []Value) Value { return Panic("named failure") })},
		{"same.ms::timeout", NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value { <-ctx.Context.Done(); CheckCancelled(ctx); return Unit{} })},
		{"same.ms::after", NewFunction(nil, "Unit", pass)},
	}
	if failed := RunTestsArgs(tests, []string{"--timeout=20ms"}); failed != 2 {
		t.Fatalf("failed=%d", failed)
	}
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	var events []nativeabi.TestEvent
	decoder := json.NewDecoder(file)
	for {
		var event nativeabi.TestEvent
		if err := decoder.Decode(&event); err == io.EOF {
			break
		} else if err != nil {
			t.Fatal(err)
		}
		events = append(events, event)
	}
	if len(events) != 10 || events[0].Event != "plan" || events[0].Available != 4 || events[0].Names[0] != events[0].Names[1] || events[9].Event != "done" {
		t.Fatalf("events: %+v", events)
	}
	if events[4].Event != "failed" || events[4].Index != 1 || events[4].Failure != "named failure" || !strings.Contains(events[6].Failure, "timed out after 20ms") || events[8].Event != "passed" || events[8].Index != 3 {
		t.Fatalf("results: %+v", events)
	}
}

func TestStructuredTestEventsEmptyAndUnmatchedFilter(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.jsonl")
	t.Setenv(nativeabi.TestEventsEnv, path)
	for _, tc := range []struct {
		args   []string
		status int
		reason string
	}{{nil, 0, "no_tests"}, {[]string{"--filter=missing"}, 1, "no_match"}} {
		if status := RunTestsArgs(nil, tc.args); status != tc.status {
			t.Fatalf("status %d", status)
		}
		data, err := os.ReadFile(path)
		if err != nil || !strings.Contains(string(data), `"event":"plan"`) || !strings.Contains(string(data), `"reason":"`+tc.reason+`"`) {
			t.Fatalf("%v: %v %s", tc.args, err, data)
		}
	}
	// Public direct runner calls keep their existing behavior and do not inherit
	// a CLI-owned result channel from the surrounding process environment.
	if err := os.WriteFile(path, []byte("unchanged"), 0600); err != nil {
		t.Fatal(err)
	}
	RunTestsWith(nil, TestOptions{Timeout: time.Second})
	data, _ := os.ReadFile(path)
	if string(data) != "unchanged" {
		t.Fatal("ordinary runner wrote a report")
	}
}
