package debugger

import (
	"bytes"
	"context"
	"errors"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/go-delve/delve/service"
	"github.com/go-delve/delve/service/api"
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
