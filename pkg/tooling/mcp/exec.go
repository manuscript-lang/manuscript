package mcp

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"time"
)

// Output is the captured result of one ms subprocess.
type Output struct {
	Stdout, Stderr string
	Code           int
	TimedOut       bool
	Truncated      bool
}

// Executor runs ms with arguments in dir. Tests substitute it.
type Executor func(ctx context.Context, dir string, args []string, timeout time.Duration) (Output, error)

const outputLimit = 256 << 10

// capWriter keeps the first outputLimit bytes and notes that more arrived.
type capWriter struct {
	buf       bytes.Buffer
	truncated bool
}

func (w *capWriter) Write(p []byte) (int, error) {
	if room := outputLimit - w.buf.Len(); room < len(p) {
		w.truncated = true
		p = p[:max(room, 0)]
		w.buf.Write(p)
		return len(p), nil
	}
	w.buf.Write(p)
	return len(p), nil
}

// SelfExecutor runs this same ms binary, so the server always matches its compiler.
func SelfExecutor(ctx context.Context, dir string, args []string, timeout time.Duration) (Output, error) {
	self, err := os.Executable()
	if err != nil {
		return Output{}, err
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	command := exec.CommandContext(ctx, self, args...)
	command.Dir = dir
	command.Stdin = nil
	var stdout, stderr capWriter
	command.Stdout, command.Stderr = &stdout, &stderr
	configureGroup(command)
	runErr := command.Run()
	out := Output{Stdout: stdout.buf.String(), Stderr: stderr.buf.String(), Truncated: stdout.truncated || stderr.truncated}
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		out.TimedOut = true
		out.Code = -1
		return out, nil
	}
	var exit *exec.ExitError
	switch {
	case runErr == nil:
	case errors.As(runErr, &exit):
		out.Code = exit.ExitCode()
	default:
		return out, runErr
	}
	return out, nil
}
