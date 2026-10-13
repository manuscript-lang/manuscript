package debugger

import (
	"context"
	"fmt"
	"net"
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
