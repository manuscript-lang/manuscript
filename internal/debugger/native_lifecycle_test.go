package debugger

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/go-delve/delve/pkg/config"
)

func TestNativeDebugLifecycle(t *testing.T) {
	if os.Getenv("MANUSCRIPT_DEBUG_TEST") != "1" {
		t.Skip("set MANUSCRIPT_DEBUG_TEST=1 to run native debugger lifecycle checks")
	}
	root := t.TempDir()
	source := filepath.Join(root, "main.go")
	// A large source line makes the stop event exceed the output pipe's capacity.
	code := "package main\nimport (\"os\"; \"strconv\"; \"time\")\nfunc marker() {\n" +
		" time.Sleep(time.Second) // " + strings.Repeat("x", 512*1024) + "\n}\n" +
		"func main() {\n os.WriteFile(os.Args[1], []byte(strconv.Itoa(os.Getpid())), 0600)\n marker()\n for { time.Sleep(time.Second) }\n}\n"
	if err := os.WriteFile(source, []byte(code), 0600); err != nil {
		t.Fatal(err)
	}
	goPath := filepath.Join("..", "..", "toolchain", "go", "bin", "go")
	target := filepath.Join(root, "target")
	if runtime.GOOS == "windows" {
		goPath += ".exe"
		target += ".exe"
	}
	build := exec.Command(goPath, "build", "-gcflags=all=-N -l", "-o", target, source)
	build.Env = append(os.Environ(), "CGO_ENABLED=0")
	if data, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build debug fixture: %v\n%s", err, data)
	}
	self, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	modes := []string{"one-shot-invalid", "script-eof", "script-read-error", "script-output-error", "script-full-output-read-error", "script-full-output-oversized", "script-null-input", "script-null-stdio", "terminal-null-stdio", "script-cancel-input", "script-cancel-output", "continue-cancel", "terminal-cancel", "terminal-embedded-prompt-cancel", "terminal-cancel-stderr", "terminal-eof"}
	if runtime.GOOS == "windows" {
		modes = append(modes, "terminal-console-cancel")
	}
	for _, mode := range modes {
		t.Run(mode, func(t *testing.T) {
			pidFile, cancelFile := filepath.Join(t.TempDir(), "pid"), filepath.Join(t.TempDir(), "cancel")
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()
			cmd := exec.CommandContext(ctx, self, "-test.run=^TestNativeDebugLifecycleChild$", "-test.timeout=18s")
			cmd.Env = append(os.Environ(), "XDG_CONFIG_HOME="+filepath.Join(root, "config"), "MANUSCRIPT_DEBUG_CHILD="+mode, "MANUSCRIPT_DEBUG_TARGET="+target, "MANUSCRIPT_DEBUG_SOURCE="+source, "MANUSCRIPT_DEBUG_PID="+pidFile, "MANUSCRIPT_DEBUG_CANCEL="+cancelFile)
			if strings.Contains(mode, "null-") {
				null, err := os.OpenFile(os.DevNull, os.O_RDWR, 0)
				if err != nil {
					t.Fatal(err)
				}
				defer null.Close()
				cmd.Stdin, cmd.Stdout, cmd.Stderr = null, null, null
				if err := cmd.Run(); err != nil {
					t.Fatalf("native redirected null streams: %v", err)
				}
				if mode == "script-null-stdio" {
					assertTargetExited(t, pidFile)
				} else if fileExists(pidFile) {
					t.Fatal("EOF from null input unexpectedly ran the target")
				}
				return
			}
			input, err := cmd.StdinPipe()
			if err != nil {
				t.Fatal(err)
			}
			defer input.Close()
			output, err := cmd.StdoutPipe()
			if err != nil {
				t.Fatal(err)
			}
			var stderr bytes.Buffer
			var errorPipe io.ReadCloser
			if mode == "terminal-cancel-stderr" {
				errorPipe, err = cmd.StderrPipe()
				if err != nil {
					t.Fatal(err)
				}
			} else {
				cmd.Stderr = &stderr
			}
			if err := cmd.Start(); err != nil {
				t.Fatal(err)
			}
			commands := "break marker\ncontinue\n"
			if strings.HasPrefix(mode, "terminal-") {
				commands = "break " + source + ":4\ncontinue\nprint \"LIFECYCLE_READY\"\n"
			}
			if errorPipe != nil {
				testBlockedTerminalErrors(t, cmd, input, output, errorPipe, commands, cancelFile)
				assertTargetExited(t, pidFile)
				return
			}
			if mode == "script-cancel-input" || mode == "terminal-cancel" || mode == "terminal-eof" {
				if _, err := io.WriteString(input, commands); err != nil {
					t.Fatal(err)
				}
			}
			if mode == "terminal-eof" {
				_ = input.Close()
			}
			reader := bufio.NewReader(output)
			var captured bytes.Buffer
			if mode == "script-cancel-output" {
				// Read just the event prefix, then leave the large write blocked.
				for !bytes.Contains(captured.Bytes(), []byte(`"source":`)) {
					b, err := reader.ReadByte()
					if err != nil {
						t.Fatalf("no blocked stop event: %v, %s\n%s", err, &captured, &stderr)
					}
					captured.WriteByte(b)
				}
			} else if mode == "script-cancel-input" || mode == "terminal-cancel" || mode == "terminal-embedded-prompt-cancel" {
				marker := `"event":"stop"`
				if strings.HasPrefix(mode, "terminal-") {
					marker = `"LIFECYCLE_READY"`
				}
				for !strings.Contains(captured.String(), marker) {
					line, err := reader.ReadString('\n')
					captured.WriteString(line)
					if err != nil {
						t.Fatalf("no ready prompt: %v, %s\n%s", err, &captured, &stderr)
					}
				}
			} else if mode == "continue-cancel" {
				for !fileExists(pidFile) && ctx.Err() == nil {
					time.Sleep(10 * time.Millisecond)
				}
			}
			if strings.Contains(mode, "cancel") && mode != "terminal-console-cancel" {
				if err := os.WriteFile(cancelFile, nil, 0600); err != nil {
					t.Fatal(err)
				}
			}
			if !unreadSessionOutput(mode) {
				_, _ = io.Copy(&captured, reader)
			}
			if err := cmd.Wait(); err != nil {
				t.Fatalf("native %s: %v\n%s\n%s", mode, err, &captured, &stderr)
			}
			if mode == "one-shot-invalid" || mode == "terminal-console-cancel" {
				if fileExists(pidFile) {
					t.Fatal("session unexpectedly executed the target")
				}
				return
			}
			assertTargetExited(t, pidFile)
		})
	}
}

func unreadSessionOutput(mode string) bool {
	return mode == "script-cancel-output" || strings.HasPrefix(mode, "script-full-output-")
}

func assertTargetExited(t *testing.T, pidFile string) {
	t.Helper()
	data, err := os.ReadFile(pidFile)
	if err != nil {
		t.Fatal(err)
	}
	pid, err := strconv.Atoi(string(data))
	if err != nil {
		t.Fatal(err)
	}
	if processAlive(pid) {
		process, _ := os.FindProcess(pid)
		_ = process.Kill()
		_ = process.Release()
		t.Fatalf("target %d survived session return", pid)
	}
}

func testBlockedTerminalErrors(t *testing.T, cmd *exec.Cmd, input io.WriteCloser, output, errorPipe io.Reader, commands, cancelFile string) {
	t.Helper()
	drained, written := make(chan struct{}), make(chan struct{})
	var stdout bytes.Buffer
	go func() { _, _ = io.Copy(&stdout, output); close(drained) }()
	go func() {
		_, _ = io.WriteString(input, commands+strings.Repeat("unknown-command\n", 10000))
		close(written)
	}()
	prefix := make([]byte, 1024)
	if _, err := io.ReadFull(errorPipe, prefix); err != nil {
		t.Fatal(err)
	}
	// The remaining diagnostics exceed pipe capacity. Leave stderr unread while
	// the local command loop fills it; stdout is drained independently.
	time.Sleep(200 * time.Millisecond)
	if err := os.WriteFile(cancelFile, nil, 0600); err != nil {
		t.Fatal(err)
	}
	err := cmd.Wait()
	_ = input.Close()
	<-written
	<-drained
	if err != nil {
		t.Fatalf("blocked terminal stderr: %v\n%s\n%s", err, &stdout, prefix)
	}
}

func fileExists(path string) bool { _, err := os.Stat(path); return err == nil }

type stopErrorWriter struct{}

func (stopErrorWriter) Write(p []byte) (int, error) {
	if bytes.Contains(p, []byte(`"event":"stop"`)) {
		return 0, io.ErrClosedPipe
	}
	return len(p), nil
}

type inputDiagnosticWriter struct {
	output  *os.File
	pidFile string
}

func (w inputDiagnosticWriter) Write(p []byte) (int, error) {
	if !bytes.Contains(p, []byte(`"event":"error"`)) {
		return len(p), nil
	}
	pid, err := os.ReadFile(w.pidFile)
	if err != nil {
		return 0, err
	}
	n, err := strconv.Atoi(string(pid))
	if err != nil || processAlive(n) {
		return 0, errors.New("input diagnostic started before target cleanup")
	}
	return w.output.Write(p)
}

func fullDiagnosticOutput(t *testing.T, pidFile string) (io.Writer, func(), func() error) {
	t.Helper()
	prime, restorePrime, err := duplicateIO(os.Stdout)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	_, err = runCancelable(ctx, func() { _ = prime.Close() }, func() (int, error) {
		_, err := prime.Write(make([]byte, 512*1024))
		return 1, err
	})
	cancel()
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("output pipe did not fill: %v", err)
	}
	if err := restorePrime(); err != nil {
		t.Fatal(err)
	}
	output, restore, err := duplicateIO(os.Stdout)
	if err != nil {
		t.Fatal(err)
	}
	return inputDiagnosticWriter{output: output, pidFile: pidFile}, func() { _ = output.Close() }, restore
}

func TestNativeDebugLifecycleChild(t *testing.T) {
	mode := os.Getenv("MANUSCRIPT_DEBUG_CHILD")
	if mode == "" {
		t.Skip("disposable native test helper")
	}
	target, source, pidFile := os.Getenv("MANUSCRIPT_DEBUG_TARGET"), os.Getenv("MANUSCRIPT_DEBUG_SOURCE"), os.Getenv("MANUSCRIPT_DEBUG_PID")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	watchDone := make(chan struct{})
	defer func() { cancel(); <-watchDone }()
	go func() {
		defer close(watchDone)
		tick := time.NewTicker(10 * time.Millisecond)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-tick.C:
				if fileExists(os.Getenv("MANUSCRIPT_DEBUG_CANCEL")) {
					cancel()
					return
				}
			}
		}
	}()
	var status int
	var err error
	cleanupCalls := 0
	if strings.HasPrefix(mode, "terminal-") {
		if mode == "terminal-embedded-prompt-cancel" {
			restore, err := embeddedTerminalIO("break " + source + ":4\ncontinue\nprint \"LIFECYCLE_READY\"\n")
			if err != nil {
				t.Fatal(err)
			}
			defer func() {
				if err := restore(); err != nil {
					t.Error(err)
				}
			}()
		}
		if mode == "terminal-console-cancel" {
			restore, err := nativeConsole(ctx, cancel)
			if err != nil {
				t.Fatal(err)
			}
			defer func() {
				if err := restore(); err != nil {
					t.Error(err)
				}
			}()
		}
		status, err = Terminal(ctx, target, []string{pidFile})
	} else {
		opts := Options{Out: os.Stdout, JSON: true, Args: []string{pidFile}, Names: Names{Root: filepath.Dir(source), Entities: []Entity{{Name: "marker", File: "main.go", Line: 3, Body: 4, Function: true}}, Sources: map[string]bool{"main.go": true}}}
		opts.Script = strings.NewReader("break marker\ncontinue\n")
		switch mode {
		case "one-shot-invalid":
			// A valid first breakpoint must not rescue an invalid later one.
			opts.Script, opts.Breaks = nil, []string{"marker", "missing"}
		case "script-cancel-input":
			opts.Script = os.Stdin
		case "continue-cancel":
			opts.Script = strings.NewReader("continue\n")
		case "script-read-error":
			opts.Script = io.MultiReader(opts.Script, readerError{io.ErrUnexpectedEOF})
			opts.CancelIO = func() { cleanupCalls++ }
		case "script-full-output-read-error", "script-full-output-oversized":
			var restore func() error
			opts.Out, opts.CancelIO, restore = fullDiagnosticOutput(t, pidFile)
			closeOutput := opts.CancelIO
			opts.CancelIO = func() { cleanupCalls++; closeOutput() }
			defer func() {
				if err := restore(); err != nil {
					t.Error(err)
				}
			}()
			if mode == "script-full-output-read-error" {
				opts.Script = io.MultiReader(opts.Script, readerError{io.ErrUnexpectedEOF})
			} else {
				opts.Script = io.MultiReader(opts.Script, strings.NewReader(strings.Repeat("x", 1024*1024+1)))
			}
		case "script-null-input":
			opts.Script = os.Stdin
		case "script-output-error":
			opts.Out = stopErrorWriter{}
		}
		status, err = Script(ctx, target, opts)
	}
	wantStatus := 0
	var wantErr error
	switch {
	case strings.Contains(mode, "cancel"):
		wantStatus, wantErr = 1, context.Canceled
	case mode == "script-read-error":
		wantStatus, wantErr = 1, io.ErrUnexpectedEOF
	case mode == "script-full-output-read-error":
		wantStatus, wantErr = 1, io.ErrUnexpectedEOF
	case mode == "script-full-output-oversized":
		wantStatus, wantErr = 1, bufio.ErrTooLong
	case mode == "script-output-error":
		wantStatus, wantErr = 1, io.ErrClosedPipe
	case mode == "one-shot-invalid":
		wantStatus = 1
	}
	if status != wantStatus || (wantErr == nil && err != nil) || (wantErr != nil && !errors.Is(err, wantErr)) {
		if unreadSessionOutput(mode) {
			fmt.Fprintf(os.Stderr, "session result %d, %v; want %d, %v\n", status, err, wantStatus, wantErr)
			os.Exit(1)
		}
		t.Fatalf("session result %d, %v; want %d, %v", status, err, wantStatus, wantErr)
	}
	if strings.HasPrefix(mode, "script-full-output-") {
		if ctx.Err() != nil || !errors.Is(err, context.DeadlineExceeded) || cleanupCalls != 1 {
			fmt.Fprintf(os.Stderr, "fatal input did not return with its own diagnostic budget: ctx %v, err %v, cleanup %d\n", ctx.Err(), err, cleanupCalls)
			os.Exit(1)
		}
	}
	if mode == "script-read-error" && cleanupCalls != 1 {
		t.Fatalf("healthy input diagnostic invoked cleanup %d times", cleanupCalls)
	}
	if strings.Contains(mode, "null-") {
		for _, file := range []*os.File{os.Stdin, os.Stdout, os.Stderr} {
			if _, err := file.Write([]byte("borrowed handle still open")); err != nil {
				t.Fatal(err)
			}
			if _, err := file.Read(make([]byte, 1)); !errors.Is(err, io.EOF) {
				t.Fatalf("borrowed null handle no longer reads EOF: %v", err)
			}
		}
	}
	if strings.HasPrefix(mode, "terminal-") {
		path, err := config.GetConfigFilePath(".dbg_history")
		if err != nil {
			t.Fatal(err)
		}
		if err := checkClosedHistory(path); err != nil {
			t.Fatal(err)
		}
		stacks := make([]byte, 1024*1024)
		stacks = stacks[:runtime.Stack(stacks, true)]
		for _, worker := range []string{"terminal.(*Term).Run", "terminal.(*Term).sigintGuard", "liner.(*State).restartPrompt"} {
			if bytes.Contains(stacks, []byte(worker)) {
				t.Fatalf("terminal worker survived return: %s\n%s", worker, stacks)
			}
		}
	}
	if unreadSessionOutput(mode) {
		// The parent deliberately leaves stdout unread. Avoid the test runner's
		// PASS record blocking after the session and its cleanup have returned.
		cancel()
		<-watchDone
		os.Exit(0)
	}
}

func embeddedTerminalIO(commands string) (func() error, error) {
	var files []*os.File
	for range 3 {
		reader, writer, err := os.Pipe()
		if err != nil {
			for _, file := range files {
				_ = file.Close()
			}
			return nil, err
		}
		files = append(files, reader, writer)
	}
	oldInput, oldOutput, oldError := os.Stdin, os.Stdout, os.Stderr
	os.Stdin, os.Stdout, os.Stderr = files[0], files[3], files[5]
	written, outputDone, errorsDone := make(chan struct{}), make(chan struct{}), make(chan struct{})
	go func() { _, _ = io.WriteString(files[1], commands); close(written) }()
	go func() { _, _ = io.Copy(oldOutput, files[2]); close(outputDone) }()
	go func() { _, _ = io.Copy(oldError, files[4]); close(errorsDone) }()
	return func() error {
		os.Stdin, os.Stdout, os.Stderr = oldInput, oldOutput, oldError
		var err error
		// The terminal must leave all borrowed handles open, including the
		// Go-created pipes whose Fd calls during launch can clear O_NONBLOCK.
		for _, file := range files {
			_, statErr := file.Stat()
			err = errors.Join(err, statErr)
		}
		for _, i := range []int{0, 1, 3, 5} {
			err = errors.Join(err, files[i].Close())
		}
		<-written
		<-outputDone
		<-errorsDone
		return errors.Join(err, files[2].Close(), files[4].Close())
	}, nil
}
