//go:build !windows

package e2e_test

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDebugScriptInterruptsCommandInput(t *testing.T) {
	source := filepath.Join(t.TempDir(), "main.ms")
	if err := os.WriteFile(source, []byte(debugScriptSource), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	command := exec.CommandContext(ctx, cliBinary, "debug", source, "--json", "--script", "-")
	input, err := command.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	output, err := command.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	command.Stderr = &stderr
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	if _, err := io.WriteString(input, "break add\ncontinue\n"); err != nil {
		t.Fatal(err)
	}
	reader := bufio.NewReader(output)
	for range 2 {
		line, err := reader.ReadBytes('\n')
		if err != nil {
			_ = command.Wait()
			t.Fatalf("debug did not stop: %v\n%s", err, &stderr)
		}
		decodeDebugEvents(t, line)
	}
	if err := command.Process.Signal(os.Interrupt); err != nil {
		t.Fatal(err)
	}
	// Leave stdin open. Cancellation must unblock the owned command reader.
	finished := make(chan error, 1)
	go func() { _, _ = io.Copy(io.Discard, reader); finished <- command.Wait() }()
	select {
	case err := <-finished:
		var exit *exec.ExitError
		if !errors.As(err, &exit) || exit.ExitCode() != 1 {
			t.Fatalf("interrupt status %v\n%s", err, &stderr)
		}
	case <-time.After(10 * time.Second):
		cancel()
		<-finished
		t.Fatal("debug remained blocked after interrupt")
	}
}

func TestDebugScriptInterruptsBlockedTargetOutput(t *testing.T) {
	source := filepath.Join(t.TempDir(), "main.ms")
	code := "import stderr from \"@std/io.ms\"\n\nexport fn main() Int:\n    let stream = stderr()\n    let chunk = \"" + strings.Repeat("e", 2048) + "\".to_bytes()\n    while true:\n        let _written = stream.write_bytes(data: chunk)\n    return 0\n"
	if err := os.WriteFile(source, []byte(code), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	command := exec.CommandContext(ctx, cliBinary, "debug", source, "--json", "--script", "-")
	input, err := command.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	output, err := command.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	errorOutput, err := command.StderrPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	if _, err := io.WriteString(input, "continue\n"); err != nil {
		t.Fatal(err)
	}
	drained := make(chan struct{})
	go func() { _, _ = io.Copy(io.Discard, output); close(drained) }()
	prefix := make([]byte, 1024)
	if _, err := io.ReadFull(errorOutput, prefix); err != nil || string(prefix) != strings.Repeat("e", len(prefix)) {
		cancel()
		_ = command.Wait()
		<-drained
		t.Fatalf("target did not write stderr: %v\n%s", err, prefix)
	}
	// The target keeps writing until this unread pipe fills. The cancellation
	// diagnostic must not try another write to the restored, full stderr pipe.
	time.Sleep(200 * time.Millisecond)
	if err := command.Process.Signal(os.Interrupt); err != nil {
		t.Fatal(err)
	}
	finished := make(chan error, 1)
	go func() { finished <- command.Wait() }()
	select {
	case err := <-finished:
		<-drained
		var exit *exec.ExitError
		if !errors.As(err, &exit) || exit.ExitCode() != 1 {
			t.Fatalf("interrupt status %v", err)
		}
	case <-time.After(10 * time.Second):
		cancel()
		<-finished
		<-drained
		t.Fatal("debug remained blocked on stderr after interrupt")
	}
}

func TestDebugScriptFatalInputWithFullSharedOutput(t *testing.T) {
	root := t.TempDir()
	source, commands := filepath.Join(root, "main.ms"), filepath.Join(root, "commands.txt")
	if err := os.WriteFile(source, []byte("export fn main() Int:\n    return 0\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(commands, []byte(strings.Repeat("x", 1024*1024+1)), 0600); err != nil {
		t.Fatal(err)
	}
	status, events, stderr := cliStreams(t, "debug", source, "--json", "--script", commands)
	if status != 1 || !bytes.Contains(events, []byte("bufio.Scanner: token too long")) || !strings.Contains(stderr, "read debug commands") {
		t.Fatalf("healthy output lost the input failure: %d\n%s\n%s", status, events, stderr)
	}
	reader, sharedOutput, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	defer sharedOutput.Close()
	if err := sharedOutput.SetWriteDeadline(time.Now().Add(10 * time.Millisecond)); err != nil {
		t.Fatal(err)
	}
	if n, err := sharedOutput.Write(make([]byte, 1024*1024)); n == 0 || !errors.Is(err, os.ErrDeadlineExceeded) {
		t.Fatalf("shared stdout/stderr did not fill: %d, %v", n, err)
	}
	if err := sharedOutput.SetWriteDeadline(time.Time{}); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, cliBinary, "debug", source, "--json", "--script", commands)
	command.Stdout, command.Stderr = sharedOutput, sharedOutput
	err = command.Run()
	var exit *exec.ExitError
	if ctx.Err() != nil || !errors.As(err, &exit) || exit.ExitCode() != 1 {
		t.Fatalf("fatal input blocked on shared stdout/stderr: %v, ctx %v", err, ctx.Err())
	}
}
