package debugger

import (
	"context"
	"net"
	"testing"
	"time"
)

func TestDAPShutdown(t *testing.T) {
	for _, mode := range []string{"cancel-before-client", "cancel-connected", "transport-loss", "malformed-client"} {
		t.Run(mode, func(t *testing.T) {
			server, conn := net.Pipe()
			defer conn.Close()
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			done := make(chan struct{})
			go func() { DAP(ctx, server); close(done) }()
			switch mode {
			case "cancel-before-client", "cancel-connected":
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
