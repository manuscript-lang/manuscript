package debugger

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/go-delve/delve/service"
	"github.com/go-delve/delve/service/api"
	"github.com/google/go-dap"
)

type breakpointClient struct {
	service.Client
	breakErr error
	resumed  bool
}

func (c *breakpointClient) CreateBreakpointWithExpr(*api.Breakpoint, string, [][2]string, bool) (*api.Breakpoint, error) {
	if c.breakErr != nil {
		return nil, c.breakErr
	}
	return &api.Breakpoint{ID: 1}, nil
}

func (c *breakpointClient) Continue() <-chan *api.DebuggerState {
	c.resumed = true
	ch := make(chan *api.DebuggerState, 1)
	ch <- &api.DebuggerState{Exited: true}
	close(ch)
	return ch
}

func TestOneShotAbortsBeforeExecutionAfterInvalidBreakpoint(t *testing.T) {
	for _, failure := range []string{"unknown-source-function", "rejected-by-delve", "later-breakpoint"} {
		t.Run(failure, func(t *testing.T) {
			client := &breakpointClient{}
			breaks := []string{"missing"}
			if failure == "rejected-by-delve" {
				client.breakErr = errors.New("no executable statement")
				breaks = []string{"main"}
			} else if failure == "later-breakpoint" {
				breaks = []string{"main", "missing"}
			}
			var out bytes.Buffer
			s := session{client: client, names: testNames(), opts: Options{Breaks: breaks, Out: &out, JSON: true}}
			s.oneShot()
			if !s.failed || client.resumed || strings.Contains(out.String(), `"event":"exit"`) {
				t.Fatalf("invalid setup ran target: resumed %v, failed %v, output %s", client.resumed, s.failed, &out)
			}
		})
	}
}

type readerError struct{ err error }

func (r readerError) Read([]byte) (int, error) { return 0, r.err }

type writerError struct {
	err   error
	short bool
	calls int
}

func (w *writerError) Write(p []byte) (int, error) {
	w.calls++
	if w.short {
		return len(p) - 1, nil
	}
	return 0, w.err
}

func TestScriptReportsInputErrors(t *testing.T) {
	for _, input := range []io.Reader{readerError{io.ErrUnexpectedEOF}, strings.NewReader(strings.Repeat("x", 1024*1024+1))} {
		var out bytes.Buffer
		s := session{opts: Options{Out: &out, JSON: true}}
		s.script(input)
		if s.ioErr == nil || !s.failed || out.Len() != 0 || s.ready() {
			t.Fatalf("input failure not latched before cleanup: %v, %s", s.ioErr, &out)
		}
		if err := reportBounded(context.Background(), &out, false, func() {}, func() error {
			return writeEvent(&out, true, Event{Event: "error", Message: s.inputErr.Error()})
		}); err != nil || !strings.Contains(out.String(), `"event":"error"`) {
			t.Fatalf("healthy output lost the input diagnostic: %v, %s", err, &out)
		}
	}
}

type unexpectedReportWriter struct{ called bool }

func (w *unexpectedReportWriter) Write([]byte) (int, error) {
	w.called = true
	return 0, errors.New("writer has no interruption contract")
}

func TestInputDiagnosticSkipsUninterruptibleWriters(t *testing.T) {
	out := &unexpectedReportWriter{}
	opts, restore, err := ownScriptIO(Options{Out: out})
	if err != nil {
		t.Fatal(err)
	}
	defer restore()
	if opts.CancelIO == nil {
		t.Fatal("test must exercise the automatic ownership hook")
	}
	if err := reportBounded(context.Background(), opts.Out, false, opts.CancelIO, func() error {
		return writeEvent(opts.Out, true, Event{Event: "error", Message: "failed input"})
	}); err != nil || out.called {
		t.Fatalf("uninterruptible writer used: %v, called %v", err, out.called)
	}
}

func TestInputFailureCannotReplaceOutputFailure(t *testing.T) {
	cause := io.ErrClosedPipe
	out := &unexpectedReportWriter{}
	s := session{opts: Options{Out: out}, ioErr: cause}
	s.script(readerError{io.ErrUnexpectedEOF})
	if s.ioErr != cause || s.inputErr != nil || out.called {
		t.Fatalf("output failure latch replaced: %v, input %v, wrote %v", s.ioErr, s.inputErr, out.called)
	}
}

func TestScriptStopsAfterOutputFailure(t *testing.T) {
	for _, json := range []bool{false, true} {
		for _, short := range []bool{false, true} {
			cause := errors.New("broken output")
			out := &writerError{err: cause, short: short}
			s := session{opts: Options{Out: out, JSON: json}}
			s.script(strings.NewReader("unknown\nunknown-again\ncontinue\n"))
			want := cause
			if short {
				want = io.ErrShortWrite
			}
			if !errors.Is(s.ioErr, want) || out.calls != 1 {
				t.Fatalf("output failure not latched: %v, %d writes", s.ioErr, out.calls)
			}
		}
	}
}

func TestScriptCommandErrorsCanBeFollowedByMoreCommands(t *testing.T) {
	var out bytes.Buffer
	s := session{opts: Options{Out: &out, JSON: true}}
	s.script(strings.NewReader("unknown\nunknown-again\nexit\n"))
	if s.ioErr != nil || !s.failed || bytes.Count(out.Bytes(), []byte(`"event":"error"`)) != 2 {
		t.Fatalf("command recovery changed: %v, %s", s.ioErr, &out)
	}
}

func TestCancelableRunnerJoinsOwnedIO(t *testing.T) {
	for _, operation := range []string{"read", "write"} {
		t.Run(operation, func(t *testing.T) {
			input, output := io.Pipe()
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			started, joined := make(chan struct{}), make(chan struct{})
			done := make(chan error, 1)
			go func() {
				_, err := runCancelable(ctx, func() {
					_ = input.Close()
					_ = output.Close()
					close(joined)
				}, func() (int, error) {
					close(started)
					if operation == "read" {
						_, err := input.Read(make([]byte, 1))
						return 1, err
					}
					_, err := output.Write([]byte("event\n"))
					return 1, err
				})
				done <- err
			}()
			<-started
			cancel()
			select {
			case err := <-done:
				if !errors.Is(err, context.Canceled) {
					t.Fatalf("lost cancellation: %v", err)
				}
				select {
				case <-joined:
				default:
					t.Fatal("I/O interrupter still running")
				}
			case <-time.After(5 * time.Second):
				t.Fatal("blocked I/O did not stop")
			}
		})
	}
}

// dapClient drives DAP over an in-memory pipe and records every message.
type dapClient struct {
	t      *testing.T
	conn   net.Conn
	reader *bufio.Reader
	seq    int
	done   chan struct{}
	inbox  chan dap.Message
}

func startDAP(t *testing.T) *dapClient {
	t.Helper()
	server, conn := net.Pipe()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { DAP(ctx, server); close(done) }()
	c := &dapClient{t: t, conn: conn, reader: bufio.NewReader(conn), done: done, inbox: make(chan dap.Message, 1024)}
	// Drain continuously: net.Pipe is synchronous, so an unread event would
	// otherwise block the server while the test is still writing a request.
	go func() {
		defer close(c.inbox)
		for {
			message, err := dap.ReadProtocolMessage(c.reader)
			if err != nil {
				return
			}
			c.inbox <- message
		}
	}()
	t.Cleanup(func() {
		cancel()
		_ = conn.Close()
		select {
		case <-done:
		case <-time.After(10 * time.Second):
			t.Error("DAP session did not stop")
		}
	})
	c.request("initialize", map[string]any{"adapterID": "manuscript", "pathFormat": "path", "linesStartAt1": true, "columnsStartAt1": true})
	c.response("initialize")
	return c
}

func (c *dapClient) request(command string, args any) int {
	c.t.Helper()
	c.seq++
	data, err := json.Marshal(map[string]any{"seq": c.seq, "type": "request", "command": command, "arguments": args})
	if err != nil {
		c.t.Fatal(err)
	}
	_ = c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
	if err := dap.WriteBaseMessage(c.conn, data); err != nil {
		c.t.Fatal(err)
	}
	return c.seq
}

// next reads messages until match accepts one.
func (c *dapClient) next(what string, match func(dap.Message) bool) dap.Message {
	c.t.Helper()
	for {
		select {
		case message, ok := <-c.inbox:
			if !ok {
				c.t.Fatalf("waiting for %s: connection closed", what)
			}
			if match(message) {
				return message
			}
		case <-time.After(15 * time.Second):
			c.t.Fatalf("waiting for %s: timeout", what)
		}
	}
}

// response waits for the response to command, successful or not.
func (c *dapClient) response(command string) dap.ResponseMessage {
	c.t.Helper()
	m := c.next(command+" response", func(m dap.Message) bool {
		r, ok := m.(dap.ResponseMessage)
		return ok && r.GetResponse().Command == command
	})
	return m.(dap.ResponseMessage)
}

// failure expects an unsuccessful response whose message mentions want.
func (c *dapClient) failure(command, want string) {
	c.t.Helper()
	r := c.response(command)
	if r.GetResponse().Success {
		c.t.Fatalf("%s unexpectedly succeeded", command)
	}
	text := r.GetResponse().Message
	if e, ok := r.(*dap.ErrorResponse); ok {
		text += " " + e.Body.Error.Format
	}
	if want != "" && !strings.Contains(text, want) {
		c.t.Fatalf("%s error %q does not mention %q", command, text, want)
	}
	if strings.Contains(text, "nil pointer") || strings.Contains(text, "Internal Error") || strings.Contains(text, "Not yet implemented") {
		c.t.Fatalf("%s leaked an internal error: %q", command, text)
	}
}

// buildTarget compiles a small native program that exits with status 0, or
// runs until killed when run is true.
func buildTarget(t *testing.T, run bool) string {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("native debugger lifecycle tests run on Unix")
	}
	goTool, err := exec.LookPath("go")
	if err != nil {
		t.Skip("go tool unavailable")
	}
	source := "package main\n\nfunc main() {}\n"
	if run {
		source = "package main\n\nimport \"time\"\n\nfunc main() { time.Sleep(time.Minute) }\n"
	}
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "main.go"), []byte(source), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "go.mod"), []byte("module target\n\ngo 1.21\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	out := filepath.Join(dir, "target")
	cmd := exec.Command(goTool, "build", "-gcflags=all=-N -l", "-o", out, ".")
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GOFLAGS=-mod=mod", "GOTOOLCHAIN=local")
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Skipf("cannot build native target: %v\n%s", err, output)
	}
	return out
}

func TestDAPRequestsBeforeSessionAreRejected(t *testing.T) {
	c := startDAP(t)
	for command, args := range map[string]any{
		"pause":             map[string]any{"threadId": 1},
		"continue":          map[string]any{"threadId": 1},
		"next":              map[string]any{"threadId": 1},
		"stepIn":            map[string]any{"threadId": 1},
		"stepOut":           map[string]any{"threadId": 1},
		"threads":           map[string]any{},
		"stackTrace":        map[string]any{"threadId": 1},
		"scopes":            map[string]any{"frameId": 1},
		"variables":         map[string]any{"variablesReference": 1},
		"evaluate":          map[string]any{"expression": "x"},
		"configurationDone": map[string]any{},
		"setBreakpoints":    map[string]any{"source": map[string]string{"path": "/x.ms"}, "breakpoints": []map[string]int{{"line": 1}}},
	} {
		c.request(command, args)
		c.failure(command, "send launch or attach before "+command)
	}
	// Rejected requests leave the adapter usable: a launch still answers.
	c.request("launch", map[string]any{"mode": "exec", "program": "/nonexistent/target"})
	c.failure("launch", "")
	c.request("pause", map[string]any{"threadId": 1})
	c.failure("pause", "send launch or attach before pause")
}

func TestDAPRequestsAreAcceptedOnceSessionExists(t *testing.T) {
	target := buildTarget(t, false)
	c := startDAP(t)
	c.request("launch", map[string]any{"mode": "exec", "program": target, "outputMode": "remote"})
	if r := c.response("launch"); !r.GetResponse().Success {
		t.Fatalf("launch: %+v", r)
	}
	// setBreakpoints arrives after initialized and before the launch response
	// is read by some clients; it must reach Delve.
	c.request("setBreakpoints", map[string]any{"source": map[string]string{"path": "/x.ms"}, "breakpoints": []map[string]int{}})
	if r := c.response("setBreakpoints"); !r.GetResponse().Success {
		t.Fatalf("setBreakpoints: %+v", r)
	}
	c.request("threads", map[string]any{})
	if r := c.response("threads"); !r.GetResponse().Success {
		t.Fatalf("threads: %+v", r)
	}
}

// untilTerminated reads through the terminated event and reports whether an
// exited event came before it.
func (c *dapClient) untilTerminated() (sawExited bool) {
	c.t.Helper()
	c.next("terminated event", func(m dap.Message) bool {
		switch m.(type) {
		case *dap.ExitedEvent:
			sawExited = true
		case *dap.TerminatedEvent:
			return true
		}
		return false
	})
	return sawExited
}

func launchToExit(t *testing.T) *dapClient {
	c := startDAP(t)
	c.request("launch", map[string]any{"mode": "exec", "program": buildTarget(t, false), "outputMode": "remote"})
	c.response("launch")
	c.request("configurationDone", map[string]any{})
	if c.untilTerminated() {
		t.Fatal("exited event reported without a known exit code")
	}
	return c
}

func TestDAPResumingAfterExitIsRejected(t *testing.T) {
	c := launchToExit(t)
	for _, command := range []string{"next", "stepIn", "stepOut", "continue", "pause"} {
		c.request(command, map[string]any{"threadId": 1})
		c.failure(command, "the debuggee has exited")
	}
	// Rejected requests produce no stopped event with reason error.
	c.request("threads", map[string]any{})
	c.next("threads response", func(m dap.Message) bool {
		if e, ok := m.(*dap.StoppedEvent); ok {
			t.Fatalf("unexpected stopped event: %+v", e)
		}
		r, ok := m.(dap.ResponseMessage)
		return ok && r.GetResponse().Command == "threads"
	})
}

func TestDAPTerminate(t *testing.T) {
	succeeds := func(t *testing.T, c *dapClient) {
		t.Helper()
		c.request("terminate", map[string]any{})
		if r := c.response("terminate"); !r.GetResponse().Success {
			t.Fatalf("terminate: %+v", r)
		}
	}
	t.Run("after exit", func(t *testing.T) { succeeds(t, launchToExit(t)) })
	t.Run("before launch", func(t *testing.T) { succeeds(t, startDAP(t)) })
	t.Run("running target", func(t *testing.T) {
		c := startDAP(t)
		c.request("launch", map[string]any{"mode": "exec", "program": buildTarget(t, true), "outputMode": "remote"})
		c.response("launch")
		c.request("configurationDone", map[string]any{})
		c.response("configurationDone")
		succeeds(t, c)
		c.untilTerminated()
	})
}

func TestDAPNoDebugExitReportsExitCode(t *testing.T) {
	c := startDAP(t)
	c.request("launch", map[string]any{"mode": "exec", "program": buildTarget(t, false), "noDebug": true})
	c.response("launch")
	if !c.untilTerminated() {
		t.Fatal("no exited event although Delve printed the exit status")
	}
}
