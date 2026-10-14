package debugger

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/go-delve/delve/service"
	"github.com/go-delve/delve/service/api"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"github.com/shirou/gopsutil/v4/process"
)

func TestScriptCommandGrammar(t *testing.T) {
	for _, line := range []string{"", " # comment", "break source with spaces.ms:5", "break main", "continue", "next", "step", "step-out", "locals", "print message", "bt", "bt 3 --raw", "bt --raw 256", "exit"} {
		if _, err := parseScriptCommand(line); err != nil {
			t.Fatalf("%q: %v", line, err)
		}
	}
	for _, line := range []string{"break", "print", "print a.b", "print a b", "next 2", "continue now", "bt 0", "bt 257", "bt 2 3", "bt --raw --raw", "quit"} {
		if _, err := parseScriptCommand(line); err == nil {
			t.Fatalf("accepted %q", line)
		}
	}
}

func TestSourceBreakpointsAndFrames(t *testing.T) {
	v := &sourceView{root: "/source", files: map[string]string{filepath.Clean("/source/a.ms"): "a.ms"}, inspection: tooling.Inspection{
		Entities: []tooling.Entity{
			{Kind: "fn", Name: "same", Span: tooling.Span{File: "a.ms", Start: 10, End: 20, Line: 2}, Entry: &tooling.Span{File: "a.ms", Start: 30, Line: 3}},
			{Kind: "fn", Name: "same", Span: tooling.Span{File: "b.ms", Start: 10, Line: 2}},
			{Kind: "fn", Name: "empty", Span: tooling.Span{File: "a.ms", Start: 40, Line: 5}},
			{Kind: "type", Name: "Box", Span: tooling.Span{File: "a.ms", Start: 50, Line: 6}},
			{Kind: "fn", Name: "later", Span: tooling.Span{File: "a.ms", Start: 60, Line: 7}},
		},
		Statements: []tooling.Span{{File: "a.ms", Start: 30, Line: 3}, {File: "a.ms", Start: 70, Line: 8}},
	}}
	if _, err := v.breakpointLocation("same"); err == nil || !strings.Contains(err.Error(), "a.ms:same, b.ms:same") {
		t.Fatalf("ambiguity: %v", err)
	}
	if got, err := v.breakpointLocation("a.ms:same"); err != nil || got != filepath.Join(v.root, "a.ms")+":3" {
		t.Fatalf("body breakpoint %q: %v", got, err)
	}
	if _, err := v.breakpointLocation("empty"); err == nil {
		t.Fatal("empty function bound a later statement")
	}
	if got, err := v.breakpointLocation("a.ms:12"); err != nil || got != "a.ms:12" {
		t.Fatal(got, err)
	}
	f := v.frame(api.Location{File: "/source/a.ms", Line: 3, Function: &api.Function{Name_: "main.initialize.func1.1"}}, 4)
	if f.Function != "same" || f.NativeFunction != "main.initialize.func1.1" || f.Index != 4 || !f.Source {
		t.Fatal(f)
	}
	for _, location := range []api.Location{{File: "/other/a.ms", Line: 3}, {File: "/source/a.ms", Line: 3, Function: &api.Function{Name_: "runtime.Cleanup"}}} {
		if f := v.frame(location, 0); f.Source {
			t.Fatalf("non-user frame: %+v", f)
		}
	}
}

func TestSourceValueRendering(t *testing.T) {
	wrap := func(v api.Variable) api.Variable {
		return api.Variable{Kind: reflect.Interface, Children: []api.Variable{v}}
	}
	for _, tc := range []struct {
		v                        api.Variable
		declared, wantType, want string
		truncated                bool
	}{
		{wrap(api.Variable{Kind: reflect.String, Value: "hello\n", Len: 6}), "String", "String", `"hello\n"`, false},
		{wrap(api.Variable{Kind: reflect.Int64, Value: "42"}), "Int", "Int", "42", false},
		{wrap(api.Variable{Kind: reflect.String, Value: "long", Len: 80}), "String", "String", `"long"`, true},
		{wrap(api.Variable{Type: "msruntime.Unit", Kind: reflect.Struct}), "Unit", "Unit", "unit", false},
		{wrap(api.Variable{Kind: reflect.String, Value: "recycled"}), "List[Int]", "List[Int]", "<unavailable after last use>", false},
		{wrap(api.Variable{Type: "msruntime.List", Kind: reflect.Struct, Children: []api.Variable{{Name: "Type", Value: "@std/List[Int]"}, {Name: "Items", Len: 35, Children: []api.Variable{wrap(api.Variable{Kind: reflect.Int64, Value: "42"})}}}}), "List[Int]", "List[Int]", "List[Int] (35 items)", true},
		{wrap(api.Variable{Type: "main.record_box", Kind: reflect.Struct, Children: []api.Variable{{Name: "Type", Value: "module/abc#Box[Int]"}, {Name: "f_count", Kind: reflect.Int64, Value: "42"}}}), "Box[Int]", "Box[Int]", "Box[Int]", false},
		{wrap(api.Variable{Type: "msruntime.Alternative", Kind: reflect.Struct, Children: []api.Variable{{Name: "Type", Value: "@std/Optional[Int]"}, {Name: "Tag", Value: "some"}, {Name: "Fields", Len: 0}}}), "Optional[Int]", "Optional[Int]", "some", false},
	} {
		got := renderValue(tc.v, "value", tc.declared, 0, nil)
		if got.Type != tc.wantType || got.Value != tc.want || got.Truncated != tc.truncated {
			t.Fatalf("%s: %+v", tc.declared, got)
		}
	}
	got := renderValue(api.Variable{Unreadable: "invalid address"}, "v", "Int", 0, nil)
	if got.Unavailable != "invalid address" {
		t.Fatal(got)
	}
	if got := runtimeType("@std/Result[module/abcd#Box[@std/List[Int]]][String]"); got != "Result[Box[List[Int]], String]" {
		t.Fatal(got)
	}
	for _, tc := range []struct {
		kind, declared, field string
		fields                []api.Variable
		name, value           string
	}{
		{"Alternative", "Optional[Int]", "Fields", []api.Variable{wrap(api.Variable{Kind: reflect.Int64, Value: "5"})}, "0", "5"},
		{"Bytes", "Bytes", "Items", []api.Variable{{Kind: reflect.Uint8, Value: "65"}}, "0", "65"},
		{"Map", "Map[String, Int]", "Entries", []api.Variable{{Children: []api.Variable{{Name: "Key", Kind: reflect.String, Value: "count", Len: 5}, {Name: "Value", Kind: reflect.Int64, Value: "42"}}}}, `"count"`, "42"},
	} {
		v := api.Variable{Type: "msruntime." + tc.kind, Kind: reflect.Struct, Children: []api.Variable{{Name: tc.field, Len: 1, Children: tc.fields}}}
		got := renderValue(wrap(v), "value", tc.declared, 0, nil)
		if got.Truncated || len(got.Children) != 1 || got.Children[0].Name != tc.name || got.Children[0].Value != tc.value {
			t.Fatalf("%s payload: %+v", tc.kind, got)
		}
	}
	if got := renderValue(wrap(api.Variable{Type: "msruntime.Map", Kind: reflect.Struct}), "map", "Map[String,Int]", 0, nil); !got.Truncated {
		t.Fatal("missing map fields appeared loaded", got)
	}
}

func TestScriptOutputPreservesBytes(t *testing.T) {
	file, err := os.CreateTemp(t.TempDir(), "output")
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	data := append([]byte(strings.Repeat("a", 8191)+"€"), 0xff)
	if _, err := file.Write(data); err != nil {
		t.Fatal(err)
	}
	_, _ = file.Seek(0, io.SeekStart)
	var out bytes.Buffer
	w := eventWriter{output: &out}
	if err := (scriptOutput{stream: "stdout", file: file}).drain(&w); err != nil {
		t.Fatal(err)
	}
	var reconstructed []byte
	for _, e := range decodeEvents(t, out.Bytes()) {
		if e.Bytes != "" {
			part, err := base64.StdEncoding.DecodeString(e.Bytes)
			if err != nil {
				t.Fatal(err)
			}
			reconstructed = append(reconstructed, part...)
		} else {
			reconstructed = append(reconstructed, e.Text...)
		}
	}
	if !bytes.Equal(data, reconstructed) {
		t.Fatal("output bytes changed across chunk boundary")
	}
}

type partialWriter struct {
	bytes.Buffer
	writes int
}

func (w *partialWriter) Write(data []byte) (int, error) {
	w.writes++
	n := len(data) / 2
	_, _ = w.Buffer.Write(data[:n])
	return n, errors.New("partial write")
}

func TestScriptPartialOutputStopsFraming(t *testing.T) {
	var out partialWriter
	w := eventWriter{output: &out}
	if err := w.emit(scriptEvent{Event: "output", Text: "message"}); err == nil {
		t.Fatal("partial write accepted")
	}
	before := out.String()
	if err := w.emit(scriptEvent{Event: "exit"}); err == nil || out.writes != 1 || out.String() != before {
		t.Fatal("another record appended to partial JSONL")
	}
}

func decodeEvents(t *testing.T, data []byte) []scriptEvent {
	t.Helper()
	decoder := json.NewDecoder(bytes.NewReader(data))
	var events []scriptEvent
	for {
		var e scriptEvent
		err := decoder.Decode(&e)
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("invalid JSONL: %v\n%s", err, data)
		}
		if e.Version != 1 || e.Seq != len(events)+1 {
			t.Fatalf("sequence/version: %+v", e)
		}
		events = append(events, e)
	}
	return events
}

// Native checks are opt-in here; CLI/e2e and distribution tests exercise the
// shipped command separately. Run MANUSCRIPT_DEBUG_TEST=1 for shutdown races.
func scriptTarget(t *testing.T, source string) (string, tooling.Inspection) {
	t.Helper()
	if os.Getenv("MANUSCRIPT_DEBUG_TEST") == "" {
		t.Skip("set MANUSCRIPT_DEBUG_TEST=1 for native debugging")
	}
	if scriptProcessSupported() != nil {
		// The unsupported-platform regression exercises pre-launch rejection;
		// native command tests apply only where safe interruption is supported.
		t.Skip("identity-bound script process interruption unavailable on this platform")
	}
	root := t.TempDir()
	path := filepath.Join(root, "main.ms")
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	result := compiler.CompileFileForBuild(path, compiler.Options{Entry: true}, compiler.Debug)
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	executable := filepath.Join(root, "program")
	if _, err := build.BuildCheckedWithType(result, executable, compiler.Debug); err != nil {
		t.Fatal(err)
	}
	return executable, tooling.Inspect(result.Program)
}

func assertReaped(t *testing.T, events []scriptEvent) {
	t.Helper()
	assertTargetGone(t, events)
	if len(events) == 0 || events[len(events)-1].Event != "exit" {
		t.Fatal("missing final exit")
	}
}

func assertTargetGone(t *testing.T, events []scriptEvent) {
	t.Helper()
	pid := 0
	for _, e := range events {
		if e.PID != 0 {
			pid = e.PID
		}
	}
	if pid == 0 {
		t.Fatal("missing target PID")
	}
	if exists, err := process.PidExists(int32(pid)); err != nil || exists {
		t.Fatalf("target %d survived: %v", pid, err)
	}
}

func TestScriptNativeCleanup(t *testing.T) {
	executable, inspection := scriptTarget(t, "export fn main() -> Int:\n    var number = 0\n    while number == 0:\n        number = number + 0\n    return number\n")
	for _, tc := range []struct {
		name, commands, reason string
		status                 int
	}{
		{"eof-entry", "", "eof", 0},
		{"eof-stopped", "break main\ncontinue\nlocals\n", "eof", 0},
		{"eof-running", "continue\n", "eof", 0},
		{"malformed", "break main\ncontinue\nunknown\n", "error", 1},
		{"oversized", strings.Repeat("x", 65537), "error", 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			var out bytes.Buffer
			status := Script(ctx, executable, nil, inspection, io.NopCloser(strings.NewReader(tc.commands)), &out, false)
			events := decodeEvents(t, out.Bytes())
			assertReaped(t, events)
			last := events[len(events)-1]
			if ctx.Err() != nil || status != tc.status || last.Reason != tc.reason {
				t.Fatalf("status %d: %+v (ctx %v)\n%s", status, last, ctx.Err(), &out)
			}
		})
	}
}

type notifyWriter struct {
	bytes.Buffer
	commands chan struct{}
	stops    chan struct{}
}

func (w *notifyWriter) Write(data []byte) (int, error) {
	if bytes.Contains(data, []byte(`"event":"command"`)) {
		select {
		case w.commands <- struct{}{}:
		default:
		}
	}
	if bytes.Contains(data, []byte(`"event":"stop"`)) && bytes.Contains(data, []byte(`"reason":"breakpoint"`)) {
		select {
		case w.stops <- struct{}{}:
		default:
		}
	}
	return w.Buffer.Write(data)
}

// Next and step-out can run forever even though they are stepping commands.
// Cancellation/EOF must interrupt and join them just like continue.
func TestScriptNativeSteppingCleanup(t *testing.T) {
	executable, inspection := scriptTarget(t, "fn spin() -> Int:\n    var number = 0\n    while number == 0:\n        number = number + 0\n    return number\nexport fn main() -> Int:\n    return spin()\n")
	for _, command := range []string{"next", "step-out"} {
		for _, mode := range []string{"dispatch-cancel", "running-cancel", "running-eof"} {
			t.Run(command+"/"+mode, func(t *testing.T) {
				ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
				defer cancel()
				input, writer, err := os.Pipe()
				if err != nil {
					t.Fatal(err)
				}
				defer writer.Close()
				out := notifyWriter{commands: make(chan struct{}, 3), stops: make(chan struct{}, 1)}
				done := make(chan int, 1)
				go func() { done <- Script(ctx, executable, nil, inspection, input, &out, false) }()
				function := "main"
				if command == "step-out" {
					function = "spin"
				}
				_, _ = io.WriteString(writer, "break "+function+"\ncontinue\n")
				select {
				case <-out.stops:
				case <-ctx.Done():
					t.Fatal(ctx.Err())
				}
				<-out.commands // break acknowledgement
				<-out.commands // continue acknowledgement
				_, _ = io.WriteString(writer, command+"\n")
				select {
				case <-out.commands:
				case <-ctx.Done():
					t.Fatal(ctx.Err())
				}
				if mode != "dispatch-cancel" {
					<-time.After(100 * time.Millisecond)
				}
				wantStatus, wantReason := 1, "cancelled"
				if mode == "running-eof" {
					_ = writer.Close()
					wantStatus, wantReason = 0, "eof"
				} else {
					cancel()
				}
				select {
				case status := <-done:
					if status != wantStatus {
						t.Fatalf("status %d, want %d", status, wantStatus)
					}
				case <-time.After(10 * time.Second):
					t.Fatal("stepping command did not join")
				}
				events := decodeEvents(t, out.Bytes())
				assertReaped(t, events)
				for _, event := range events {
					if event.Event == "result" && event.CommandID == 3 {
						t.Fatal("interrupted stepping command reported success")
					}
				}
				if last := events[len(events)-1]; last.Reason != wantReason {
					t.Fatalf("exit %+v, want %s", last, wantReason)
				}
			})
		}
	}
}

func TestScriptNativeCancellation(t *testing.T) {
	executable, inspection := scriptTarget(t, "export fn main() -> Int:\n    var number = 0\n    while number == 0:\n        number = number + 0\n    return number\n")
	for _, mode := range []string{"input-idle", "resume-race", "running", "eof-running"} {
		t.Run(mode, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			input, writer, err := os.Pipe()
			if err != nil {
				t.Fatal(err)
			}
			defer writer.Close()
			out := notifyWriter{commands: make(chan struct{}, 1)}
			done := make(chan int, 1)
			go func() { done <- Script(ctx, executable, nil, inspection, input, &out, false) }()
			_, _ = io.WriteString(writer, "break main\n")
			select {
			case <-out.commands:
			case <-ctx.Done():
				t.Fatal(ctx.Err())
			}
			if mode != "input-idle" {
				_, _ = io.WriteString(writer, "continue\n")
				select {
				case <-out.commands:
				case <-ctx.Done():
					t.Fatal(ctx.Err())
				}
			}
			if mode == "running" || mode == "eof-running" {
				// The first continue reaches the breakpoint; the second actually
				// runs the loop, after the source stop and inspection have completed.
				_, _ = io.WriteString(writer, "continue\n")
				select {
				case <-out.commands:
				case <-ctx.Done():
					t.Fatal(ctx.Err())
				}
				<-time.After(100 * time.Millisecond)
			}
			wantStatus, wantReason := 1, "cancelled"
			if mode == "eof-running" {
				_ = writer.Close()
				wantStatus, wantReason = 0, "eof"
			} else {
				cancel()
			}
			select {
			case status := <-done:
				if status != wantStatus {
					t.Fatal(status)
				}
			case <-time.After(10 * time.Second):
				t.Fatal("cancel did not join")
			}
			events := decodeEvents(t, out.Bytes())
			assertReaped(t, events)
			if events[len(events)-1].Reason != wantReason {
				t.Fatal(events)
			}
		})
	}
}

type failingWriter struct{ bytes.Buffer }

func (w *failingWriter) Write(data []byte) (int, error) {
	if bytes.Contains(data, []byte(`"event":"result"`)) {
		return 0, errors.New("broken writer")
	}
	return w.Buffer.Write(data)
}

func TestScriptNativeWriterError(t *testing.T) {
	executable, inspection := scriptTarget(t, "export fn main() -> Int:\n    return 0\n")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	var out failingWriter
	if status := Script(ctx, executable, nil, inspection, io.NopCloser(strings.NewReader("break main\nexit\n")), &out, false); status != 1 {
		t.Fatal(status)
	}
	assertTargetGone(t, decodeEvents(t, out.Bytes())) // broken output need not contain final records
}

type sourceClient struct {
	service.Client
	frames               []api.Stackframe
	variables, arguments []api.Variable
}

func (c sourceClient) Stacktrace(_ int64, _ int, _ api.StacktraceOptions, _ *api.LoadConfig) ([]api.Stackframe, error) {
	return c.frames, nil
}
func (c sourceClient) ListLocalVariables(_ api.EvalScope, _ api.LoadConfig) ([]api.Variable, error) {
	return c.variables, nil
}
func (c sourceClient) ListFunctionArgs(_ api.EvalScope, _ api.LoadConfig) ([]api.Variable, error) {
	return c.arguments, nil
}

func TestScriptSourceStackAndScope(t *testing.T) {
	source := api.Stackframe{Location: api.Location{File: "/source/main.ms", Line: 3, Function: &api.Function{Name_: "main.call_symbol1"}}}
	native := api.Stackframe{Location: api.Location{File: "/runtime/main.ms", Line: 3, Function: &api.Function{Name_: "runtime.Invoke"}}}
	v := &sourceView{files: map[string]string{filepath.Clean("/source/main.ms"): "main.ms"}, locals: map[string]tooling.Local{
		"arg1_input": {Name: "input", Type: "Int"}, "local2_value": {Name: "value", Type: "String"}, "local1_old": {Name: "old", Type: "Int"},
	}}
	client := sourceClient{frames: []api.Stackframe{source, native, source, native}, variables: []api.Variable{{Name: "ctx"}, {Name: "local1_old", Flags: api.VariableShadowed}, {Name: "local2_value", Kind: reflect.String, Value: "hello", Len: 5}}, arguments: []api.Variable{{Name: "arg1_input", Kind: reflect.Int64, Value: "42"}}}
	s := scriptSession{client: client, source: v}
	frames, truncated, err := s.stack(2, false)
	if err != nil || truncated || len(frames) != 2 || frames[1].Index != 2 {
		t.Fatalf("filtered frames: %+v %v %v", frames, truncated, err)
	}
	raw, _, err := s.stack(3, true)
	if err != nil || len(raw) != 3 || raw[1].NativeFunction != "runtime.Invoke" {
		t.Fatal(raw, err)
	}
	values, err := s.locals()
	if err != nil || len(values) != 2 || values[0].Name != "input" || values[0].Value != "42" || values[1].Name != "value" {
		t.Fatal(values, err)
	}
	client.frames = []api.Stackframe{native, source}
	s.client = client
	if _, err := s.locals(); err == nil {
		t.Fatal("runtime stop borrowed another frame's locals")
	}
	stop, err := s.stop(&api.DebuggerState{CurrentThread: &api.Thread{File: native.File, Line: native.Line, Function: native.Function}})
	if err != nil || stop.Location.Source || stop.Location.NativeFunction != "runtime.Invoke" || len(stop.Locals) != 0 {
		t.Fatal(stop, err)
	}
	client.frames = []api.Stackframe{{Err: "could not unwind"}}
	s.client = client
	if _, _, err := s.stack(20, false); err == nil {
		t.Fatal("stack unwind error discarded by filtering")
	}
}

type errorInput struct{ io.Reader }

func (r errorInput) Read(p []byte) (int, error) {
	n, err := r.Reader.Read(p)
	if err == io.EOF {
		return n, errors.New("input failure")
	}
	return n, err
}
func (errorInput) Close() error { return nil }

func TestScriptNativeInputError(t *testing.T) {
	executable, inspection := scriptTarget(t, "export fn main() -> Int:\n    var number = 0\n    while number == 0:\n        number = number + 0\n    return number\n")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	var out bytes.Buffer
	status := Script(ctx, executable, nil, inspection, errorInput{strings.NewReader("continue\n")}, &out, false)
	events := decodeEvents(t, out.Bytes())
	assertReaped(t, events)
	if status != 1 || events[len(events)-1].Reason != "error" {
		t.Fatal(status, events)
	}
}
