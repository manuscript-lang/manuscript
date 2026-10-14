package debugger

import (
	"bufio"
	"context"
	"encoding/json"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/google/go-dap"
)

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

func (c *dapClient) event(name string) dap.EventMessage {
	c.t.Helper()
	m := c.next(name+" event", func(m dap.Message) bool {
		e, ok := m.(dap.EventMessage)
		return ok && e.GetEvent().Event == name
	})
	return m.(dap.EventMessage)
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

// buildTarget compiles a small native program that exits with status 0.
func buildTarget(t *testing.T) string {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("native debugger lifecycle tests run on Unix")
	}
	goTool, err := exec.LookPath("go")
	if err != nil {
		t.Skip("go tool unavailable")
	}
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "main.go"), []byte("package main\n\nfunc main() { println(\"done\") }\n"), 0o600); err != nil {
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

func TestDAPFailedAttachDoesNotPoisonLaunch(t *testing.T) {
	target := buildTarget(t)
	c := startDAP(t)
	c.request("attach", map[string]any{"mode": "local", "processId": 999999})
	c.failure("attach", "")
	c.request("launch", map[string]any{"mode": "exec", "program": target, "stopOnEntry": true})
	if r := c.response("launch"); !r.GetResponse().Success {
		t.Fatalf("launch after failed attach: %+v", r)
	}
}
