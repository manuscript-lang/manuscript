package e2e_test

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type debugEvent struct {
	Event    string `json:"event"`
	Reason   string `json:"reason"`
	Function string `json:"function"`
	File     string `json:"file"`
	Line     int    `json:"line"`
	Source   string `json:"source"`
	Status   *int   `json:"status"`
	Message  string `json:"message"`
	Stack    []struct {
		Function string `json:"function"`
		Line     int    `json:"line"`
	} `json:"stack"`
	Locals []struct{ Name, Type, Value string } `json:"locals"`
}

func decodeDebugEvents(t *testing.T, output []byte) []debugEvent {
	t.Helper()
	var events []debugEvent
	for _, line := range bytes.Split(bytes.TrimSpace(output), []byte("\n")) {
		var event debugEvent
		if err := json.Unmarshal(line, &event); err != nil {
			t.Fatalf("stdout is not JSON Lines: %v: %q", err, line)
		}
		events = append(events, event)
	}
	return events
}

// skipWithoutTracing skips where the OS or container forbids tracing a child.
func skipWithoutTracing(t *testing.T, status int, stderr string) {
	t.Helper()
	if status != 0 && (strings.Contains(stderr, "operation not permitted") || strings.Contains(stderr, "permission denied") || strings.Contains(stderr, "debugserver")) {
		t.Skipf("native debugging unavailable: %s", stderr)
	}
}

const debugScriptSource = `fn add(a: Int, b: Int) Int:
    let sum = a + b
    return sum

export fn main() Int:
    let total = add(a: 1, b: 2)
    return total - 3
`

func TestDebugOneShotReportsSourceNamesAndUserFrames(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "main.ms")
	if err := os.WriteFile(source, []byte(debugScriptSource), 0600); err != nil {
		t.Fatal(err)
	}
	status, stdout, stderr := cliStreams(t, "debug", source, "--json", "--break", "main.ms:3")
	skipWithoutTracing(t, status, stderr)
	events := decodeDebugEvents(t, stdout)
	if status != 0 || len(events) != 2 || events[0].Event != "breakpoint" {
		t.Fatalf("one-shot debug: %d\n%s\n%s", status, stdout, stderr)
	}
	stop := events[1]
	if stop.Event != "stop" || stop.Reason != "breakpoint" || stop.Function != "add" || stop.Line != 3 || strings.TrimSpace(stop.Source) != "return sum" {
		t.Fatalf("stop event: %+v", stop)
	}
	if len(stop.Stack) != 2 || stop.Stack[0].Function != "add" || stop.Stack[1].Function != "main" {
		t.Fatalf("stack should list only Manuscript frames: %+v", stop.Stack)
	}
	found := false
	for _, local := range stop.Locals {
		if strings.Contains(local.Name, "local") {
			t.Fatalf("generated local name leaked: %+v", stop.Locals)
		}
		found = found || local.Name == "sum" && local.Type == "Int" && local.Value == "3"
	}
	if !found {
		t.Fatalf("locals should include sum: Int = 3: %+v", stop.Locals)
	}
}

func TestDebugScriptBreaksByFunctionNameAndReportsExit(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "main.ms")
	commands := filepath.Join(root, "commands.txt")
	if err := os.WriteFile(source, []byte(debugScriptSource), 0600); err != nil {
		t.Fatal(err)
	}
	script := "# stop in add\nbreak add\ncontinue\nnext\nprint sum\nprint missing\nclear 1\ncontinue\n"
	if err := os.WriteFile(commands, []byte(script), 0600); err != nil {
		t.Fatal(err)
	}
	status, stdout, stderr := cliStreams(t, "debug", source, "--json", "--script", commands)
	skipWithoutTracing(t, status, stderr)
	events := decodeDebugEvents(t, stdout)
	var kinds []string
	for _, event := range events {
		kinds = append(kinds, event.Event)
	}
	want := "breakpoint,stop,stop,value,error,cleared,exit"
	if status != 1 || strings.Join(kinds, ",") != want {
		t.Fatalf("events %v, status %d, want %s\n%s\n%s", kinds, status, want, stdout, stderr)
	}
	if events[1].Function != "add" || events[1].Line != 2 {
		t.Fatalf("function breakpoint should stop on the first body line: %+v", events[1])
	}
	if events[2].Reason != "next" || events[2].Line != 3 {
		t.Fatalf("next should advance one source line: %+v", events[2])
	}
	if events[4].Message == "" || events[6].Status == nil || *events[6].Status != 0 {
		t.Fatalf("unknown local should be an error event and the program should exit 0: %+v", events)
	}
}

func TestDebugOneShotRejectsUnknownAndUnreachedBreakpoints(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "main.ms")
	if err := os.WriteFile(source, []byte("import stdout from \"@std/io.ms\"\n\nfn never() Int:\n    return 1\n\nexport fn main() Int:\n    let _written = stdout().write(data: \"TARGET_RAN\\n\")\n    return 0\n"), 0600); err != nil {
		t.Fatal(err)
	}
	status, stdout, stderr := cliStreams(t, "debug", source, "--json", "--break", "nothing")
	if status != 1 || !strings.Contains(string(stdout), `"event":"error"`) || !strings.Contains(string(stdout), "function declared in Manuscript source") {
		t.Fatalf("unknown function breakpoint: %d\n%s\n%s", status, stdout, stderr)
	}
	if strings.Contains(stderr, "TARGET_RAN") || strings.Contains(string(stdout), `"event":"exit"`) {
		t.Fatalf("invalid breakpoint ran the target: %s\n%s", stdout, stderr)
	}
	status, stdout, stderr = cliStreams(t, "debug", source, "--json", "--break", "never", "--break", "nothing")
	if status != 1 || strings.Contains(stderr, "TARGET_RAN") || strings.Contains(string(stdout), `"event":"exit"`) {
		t.Fatalf("a later invalid breakpoint ran the target: %d\n%s\n%s", status, stdout, stderr)
	}
	status, stdout, stderr = cliStreams(t, "debug", source, "--json", "--break", "never")
	skipWithoutTracing(t, status, stderr)
	events := decodeDebugEvents(t, stdout)
	if status != 1 || len(events) != 3 || events[0].Event != "breakpoint" || events[1].Event != "exit" || events[2].Event != "error" {
		t.Fatalf("a breakpoint the program never reaches should report exit and fail: %d\n%s\n%s", status, stdout, stderr)
	}
}
