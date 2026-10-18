//go:build unix

package e2e_test

import (
	"bufio"
	"bytes"
	"context"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func shutdownExamples(t *testing.T) map[string]string {
	t.Helper()
	examples := map[string]string{}
	for _, name := range []string{"observer", "server"} {
		data, err := os.ReadFile(filepath.Join("testdata", "shutdown", name+".source"))
		if err != nil {
			t.Fatal(err)
		}
		examples[name] = string(data)
	}
	return examples
}

type shutdownChild struct {
	command *exec.Cmd
	cancel  context.CancelFunc
	lines   chan string
	stderr  bytes.Buffer
	waited  bool
}

func startShutdownChild(t *testing.T, binary string, args ...string) *shutdownChild {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	child := &shutdownChild{cancel: cancel, lines: make(chan string, 16)}
	child.command = exec.CommandContext(ctx, binary, args...)
	// Every signal targets this disposable child. On timeout/failure kill its
	// private process group as well, so an ms run launcher cannot leave an orphan.
	child.command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	child.command.Cancel = func() error {
		return syscall.Kill(-child.command.Process.Pid, syscall.SIGKILL)
	}
	child.command.Stderr = &child.stderr
	stdout, err := child.command.StdoutPipe()
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	if err := child.command.Start(); err != nil {
		cancel()
		t.Fatal(err)
	}
	go func() {
		defer close(child.lines)
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			child.lines <- scanner.Text()
		}
	}()
	t.Cleanup(func() {
		cancel()
		if !child.waited {
			for range child.lines {
			}
			_ = child.command.Wait()
		}
	})
	return child
}

func (child *shutdownChild) line(t *testing.T) string {
	t.Helper()
	line, ok := <-child.lines
	if !ok {
		err := child.command.Wait()
		child.waited = true
		t.Fatalf("child exited before readiness: %v, stderr %s", err, child.stderr.String())
	}
	return line
}

func (child *shutdownChild) finish(t *testing.T, signal syscall.Signal) []string {
	t.Helper()
	var lines []string
	for line := range child.lines {
		lines = append(lines, line)
	}
	err := child.command.Wait()
	child.waited = true
	exit, ok := err.(*exec.ExitError)
	if !ok || exit.ExitCode() != 128+int(signal) || child.stderr.Len() != 0 {
		t.Fatalf("shutdown: %v, stdout %q, stderr %s", err, lines, child.stderr.String())
	}
	return lines
}

func TestShutdownCookbook(t *testing.T) {
	examples := shutdownExamples(t)
	for _, name := range []string{"observer", "server"} {
		source := examples[name]
		directory := t.TempDir()
		file := filepath.Join(directory, name+".ms")
		if err := os.WriteFile(file, []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
		binary := filepath.Join(directory, name)
		if output, err := commandOutput(t, cliBinary, "build", file, "-o", binary); err != nil {
			t.Fatalf("build cookbook example: %v\n%s", err, output)
		}
		for _, launcher := range []string{"native", "launcher"} {
			for _, signal := range []syscall.Signal{syscall.SIGINT, syscall.SIGTERM} {
				t.Run(name+"/"+launcher+"/"+signal.String(), func(t *testing.T) {
					program := binary
					var args []string
					if launcher == "launcher" {
						program, args = cliBinary, []string{"run", file}
					}
					child := startShutdownChild(t, program, args...)
					if name == "observer" {
						if line := child.line(t); line != "waiting" {
							t.Fatalf("observer readiness: %q", line)
						}
						if err := child.command.Process.Signal(signal); err != nil {
							t.Fatal(err)
						}
						lines := child.finish(t, signal)
						// Observation is a race, not a shutdown guarantee. Accept
						// any valid prefix; do not require "got signal" or rely on
						// scheduling to forbid "after sleep" on an overloaded host.
						transcript := strings.Join(lines, "\n")
						t.Logf("observer stdout after readiness: %q", transcript)
						if transcript != "" && transcript != "got signal" && transcript != "got signal\nafter sleep" {
							t.Fatalf("unexpected observer transcript: %q", transcript)
						}
						return
					}
					connection, err := net.DialTimeout("tcp", child.line(t), 2*time.Second)
					if err != nil {
						t.Fatal(err)
					}
					defer connection.Close()
					if err := connection.SetReadDeadline(time.Now().Add(5 * time.Second)); err != nil {
						t.Fatal(err)
					}
					if line := child.line(t); line != "ready" {
						t.Fatalf("worker readiness: %q", line)
					}
					if err := child.command.Process.Signal(signal); err != nil {
						t.Fatal(err)
					}
					data, err := io.ReadAll(connection)
					if err != nil || string(data) != "farewell\n" {
						t.Fatalf("farewell and EOF: %q, %v", data, err)
					}
					if lines := child.finish(t, signal); strings.Join(lines, "\n") != "worker stopped\nfarewell sent" {
						t.Fatalf("worker cleanup must finish before synchronous farewell: %q", lines)
					}
				})
			}
		}
	}
}
