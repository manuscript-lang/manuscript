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
	code := "import stderr from \"@std/io.ms\"\n\nexport fn main() -> Int:\n    let stream = stderr()\n    let chunk = \"" + strings.Repeat("e", 2048) + "\".to_bytes()\n    while true:\n        let _written = stream.write(data: chunk)\n    return 0\n"
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
