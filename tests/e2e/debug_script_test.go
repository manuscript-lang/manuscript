package e2e_test

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/shirou/gopsutil/v4/process"
)

type debugEvent struct {
	Version, Seq, CommandID, PID               int
	Event, Reason, Code, Stream, Text, Message string
	Command                                    string
	Result                                     json.RawMessage
	Location                                   struct {
		File, Function, NativeFunction string
		Source                         bool
		Index                          int
	}
	Locals       []struct{ Name, Type, Value string }
	TargetStatus *int `json:"target_status"`
}

func debugTranscript(t *testing.T, cwd, source, script string, extra ...string) ([]debugEvent, int) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "commands.txt")
	if err := os.WriteFile(path, []byte(script), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	args := append([]string{"debug", source, "--script=" + path, "--json"}, extra...)
	cmd := exec.CommandContext(ctx, cliBinary, args...)
	cmd.Dir = cwd
	var out, stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr
	err := cmd.Run()
	status := 0
	if err != nil {
		if e, ok := err.(*exec.ExitError); ok {
			status = e.ExitCode()
		} else {
			t.Fatal(err)
		}
	}
	if ctx.Err() != nil || stderr.Len() != 0 {
		t.Fatalf("debug: %v %s", ctx.Err(), &stderr)
	}
	decoder := json.NewDecoder(&out)
	events := []debugEvent{}
	for {
		var event debugEvent
		err := decoder.Decode(&event)
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err, out.String())
		}
		if event.Version != 1 || event.Seq != len(events)+1 {
			t.Fatal(event)
		}
		events = append(events, event)
	}
	if len(events) == 0 || events[len(events)-1].Event != "exit" {
		t.Fatal(events)
	}
	return events, status
}

func TestCLIScriptedDebugHello(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"ms.toml", "src/main.ms"} {
		data, err := os.ReadFile(filepath.Join("../../examples/hello", name))
		if err != nil {
			t.Fatal(err)
		}
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, data, 0600); err != nil {
			t.Fatal(err)
		}
	}
	for _, tc := range []struct{ name, script, reason string }{
		{"issue-repro", "break src/main.ms:5\ncontinue\nnext\nnext\nlocals\nbt 3\nexit\n", "exit"},
		{"source-function", "break main\ncontinue\nnext\nlocals\nprint message\nbt 3\nbt 256 --raw\ncontinue\nexit\n", "exited"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			events, status := debugTranscript(t, root, "ms.toml", tc.script, "--", "a", "b")
			if status != 0 || events[len(events)-1].Reason != tc.reason {
				t.Fatal(status, events)
			}
			var programOut strings.Builder
			localFound, sourceStop, sourceStack, rawStack := false, false, false, false
			for _, e := range events {
				if e.Event == "output" {
					if e.Stream != "stdout" {
						t.Fatal(e)
					}
					programOut.WriteString(e.Text)
				}
				if e.Event == "stop" && e.Location.Source {
					if e.Location.File != "src/main.ms" || e.Location.Function != "main" {
						t.Fatal(e)
					}
					sourceStop = true
					for _, local := range e.Locals {
						if local.Name == "message" && local.Type == "String" && local.Value == `"Arguments: 2\n"` {
							localFound = true
						}
					}
				}
				if e.Event == "result" && bytes.Contains(e.Result, []byte(`"frames"`)) {
					var result struct{ Frames []struct{ Source bool } }
					if err := json.Unmarshal(e.Result, &result); err != nil {
						t.Fatal(err)
					}
					allSource := len(result.Frames) > 0
					for _, f := range result.Frames {
						if !f.Source {
							allSource = false
							rawStack = true
						}
					}
					sourceStack = sourceStack || allSource
				}
			}
			if programOut.String() != "Arguments: 2\n" || !sourceStop || !localFound || !sourceStack || tc.name == "source-function" && !rawStack {
				t.Fatalf("stdout=%q source=%v locals=%v stack=%v raw=%v: %+v", programOut.String(), sourceStop, localFound, sourceStack, rawStack, events)
			}
		})
	}
}

func TestCLIScriptedDebugOutputAndExit(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "main.ms")
	text := "import arguments from \"@std/cli.ms\"\nimport {stdout, stderr, stdin} from \"@std/io.ms\"\nexport fn main() -> Int:\n    let input = stdin().read(max_bytes: 1)\n    let out = stdout().write(data: \"stdout:{arguments().length()}\\n\".to_bytes())\n    let err = stderr().write(data: \"stderr:λ\\n\".to_bytes())\n    return 7\n"
	if err := os.WriteFile(source, []byte(text), 0600); err != nil {
		t.Fatal(err)
	}
	events, status := debugTranscript(t, root, source, "continue\nexit\n", "--", "a", "b")
	outputs := map[string]string{}
	for _, e := range events {
		if e.Event == "output" {
			outputs[e.Stream] += e.Text
		}
	}
	last := events[len(events)-1]
	if status != 7 || last.Reason != "exited" || last.TargetStatus == nil || *last.TargetStatus != 7 || outputs["stdout"] != "stdout:2\n" || outputs["stderr"] != "stderr:λ\n" {
		t.Fatal(status, outputs, events)
	}
}

func TestCLIScriptedDebugSIGINT(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows does not support sending os.Interrupt")
	}
	root := t.TempDir()
	source := filepath.Join(root, "main.ms")
	if err := os.WriteFile(source, []byte("export fn main() -> Int:\n    var value = 0\n    while value == 0:\n        value = value + 0\n    return value\n"), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, cliBinary, "debug", source, "--script=-", "--json")
	input, err := cmd.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	out, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	decoder := json.NewDecoder(bufio.NewReader(out))
	var initial debugEvent
	if err := decoder.Decode(&initial); err != nil {
		t.Fatal(err)
	}
	if initial.PID == 0 {
		t.Fatal(initial)
	}
	if _, err := io.WriteString(input, "continue\n"); err != nil {
		t.Fatal(err)
	}
	var command debugEvent
	if err := decoder.Decode(&command); err != nil {
		t.Fatal(err)
	}
	if command.Event != "command" {
		t.Fatal(command)
	}
	<-time.After(100 * time.Millisecond)
	if err := cmd.Process.Signal(os.Interrupt); err != nil {
		t.Fatal(err)
	}
	var last debugEvent
	for {
		var e debugEvent
		err := decoder.Decode(&e)
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		last = e
	}
	err = cmd.Wait()
	if err == nil || ctx.Err() != nil || last.Event != "exit" || last.Reason != "cancelled" || stderr.Len() != 0 {
		t.Fatalf("%v ctx=%v last=%+v stderr=%s", err, ctx.Err(), last, &stderr)
	}
	if exists, err := process.PidExists(int32(initial.PID)); err != nil || exists {
		t.Fatalf("target survived SIGINT: %v", err)
	}
}

func TestCLIScriptedDebugSourceValues(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "main.ms")
	source := "type Box:\n    count: Int\ntype Holder:\n    value: Box\nfn helper(input: Int) -> Int:\n    let box = Box(count: 42)\n    let holder = Holder(value: box)\n    let items = [1, 2, 3]\n    let entries = {\"count\": 42}\n    let optional: Optional[Int] = some(5)\n    let data = \"A\".to_bytes()\n    return input + items.at(0).unwrap() + entries.get(\"count\").unwrap() + optional.unwrap() + data.length() + box.count + holder.value.count - 135\nexport fn main() -> Int:\n    return helper(input: 2)\n"
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	events, status := debugTranscript(t, root, path, "break "+path+":12\ncontinue\nlocals\nbt 3\ncontinue\nexit\n")
	if status != 0 {
		t.Fatal(status, events)
	}
	type value struct {
		Name, Type, Value string
		Children          []value
		Unavailable       string
		Truncated         bool
	}
	var values []value
	for _, event := range events {
		if event.Event == "result" && len(event.Result) > 0 && event.Result[0] == '[' {
			if err := json.Unmarshal(event.Result, &values); err != nil {
				t.Fatal(err)
			}
		}
	}
	byName := map[string]value{}
	for _, v := range values {
		byName[v.Name] = v
	}
	for name, want := range map[string]string{"input": "2", "box": "Box", "holder": "Holder", "items": "List[Int] (3 items)", "entries": "Map[String, Int] (1 items)", "optional": "some"} {
		v := byName[name]
		if v.Value != want || v.Unavailable != "" || v.Truncated {
			t.Fatalf("%s: %+v (all %+v)", name, v, values)
		}
	}
	for name, want := range map[string]string{"box": "42", "items": "1", "entries": "42", "optional": "5"} {
		v := byName[name]
		if len(v.Children) == 0 || v.Children[0].Value != want || v.Children[0].Unavailable != "" {
			t.Fatalf("%s payload: %+v", name, v)
		}
	}
	// Delve can fail to resolve the concrete Bytes interface in this native
	// fixture. Preserve that error instead of inventing empty/incorrect contents;
	// loaded Bytes layout and numeric payloads have a structural regression too.
	if v := byName["data"]; v.Unavailable != "" {
		if v.Type != "Bytes" || v.Value != "<unavailable>" {
			t.Fatal(v)
		}
	} else if v.Value != "Bytes (1 items)" || len(v.Children) != 1 || v.Children[0].Value != "65" {
		t.Fatal(v)
	}
	if v := byName["holder"]; len(v.Children) != 1 || v.Children[0].Type != "Box" || len(v.Children[0].Children) != 1 || v.Children[0].Children[0].Value != "42" {
		t.Fatal(v)
	}
}

func TestCLIScriptedDebugUnreadOutputCancellation(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows signal delivery is exercised by its distribution runner")
	}
	root := t.TempDir()
	source := filepath.Join(root, "main.ms")
	text := "import stdout from \"@std/io.ms\"\nexport fn main() -> Int:\n    var count = 0\n    while count < 4096:\n        let output = stdout().write(data: \"" + strings.Repeat("x", 128) + "\".to_bytes())\n        count = count + 1\n\n    while count == 4096:\n        count = count + 0\n    return count\n"
	if err := os.WriteFile(source, []byte(text), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, cliBinary, "debug", source, "--script=-", "--json")
	input, err := cmd.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	out, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	decoder := json.NewDecoder(out)
	var initial debugEvent
	if err := decoder.Decode(&initial); err != nil || initial.PID == 0 {
		t.Fatal(initial, err)
	}
	_, _ = io.WriteString(input, "break "+source+":8\ncontinue\nexit\n")
	for {
		var event debugEvent
		if err := decoder.Decode(&event); err != nil {
			t.Fatal(err)
		}
		if event.Event == "command" && event.Command == "continue" {
			break
		}
	}
	// Stop reading while the checkpoint output fills the inherited stdout pipe.
	<-time.After(300 * time.Millisecond)
	if err := cmd.Process.Signal(os.Interrupt); err != nil {
		t.Fatal(err)
	}
	err = cmd.Wait()
	if err == nil || ctx.Err() != nil || stderr.Len() != 0 {
		t.Fatalf("cancel: %v ctx=%v stderr=%s", err, ctx.Err(), &stderr)
	}
	if exists, err := process.PidExists(int32(initial.PID)); err != nil || exists {
		t.Fatalf("target survived unread output: %v", err)
	}
}

func TestCLIScriptedDebugFunctionDefault(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "main.ms")
	source := "fn answer(operation: fn() -> Int = fn() -> Int: 7) -> Int:\n    let result = operation()\n    return result\nexport fn main() -> Int:\n    return answer()\n"
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	events, status := debugTranscript(t, root, path, "break answer\ncontinue\nbt 3\nexit\n")
	if status == 1 {
		// Source line directives can map the entry to both generated factory and
		// callable PCs. Report that ambiguity instead of selecting the factory.
		for _, e := range events {
			if e.Event == "error" && strings.Contains(e.Message, "ambiguous native entry") {
				return
			}
		}
		t.Fatal("unexpected source breakpoint failure", events)
	}
	if status != 0 {
		t.Fatal(status, events)
	}
	found := false
	for _, e := range events {
		if e.Event == "stop" && e.Reason == "breakpoint" {
			if e.Location.Function != "answer" || e.Location.File != "main.ms" {
				t.Fatal(e)
			}
			found = true
		}
	}
	if !found {
		t.Fatal("did not reach answer body")
	}
	// The breakpoint result includes the own-body line, not the default callback.
	var result struct{ Location struct{ Line int } }
	for _, e := range events {
		if e.Event == "result" && bytes.Contains(e.Result, []byte(`"breakpoint_id"`)) {
			if err := json.Unmarshal(e.Result, &result); err != nil {
				t.Fatal(err)
			}
		}
	}
	if result.Location.Line != 2 {
		t.Fatalf("bound header callback: %+v", result)
	}
}
