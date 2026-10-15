package debugger

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"sync"
	"time"
)

const diagnosticWriteBudget = 100 * time.Millisecond

// reportBounded attempts a diagnostic only through known immediate writers or
// interruptible output. Never leave a reporting goroutine behind on timeout.
func reportBounded(ctx context.Context, out io.Writer, callerCanInterrupt bool, interrupt func(), write func() error) error {
	if ctx.Err() != nil {
		return nil
	}
	switch writer := out.(type) {
	case *os.File:
		if !boundedFileWrite(writer) {
			return nil
		}
	case *bytes.Buffer, *strings.Builder:
	default:
		if out != io.Discard && !callerCanInterrupt {
			return nil
		}
	}
	ctx, cancel := context.WithTimeout(ctx, diagnosticWriteBudget)
	defer cancel()
	_, err := runCancelable(ctx, interrupt, func() (int, error) { return 1, write() })
	return err
}

// ReportError makes a best-effort CLI diagnostic after session cleanup. It
// preserves borrowed stderr and skips transports whose write cannot be bounded.
// In particular stdout and stderr may share an unread pipe after a script error.
func ReportError(ctx context.Context, out *os.File, cause error) (err error) {
	if cause == nil || ctx.Err() != nil {
		return nil
	}
	opts, restore, err := ownScriptIO(Options{Out: out})
	if err != nil {
		return err
	}
	defer func() { err = errors.Join(err, restore()) }()
	return reportBounded(ctx, opts.Out, false, opts.CancelIO, func() error {
		_, err := fmt.Fprintln(opts.Out, cause)
		return err
	})
}

// runCancelable joins both the session and its I/O interrupter. On Windows,
// cancellation must stay armed until the worker ends: CancelSynchronousIo only
// cancels an already pending call, so a single call can miss the next read.
func runCancelable(ctx context.Context, interrupt func(), run func() (int, error)) (status int, err error) {
	type result struct {
		status int
		err    error
	}
	ready := make(chan func() error, 1)
	done := make(chan result, 1)
	release := make(chan struct{})
	joined := make(chan struct{})
	finished := make(chan error, 1)
	go func() {
		defer close(joined)
		cancelThread, finish, err := cancellationThread()
		if err != nil {
			ready <- func() error { return nil }
			done <- result{1, err}
			finished <- nil
			return
		}
		defer func() { finished <- finish() }()
		ready <- cancelThread
		status, err := run()
		done <- result{status, err}
		// Keep a Windows thread handle valid until the interrupter has stopped.
		<-release
	}()
	cancelThread := <-ready
	var cancelErr error
	defer func() {
		close(release)
		<-joined
		if finishErr := errors.Join(cancelErr, <-finished); finishErr != nil {
			status, err = 1, errors.Join(err, finishErr)
		}
	}()
	select {
	case result := <-done:
		if err := ctx.Err(); err != nil {
			return 1, errors.Join(err, result.err)
		}
		return result.status, result.err
	case <-ctx.Done():
	}
	interrupted := make(chan struct{})
	go func() { interrupt(); close(interrupted) }()
	tick := time.NewTicker(10 * time.Millisecond)
	defer tick.Stop()
	for {
		if err := cancelThread(); cancelErr == nil {
			cancelErr = err
		}
		select {
		case result := <-done:
			<-interrupted
			return 1, errors.Join(ctx.Err(), result.err)
		case <-tick.C:
		}
	}
}

// ownScriptIO makes standard file I/O interruptible without closing borrowed
// handles. Restore runs after service shutdown, so inherited target handles no
// longer depend on any shared Unix descriptor flags.
func ownScriptIO(opts Options) (Options, func() error, error) {
	var files []*os.File
	var restores []func() error
	var closeErr error
	closeFiles := sync.OnceFunc(func() {
		for _, file := range files {
			closeErr = errors.Join(closeErr, file.Close())
		}
	})
	restore := func() error {
		closeFiles()
		err := closeErr
		for i := len(restores) - 1; i >= 0; i-- {
			err = errors.Join(err, restores[i]())
		}
		return err
	}
	input, _ := opts.Script.(*os.File)
	output, _ := opts.Out.(*os.File)
	for _, stream := range []struct {
		file *os.File
		set  func(*os.File)
	}{
		{input, func(f *os.File) { opts.Script = f }},
		{output, func(f *os.File) { opts.Out = f }},
	} {
		if stream.file == nil {
			continue
		}
		file, undo, err := duplicateIO(stream.file)
		if err != nil {
			err = errors.Join(err, restore())
			return opts, func() error { return nil }, err
		}
		files = append(files, file)
		restores = append(restores, undo)
		stream.set(file)
	}
	previous := opts.CancelIO
	opts.CancelIO = func() {
		if previous != nil {
			previous()
		}
		closeFiles()
	}
	return opts, restore, nil
}
