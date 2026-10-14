// Package debugger embeds Delve's public service APIs. No dlv executable is used.
package debugger

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"sync"

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
	transport = &execTransport{ReadWriteCloser: transport, reader: bufio.NewReader(transport), startSession: func() {
		// Delve records an attach target in the shared configuration before it
		// knows the attach will succeed, and a failed attach leaves it behind. The
		// next launch would then try to attach to that process instead of starting
		// its program. Every session start begins from a clean target selection.
		// This runs on the request loop, so it cannot race the handlers.
		cfg.Debugger.AttachPid, cfg.Debugger.AttachWaitFor, cfg.Debugger.AttachWaitForInterval = 0, "", 0
	}}
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

var terminalStdioMu sync.Mutex

// Terminal runs the ordinary Delve terminal against an in-process RPC service.
// The private pipe is never exposed as a network listener. Delve owns Ctrl-C;
// the caller cancels ctx on termination so a launched target is reaped.
func Terminal(ctx context.Context, executable string, args []string) (status int, err error) {
	if err := ctx.Err(); err != nil {
		return 1, err
	}
	// Delve/liner use process stdio and console handles for editing and modes.
	// A CLI has one terminal; serialize ownership for embedded callers too.
	terminalStdioMu.Lock()
	defer terminalStdioMu.Unlock()
	if err := ctx.Err(); err != nil {
		return 1, err
	}
	listener, conn := service.ListenerPipe()
	defer listener.Close()
	defer conn.Close()
	server := rpccommon.NewServer(&service.Config{
		Listener: listener, ProcessArgs: append([]string{executable}, args...), APIVersion: 2,
		Debugger: delve.Config{Backend: "default", WorkingDir: ".", CheckGoVersion: true, ExecuteKind: delve.ExecutingExistingFile},
	})
	if err := ctx.Err(); err != nil {
		return 1, err
	}
	if err := server.Run(); err != nil {
		return 1, err
	}
	restoreIO, restoreErrors := func() error { return nil }, func() error { return nil }
	defer func() {
		stopErr := server.Stop()
		if closeErr := errors.Join(stopErr, restoreErrors(), restoreIO()); closeErr != nil {
			status, err = 1, errors.Join(err, closeErr)
		}
	}()
	// Launch may call Fd on inherited files. Own them after that call so their
	// shared flags remain nonblocking throughout terminal reads and writes.
	var opts, errorOpts Options
	opts, restoreIO, err = ownScriptIO(Options{Script: os.Stdin, Out: os.Stdout})
	if err != nil {
		return 1, err
	}
	errorOpts, restoreErrors, err = ownScriptIO(Options{Out: os.Stderr})
	if err != nil {
		return 1, err
	}
	conf, err := config.LoadConfig()
	if err != nil {
		return 1, err
	}
	input, output, errorOutput := opts.Script.(*os.File), opts.Out.(*os.File), errorOpts.Out.(*os.File)
	undoConsole, err := replaceConsoleStdio(input, output, errorOutput)
	if err != nil {
		return 1, err
	}
	defer func() {
		if consoleErr := undoConsole(); consoleErr != nil {
			status, err = 1, errors.Join(err, consoleErr)
		}
	}()
	oldInput, oldOutput, oldError := os.Stdin, os.Stdout, os.Stderr
	os.Stdin, os.Stdout, os.Stderr = input, output, errorOutput
	defer func() { os.Stdin, os.Stdout, os.Stderr = oldInput, oldOutput, oldError }()
	interruptIO := func() { opts.CancelIO(); errorOpts.CancelIO() }
	client := rpc2.NewClientFromConn(conn)
	defer client.Disconnect(false)
	return runCancelable(ctx, func() {
		_ = client.Disconnect(false)
		interruptIO()
	}, func() (int, error) {
		term := terminal.New(msClient{client}, conf)
		status, err := term.RunWithContext(ctx)
		interruptIO()
		term.WaitForInput()
		return status, err
	})
}

// Manuscript source maps already identify source files. Delve's Go-module path
// guessing invokes go list/env from PATH and does not describe these targets.
type msClient struct{ service.Client }

func (msClient) GuessSubstitutePath() ([][2]string, error) {
	return nil, fmt.Errorf("Go-module path guessing is unavailable; use the Manuscript source paths or explicit substitute-path rules")
}
