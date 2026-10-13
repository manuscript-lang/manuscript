package debugger

import (
	"bufio"
	"context"
	"fmt"
	"github.com/google/go-dap"
	"net"
	"strings"
	"testing"
	"time"
)

func TestDAPShutdown(t *testing.T) {
	for _, mode := range []string{"cancel-before-client", "cancel-unread-response", "transport-loss", "malformed-client"} {
		t.Run(mode, func(t *testing.T) {
			server, conn := net.Pipe()
			defer conn.Close()
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			done := make(chan struct{})
			go func() { DAP(ctx, server); close(done) }()
			switch mode {
			case "cancel-unread-response":
				body := `{"seq":1,"type":"request","command":"initialize","arguments":{"adapterID":"manuscript"}}`
				_ = conn.SetWriteDeadline(time.Now().Add(time.Second))
				_, _ = fmt.Fprintf(conn, "Content-Length: %d\r\n\r\n%s", len(body), body)
				cancel()
			case "cancel-before-client":
				cancel()
			case "transport-loss":
				_ = conn.Close()
			case "malformed-client":
				_, _ = conn.Write([]byte("invalid header\r\n\r\n"))
			}
			select {
			case <-done:
			case <-time.After(5 * time.Second):
				t.Fatal("DAP failed to stop")
			}
		})
	}
}

func TestDAPRejectsGoBuildModes(t *testing.T) {
	for _, mode := range []string{"", "debug", "test"} {
		t.Run(mode, func(t *testing.T) {
			t.Setenv("PATH", t.TempDir())
			server, conn := net.Pipe()
			defer conn.Close()
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			done := make(chan struct{})
			go func() { DAP(ctx, server); close(done) }()
			_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
			body := fmt.Sprintf(`{"seq":1,"type":"request","command":"launch","arguments":{"mode":%q,"program":"missing.go"}}`, mode)
			if _, err := fmt.Fprintf(conn, "Content-Length: %d\r\n\r\n%s", len(body), body); err != nil {
				t.Fatal(err)
			}
			message, err := dap.ReadProtocolMessage(bufio.NewReader(conn))
			if err != nil {
				t.Fatal(err)
			}
			response, ok := message.(*dap.ErrorResponse)
			if !ok || response.Success || !strings.Contains(response.Body.Error.Format, "ms requires mode exec") {
				t.Fatalf("not rejected before tool discovery: %#v", message)
			}
			cancel()
			select {
			case <-done:
			case <-time.After(5 * time.Second):
				t.Fatal("session did not exit")
			}
		})
	}
}
