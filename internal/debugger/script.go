package debugger

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/go-delve/delve/pkg/proc"
	"github.com/go-delve/delve/service"
	"github.com/go-delve/delve/service/api"
	delve "github.com/go-delve/delve/service/debugger"
	"github.com/go-delve/delve/service/rpc2"
	"github.com/go-delve/delve/service/rpccommon"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

// Every record has a protocol version and sequence. Command records acknowledge
// input before execution; a result is emitted only for a completed command.
type scriptEvent struct {
	Version        int           `json:"version"`
	Seq            int           `json:"seq"`
	Event          string        `json:"event"`
	CommandID      int           `json:"command_id,omitempty"` // physical input line
	Command        string        `json:"command,omitempty"`
	Result         any           `json:"result,omitempty"`
	Code           string        `json:"code,omitempty"`
	Message        string        `json:"message,omitempty"`
	Reason         string        `json:"reason,omitempty"`
	Location       *sourceFrame  `json:"location,omitempty"`
	Locals         []sourceValue `json:"locals,omitempty"`
	Stack          []sourceFrame `json:"stack,omitempty"`
	StackTruncated bool          `json:"stack_truncated,omitempty"`
	Stream         string        `json:"stream,omitempty"`
	Text           string        `json:"text,omitempty"`
	Bytes          string        `json:"bytes_base64,omitempty"`
	Status         *int          `json:"status,omitempty"`
	TargetStatus   *int          `json:"target_status"`
	PID            int           `json:"pid,omitempty"`
}

type eventWriter struct {
	output io.Writer
	seq    int
	broken bool
}

func (w *eventWriter) emit(event scriptEvent) error {
	if w.broken {
		return io.ErrShortWrite
	}
	event.Version, event.Seq = 1, w.seq+1
	data, err := json.Marshal(event)
	if err != nil {
		return err
	}
	data = append(data, '\n')
	n, err := w.output.Write(data)
	if n == len(data) {
		w.seq++
	} else {
		// A partial frame cannot safely be followed by a different record.
		w.broken = n > 0
		if err == nil {
			err = io.ErrShortWrite
		}
	}
	return err
}

// ScriptFailure covers errors before a debug target exists (build, source,
// metadata or command-file setup). Usage errors remain ordinary CLI diagnostics.
func ScriptFailure(output io.Writer, code string, err error) int {
	w := eventWriter{output: output}
	_ = w.emit(scriptEvent{Event: "error", Code: code, Message: err.Error()})
	status := 1
	_ = w.emit(scriptEvent{Event: "exit", Reason: "error", Status: &status})
	return status
}

type scriptLine struct {
	id   int
	text string
	err  error
}

// Input is owned by Script, so cancellation can close and join a blocked read.
// An unbuffered stream provides one-command lookahead without reading all input
// into memory. EOF is observed only after preceding commands have been consumed.
func scanScript(ctx context.Context, input io.Reader, lines chan<- scriptLine) {
	defer close(lines)
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 4096), 64*1024)
	id := 0
	for scanner.Scan() {
		id++
		if text := strings.TrimSpace(scanner.Text()); text == "" || strings.HasPrefix(text, "#") {
			continue
		}
		line := scriptLine{id: id, text: scanner.Text()}
		select {
		case lines <- line:
		case <-ctx.Done():
			return
		}
	}
	if err := scanner.Err(); err != nil {
		select {
		case lines <- scriptLine{id: id + 1, err: err}:
		case <-ctx.Done():
		}
	}
}

// Capture files work with native Delve and Apple's debugserver. Deliver output
// at checkpoints, reading a fixed byte-count snapshot in bounded chunks. Bytes
// that cannot safely be represented as UTF-8 are losslessly base64 encoded.
type scriptOutput struct {
	stream string
	file   *os.File
}

func (o scriptOutput) drain(w *eventWriter) error {
	info, err := o.file.Stat()
	if err != nil {
		return err
	}
	at, err := o.file.Seek(0, io.SeekCurrent)
	if err != nil {
		return err
	}
	remaining := info.Size() - at
	buffer := make([]byte, 8192)
	for remaining > 0 {
		n, err := o.file.Read(buffer[:min(int64(len(buffer)), remaining)])
		if err != nil {
			return err
		}
		if n == 0 {
			return io.ErrNoProgress
		}
		remaining -= int64(n)
		event := scriptEvent{Event: "output", Stream: o.stream}
		if utf8.Valid(buffer[:n]) {
			event.Text = string(buffer[:n])
		} else {
			event.Bytes = base64.StdEncoding.EncodeToString(buffer[:n])
		}
		if err := w.emit(event); err != nil {
			return err
		}
	}
	return nil
}

type commandResult struct {
	result any
	state  *api.DebuggerState
	err    error
}

// Script runs a bounded command language over embedded Delve's public RPC
// client. It takes ownership of input, kills/reaps its target on every return,
// and preserves the interactive Terminal path as a separate entry point.
func Script(ctx context.Context, executable string, args []string, inspection tooling.Inspection, input io.ReadCloser, output io.Writer, rawStack bool) (returnStatus int) {
	defer input.Close()
	if file, ok := input.(*os.File); ok {
		if err := validateScriptInput(file); err != nil {
			return ScriptFailure(output, "input", err)
		}
	}
	if err := scriptProcessSupported(); err != nil {
		return ScriptFailure(output, "launch", err)
	}
	if input == os.Stdin {
		file, restore, err := scriptFile(os.Stdin)
		if err != nil {
			return ScriptFailure(output, "input", err)
		}
		defer restore()
		input = file
	}
	defer input.Close()
	if output == os.Stdout {
		file, restore, err := scriptFile(os.Stdout)
		if err != nil {
			return ScriptFailure(output, "output", err)
		}
		defer restore()
		defer file.Close()
		output = file
	}
	// Unblock an unread protocol pipe on cancellation. Give final records a
	// bounded chance to reach a responsive consumer during cleanup.
	writerDone := make(chan struct{})
	writerJoined := make(chan struct{})
	go func() {
		defer close(writerJoined)
		select {
		case <-ctx.Done():
			if file, ok := output.(*os.File); ok {
				interruptScriptOutput(file)
			}
		case <-writerDone:
		}
	}()
	stopWriter := sync.OnceFunc(func() { close(writerDone); <-writerJoined })
	defer stopWriter()
	if file, ok := output.(*os.File); ok {
		defer file.SetWriteDeadline(time.Time{})
	}
	v, err := loadSourceView(executable, inspection)
	if err != nil {
		return ScriptFailure(output, "metadata", err)
	}
	directory, err := os.MkdirTemp("", "manuscript-debug-output-")
	if err != nil {
		return ScriptFailure(output, "output", err)
	}
	defer os.RemoveAll(directory)
	outputs := []scriptOutput{}
	defer func() {
		for _, o := range outputs {
			_ = o.file.Close()
		}
	}()
	for _, stream := range []string{"stdout", "stderr"} {
		file, err := os.OpenFile(filepath.Join(directory, stream), os.O_CREATE|os.O_RDONLY, 0600)
		if err != nil {
			return ScriptFailure(output, "output", err)
		}
		outputs = append(outputs, scriptOutput{stream: stream, file: file})
	}
	listener, conn := service.ListenerPipe()
	defer listener.Close()
	defer conn.Close()
	server := rpccommon.NewServer(&service.Config{
		Listener: listener, ProcessArgs: append([]string{executable}, args...), APIVersion: 2,
		Debugger: delve.Config{Backend: "default", WorkingDir: ".", CheckGoVersion: true, ExecuteKind: delve.ExecutingExistingFile, Scripted: runtime.GOOS == "darwin", ScriptedContext: ctx,
			Stdin: os.DevNull, Stdout: proc.OutputRedirect{Path: outputs[0].file.Name()}, Stderr: proc.OutputRedirect{Path: outputs[1].file.Name()}},
	})
	if err := ctx.Err(); err != nil {
		return ScriptFailure(output, "cancelled", err)
	}
	if err := server.Run(); err != nil {
		if ctx.Err() != nil {
			return ScriptFailure(output, "cancelled", err)
		}
		return ScriptFailure(output, "launch", err)
	}
	client := rpc2.NewClientFromConn(conn)
	pid := client.ProcessPid()
	// Bind an explicit identity while stopped. Unsupported kernels/platforms
	// must fail closed, rather than rely on os.FindProcess's PID-only fallback.
	target, err := bindScriptProcess(server, pid)
	if err != nil {
		err = errors.Join(err, server.Stop())
		return ScriptFailure(output, "launch", err)
	}
	defer target.Close()
	session := scriptSession{client: client, source: v, rawStack: rawStack}
	w := eventWriter{output: output}
	status, reason := 0, "eof"
	var targetStatus *int
	var active <-chan commandResult
	activeResumes := false
	var line scriptLine
	readerCtx, cancel := context.WithCancel(ctx)
	lines := make(chan scriptLine)
	readerDone := make(chan struct{})
	go func() { defer close(readerDone); scanScript(readerCtx, input, lines) }()
	drain := func() error {
		for _, o := range outputs {
			if err := o.drain(&w); err != nil {
				return err
			}
		}
		return nil
	}
	fail := func(code string, err error) {
		if ctx.Err() != nil {
			code, err = "cancelled", ctx.Err()
			stopWriter()
			if file, ok := output.(*os.File); ok {
				_ = file.SetWriteDeadline(time.Now().Add(time.Second))
			}
		}
		status, reason = 1, "error"
		if code == "cancelled" {
			reason = "cancelled"
		}
		_ = w.emit(scriptEvent{Event: "error", CommandID: line.id, Code: code, Message: err.Error()})
	}
	// Join before stopping the service. Concurrent Delve Halt/Continue races
	// inside the pinned backend; interrupt only this session's launched process
	// through its retained OS identity or debugserver connection. A stopped
	// target is killed by server.Stop, after the command joins.
	defer func() {
		cancel()
		stopWriter()
		if file, ok := output.(*os.File); ok {
			_ = file.SetWriteDeadline(time.Now().Add(time.Second))
		}
		if active != nil {
			if activeResumes || scriptInterruptsInspection() {
				err := target.Interrupt()
				if err != nil && !errors.Is(err, os.ErrProcessDone) {
					fail("cleanup", err)
				}
			}
			<-active
			active = nil
		}
		if err := server.Stop(); err != nil && targetStatus == nil {
			fail("cleanup", err)
		}
		// The native backend can observe a SIGKILL on another target thread and
		// leave the process leader waitable. Reap an owned child after Delve has
		// joined/detached; already-reaped targets (or LLDB-owned children) simply
		// return a wait error.
		if err := target.Reap(); err != nil {
			fail("cleanup", err)
		}
		// Closing a reader can itself block. The target must already be gone.
		_ = input.Close()
		<-readerDone
		if err := drain(); err != nil {
			fail("output", err)
		}
		_ = w.emit(scriptEvent{Event: "exit", Reason: reason, Status: &status, TargetStatus: targetStatus})
		returnStatus = status
	}()
	state, err := client.GetState()
	if err != nil {
		fail("state", err)
		return 1
	}
	entry := scriptEvent{Event: "stop", Reason: "entry", PID: pid}
	if state.CurrentThread != nil {
		t := state.CurrentThread
		f := v.frame(api.Location{File: t.File, Line: t.Line, Function: t.Function}, 0)
		entry.Location = &f
	}
	if err := w.emit(entry); err != nil {
		fail("output", err)
		return 1
	}
	var pending *scriptLine
	for {
		if pending != nil {
			line, pending = *pending, nil
		} else {
			select {
			case next, ok := <-lines:
				if !ok {
					return status
				}
				line = next
			case <-ctx.Done():
				fail("cancelled", ctx.Err())
				return 1
			}
		}
		if line.err != nil {
			fail("input", line.err)
			return 1
		}
		command, err := parseScriptCommand(line.text)
		if err != nil {
			fail("command", err)
			return 1
		}
		if command.name == "" {
			continue
		}
		if err := w.emit(scriptEvent{Event: "command", CommandID: line.id, Command: line.text}); err != nil {
			fail("output", err)
			return 1
		}
		if command.name == "exit" {
			reason = "exit"
			return status
		}
		done := make(chan commandResult, 1)
		active = done
		activeResumes = command.resumes()
		go func() { done <- session.execute(command) }()
		eof := false
		// Keep at most one later line; if present, an EOF after it cannot
		// interrupt this operation. If absent, EOF cancels the final operation.
		var result commandResult
		completed := false
		for !completed && !eof {
			select {
			case result = <-done:
				completed = true
				active = nil
			case next, ok := <-lines:
				if !ok {
					eof = true
				} else if next.err != nil {
					line = next
					fail("input", next.err)
					return 1
				} else {
					pending = &next
				}
			case <-ctx.Done():
				fail("cancelled", ctx.Err())
				return 1
			}
			if pending != nil && !completed {
				select {
				case result = <-done:
					completed = true
					active = nil
				case <-ctx.Done():
					fail("cancelled", ctx.Err())
					return 1
				}
			}
		}
		if eof && !completed {
			if !command.resumes() {
				select {
				case result = <-done:
					completed = true
					active = nil
				case <-ctx.Done():
					fail("cancelled", ctx.Err())
					return 1
				}
			}
			select {
			case result = <-done:
				completed = true
				active = nil
			default:
			}
			if !completed {
				reason = "eof"
				return status
			}
		}
		if err := drain(); err != nil {
			fail("output", err)
			return 1
		}
		if result.state != nil && result.state.Exited {
			exit := result.state.ExitStatus
			targetStatus = &exit
			status, reason = exit, "exited"
			if err := w.emit(scriptEvent{Event: "result", CommandID: line.id, Result: map[string]bool{"exited": true}}); err != nil {
				fail("output", err)
				return 1
			}
			return status
		}
		if result.err != nil {
			fail("debugger", result.err)
			return 1
		}
		if err := w.emit(scriptEvent{Event: "result", CommandID: line.id, Result: result.result}); err != nil {
			fail("output", err)
			return 1
		}
		if result.state != nil {
			stop, err := session.stop(result.state)
			if err != nil {
				fail("inspection", err)
				return 1
			}
			stop.CommandID = line.id
			if err := w.emit(stop); err != nil {
				fail("output", err)
				return 1
			}
		}
		if eof {
			return status
		}
	}
}
