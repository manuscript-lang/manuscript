// Package debugger embeds Delve's public service APIs. No dlv executable is used.
package debugger

import (
	"context"
	"fmt"
	"io"
	"os"

	"github.com/go-delve/delve/pkg/config"
	"github.com/go-delve/delve/pkg/terminal"
	"github.com/go-delve/delve/service"
	"github.com/go-delve/delve/service/dap"
	delve "github.com/go-delve/delve/service/debugger"
	"github.com/go-delve/delve/service/rpc2"
	"github.com/go-delve/delve/service/rpccommon"
)

// DAP serves one session over an owned private transport. It joins the read
// loop on every shutdown path before returning, including cancellation before
// the first request. A launched target is halted, killed and reaped by Close.
func DAP(ctx context.Context, transport io.ReadWriteCloser) {
	cfg := &dap.Config{Config: &service.Config{
		// The protocol owns stdin. In particular Windows inherits this handle
		// even for background targets; sharing it can block target startup or let
		// a target consume DAP requests. Match the old adapter's ignored stdin.
		Debugger: delve.Config{Backend: "default", CheckGoVersion: true, Stdin: os.DevNull},
	}, StopTriggered: make(chan struct{})}
	transport = newExecTransport(transport)
	session := dap.NewSession(transport, cfg, nil)
	done := make(chan struct{})
	go func() { session.ServeDAPCodec(); close(done) }()
	select {
	case <-done:
	case <-ctx.Done():
	}
	close(cfg.StopTriggered)
	// Unblock protocol writes as well as reads before detaching the target.
	_ = transport.Close()
	session.Close()
	<-done
}

// Terminal runs the ordinary Delve terminal against an in-process RPC service.
// The private pipe is never exposed as a network listener. Delve owns Ctrl-C;
// the caller cancels ctx on termination so a launched target is reaped.
func Terminal(ctx context.Context, executable string, args []string) (int, error) {
	listener, conn := service.ListenerPipe()
	defer listener.Close()
	defer conn.Close()
	server := rpccommon.NewServer(&service.Config{
		Listener: listener, ProcessArgs: append([]string{executable}, args...), APIVersion: 2,
		Debugger: delve.Config{Backend: "default", WorkingDir: ".", CheckGoVersion: true, ExecuteKind: delve.ExecutingExistingFile},
	})
	if err := server.Run(); err != nil {
		return 1, err
	}
	defer server.Stop()
	conf, err := config.LoadConfig()
	if err != nil {
		return 1, err
	}
	term := terminal.New(msClient{rpc2.NewClientFromConn(conn)}, conf)
	type result struct {
		status int
		err    error
	}
	done := make(chan result, 1)
	go func() { status, err := term.Run(); done <- result{status, err} }()
	select {
	case result := <-done:
		return result.status, result.err
	case <-ctx.Done():
		// Run can be blocked reading a terminal. Restore it before the CLI exits;
		// the deferred server stop halts and detaches the target first.
		term.Close()
		return 1, ctx.Err()
	}
}

// Manuscript source maps already identify source files. Delve's Go-module path
// guessing invokes go list/env from PATH and does not describe these targets.
type msClient struct{ service.Client }

func (msClient) GuessSubstitutePath() ([][2]string, error) {
	return nil, fmt.Errorf("Go-module path guessing is unavailable; use the Manuscript source paths or explicit substitute-path rules")
}
