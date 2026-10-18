package debugger

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"strconv"
	"strings"
	"sync"

	"github.com/go-delve/delve/pkg/proc"
	"github.com/go-delve/delve/service"
	"github.com/go-delve/delve/service/api"
	delve "github.com/go-delve/delve/service/debugger"
	"github.com/go-delve/delve/service/rpc2"
	"github.com/go-delve/delve/service/rpccommon"
)

// Local names a generated Go local with its Manuscript spelling and type.
type Local struct{ Name, Type string }

// Entity is a top-level Manuscript declaration. Function declarations can be
// named in frames and used as breakpoint targets; Body is the first statement line.
type Entity struct {
	Name, File string
	Line, Body int
	Function   bool
}

// Names maps generated Go identifiers and positions back to Manuscript source.
// Files are slash-separated paths relative to Root.
type Names struct {
	Root string
	// Locals maps a function (as frames name it) and the Go name of one of
	// its locals to the source binding.
	Locals   map[string]map[string]Local
	Entities []Entity
	Sources  map[string]bool
	// Lines holds, per file, the lines that begin a statement or declaration.
	Lines map[string]map[int]bool
}

// Options configures one scripted or one-shot debugging session.
type Options struct {
	// Script supplies commands, one per line. A nil Script runs Breaks once.
	Script io.Reader
	// CancelIO interrupts owned command input and event output on cancellation.
	// It is also called after fatal I/O errors. Borrowed streams are never closed
	// automatically; *os.File streams use owned, interruptible duplicates.
	CancelIO func()
	// Breaks are breakpoint specifications installed before a one-shot run.
	Breaks []string
	JSON   bool
	Out    io.Writer
	Args   []string
	Names  Names
}

// Value is a rendered local variable.
type Value struct {
	Name  string `json:"name"`
	Type  string `json:"type,omitempty"`
	Value string `json:"value"`
}

// Frame is a Manuscript stack frame.
type Frame struct {
	Function string `json:"function,omitempty"`
	File     string `json:"file"`
	Line     int    `json:"line"`
}

// Breakpoint describes an installed breakpoint.
type Breakpoint struct {
	ID       int    `json:"id"`
	Function string `json:"function,omitempty"`
	File     string `json:"file"`
	Line     int    `json:"line"`
}

// Event is one result line of a session.
type Event struct {
	Event       string       `json:"event"`
	Command     string       `json:"command,omitempty"`
	Message     string       `json:"message,omitempty"`
	Reason      string       `json:"reason,omitempty"`
	Breakpoint  int          `json:"breakpoint,omitempty"`
	Function    string       `json:"function,omitempty"`
	File        string       `json:"file,omitempty"`
	Line        int          `json:"line,omitempty"`
	Source      string       `json:"source,omitempty"`
	Status      *int         `json:"status,omitempty"`
	Stack       []Frame      `json:"stack,omitempty"`
	Locals      []Value      `json:"locals,omitempty"`
	Breakpoints []Breakpoint `json:"breakpoints,omitempty"`
}

var loadConfig = api.LoadConfig{FollowPointers: true, MaxVariableRecurse: 1, MaxStringLen: 1024, MaxArrayValues: 64, MaxStructFields: -1}

// Script runs commands against a Debug build without a terminal. It returns 0
// when every command succeeded, 1 when a command failed or a one-shot run
// ended without reaching a breakpoint.
func Script(ctx context.Context, executable string, opts Options) (status int, err error) {
	if err := ctx.Err(); err != nil {
		return 1, err
	}
	listener, conn := service.ListenerPipe()
	defer listener.Close()
	defer conn.Close()
	config := delve.Config{Backend: "default", WorkingDir: ".", CheckGoVersion: true, ExecuteKind: delve.ExecutingExistingFile, Stdin: os.DevNull}
	if opts.JSON {
		// Standard output carries only events.
		for _, output := range []*proc.OutputRedirect{&config.Stdout, &config.Stderr} {
			redirect, cleanup, redirectErr := redirectToStderr()
			if redirectErr != nil {
				return 1, redirectErr
			}
			*output = redirect
			defer func() {
				if closeErr := cleanup(); closeErr != nil {
					status, err = 1, errors.Join(err, closeErr)
				}
			}()
		}
	}
	server := rpccommon.NewServer(&service.Config{Listener: listener, ProcessArgs: append([]string{executable}, opts.Args...), APIVersion: 2, Debugger: config})
	if err := ctx.Err(); err != nil {
		return 1, err
	}
	if err := server.Run(); err != nil {
		return 1, err
	}
	restoreIO := func() error { return nil }
	var s *session
	var interrupt func()
	callerCanInterruptOutput := opts.CancelIO != nil
	defer func() {
		stopErr := server.Stop()
		var reportErr error
		if s != nil && s.inputErr != nil {
			// Reporting cannot delay target cleanup. Only a transport whose
			// write can be interrupted gets a best-effort error event.
			reportErr = reportBounded(ctx, s.opts.Out, callerCanInterruptOutput, interrupt, func() error {
				return writeEvent(s.opts.Out, s.opts.JSON, Event{Event: "error", Message: s.inputErr.Error()})
			})
			interrupt()
		}
		if closeErr := errors.Join(stopErr, reportErr, restoreIO()); closeErr != nil {
			status, err = 1, errors.Join(err, closeErr)
		}
	}()
	// Launch can call Fd on inherited files, clearing their shared nonblocking
	// flag. Prepare owned I/O afterward, before any target command can run.
	opts, restoreIO, err = ownScriptIO(opts)
	if err != nil {
		return 1, err
	}
	s = &session{client: rpc2.NewClientFromConn(conn), opts: opts, names: opts.Names, ctx: ctx}
	defer s.client.Disconnect(false)
	var cancelIO sync.Once
	interrupt = func() {
		_ = s.client.Disconnect(false)
		if opts.CancelIO != nil {
			cancelIO.Do(opts.CancelIO)
		}
	}
	return runCancelable(ctx, interrupt, func() (int, error) {
		if opts.Script == nil {
			s.oneShot()
		} else {
			s.script(opts.Script)
		}
		if s.failed || s.ioErr != nil {
			if s.ioErr != nil && s.inputErr == nil {
				interrupt()
			}
			return 1, s.ioErr
		}
		return 0, nil
	})
}

func redirectToStderr() (proc.OutputRedirect, func() error, error) {
	if runtime.GOOS != "windows" {
		return proc.OutputRedirect{Path: "/dev/stderr"}, func() error { return nil }, nil
	}
	// Delve consumes and closes supplied files after launch. Give it a distinct
	// owned handle for each target stream, retaining cleanup for launch failures.
	file, restore, err := duplicateIO(os.Stderr)
	if err != nil {
		return proc.OutputRedirect{}, nil, err
	}
	return proc.OutputRedirect{File: file}, func() error {
		err := file.Close()
		if errors.Is(err, os.ErrClosed) {
			err = nil
		}
		return errors.Join(err, restore())
	}, nil
}

type session struct {
	client   service.Client
	opts     Options
	names    Names
	exited   bool
	failed   bool
	ctx      context.Context
	ioErr    error
	inputErr error
}

func (s *session) oneShot() {
	for _, spec := range s.opts.Breaks {
		if !s.command("break "+spec) || s.failed {
			return
		}
	}
	s.command("continue")
	if s.exited {
		s.fail("program exited before reaching a breakpoint")
	}
}

func (s *session) script(input io.Reader) {
	if !s.ready() {
		return
	}
	lines := bufio.NewScanner(input)
	lines.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for lines.Scan() {
		if !s.ready() {
			return
		}
		line := strings.TrimSpace(lines.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if line == "exit" {
			return
		}
		if !s.command(line) {
			return
		}
	}
	if err := lines.Err(); err != nil {
		s.failed = true
		s.inputErr = fmt.Errorf("read debug commands: %w", err)
		s.ioErr = s.inputErr
	}
}

func (s *session) ready() bool {
	return s.ioErr == nil && (s.ctx == nil || s.ctx.Err() == nil)
}

// command runs one command and reports whether the session can continue.
func (s *session) command(line string) bool {
	if !s.ready() {
		return false
	}
	fields := strings.Fields(line)
	name, rest := fields[0], strings.TrimSpace(strings.TrimPrefix(line, fields[0]))
	if s.exited && name != "breakpoints" {
		s.fail(name + ": the program has exited; use exit to end the session")
		return false
	}
	switch name {
	case "break":
		s.breakAt(rest)
	case "clear":
		s.clear(rest)
	case "breakpoints":
		s.listBreakpoints()
	case "continue":
		// Drain tracepoint results too, joining the public client's producer.
		var state *api.DebuggerState
		for next := range s.client.Continue() {
			state = next
		}
		s.resume(state, nil, "continue")
	case "next", "step", "stepout":
		s.step(name)
	case "stack", "locals":
		s.inspect(name)
	case "print":
		s.print(rest)
	default:
		s.fail("unknown command " + strconv.Quote(name) + "; use break, clear, breakpoints, continue, next, step, stepout, stack, locals, print, or exit")
	}
	return s.ready()
}

func (s *session) fail(message string) {
	s.failed = true
	s.emit(Event{Event: "error", Message: message})
}

func (s *session) breakAt(spec string) {
	location, err := s.names.location(spec)
	if err != nil {
		s.fail(err.Error())
		return
	}
	bp, err := s.client.CreateBreakpointWithExpr(&api.Breakpoint{}, location, nil, false)
	if err != nil {
		s.fail("break " + spec + ": " + err.Error())
		return
	}
	s.emit(Event{Event: "breakpoint", Command: "break", Breakpoint: bp.ID, Function: s.names.function(bp.File, bp.Line), File: s.names.relative(bp.File), Line: bp.Line})
}

func (s *session) clear(arg string) {
	id, err := strconv.Atoi(arg)
	if err != nil {
		s.fail("clear takes a breakpoint id")
		return
	}
	if _, err := s.client.ClearBreakpoint(id); err != nil {
		s.fail(err.Error())
		return
	}
	s.emit(Event{Event: "cleared", Command: "clear", Breakpoint: id})
}

func (s *session) listBreakpoints() {
	list, err := s.client.ListBreakpoints(false)
	if err != nil {
		s.fail(err.Error())
		return
	}
	var breakpoints []Breakpoint
	for _, bp := range list {
		if bp.ID > 0 {
			breakpoints = append(breakpoints, Breakpoint{ID: bp.ID, Function: s.names.function(bp.File, bp.Line), File: s.names.relative(bp.File), Line: bp.Line})
		}
	}
	s.emit(Event{Event: "breakpoints", Command: "breakpoints", Breakpoints: breakpoints})
}

// step runs one stepping command. Generated glue between statements, such as
// source-position bookkeeping, is attributed to lines no statement owns, and a
// step can land in the Go runtime; neither is a position the program's author
// wrote, so stepping continues until a statement line of Manuscript source.
func (s *session) step(kind string) {
	run := map[string]func() (*api.DebuggerState, error){"next": s.client.Next, "step": s.client.Step, "stepout": s.client.StepOut}[kind]
	state, err := run()
	for attempts := 0; attempts < 16 && s.ready() && err == nil && state != nil && !state.Exited; attempts++ {
		if state.CurrentThread != nil && state.CurrentThread.Breakpoint != nil {
			break
		}
		frames, _, stackErr := s.stack(state)
		if stackErr != nil || len(frames) == 0 {
			break
		}
		if !frames[0].user {
			state, err = s.client.StepOut()
			continue
		}
		if s.names.Lines[frames[0].File][frames[0].Line] {
			break
		}
		state, err = run()
	}
	s.resume(state, err, kind)
}

// resume reports the outcome of a command that ran the target.
func (s *session) resume(state *api.DebuggerState, err error, reason string) {
	if state == nil {
		if err == nil {
			err = fmt.Errorf("%s: the debugger returned no state", reason)
		}
		s.fail(err.Error())
		return
	}
	if state.Exited {
		s.exited = true
		status := state.ExitStatus
		s.emit(Event{Event: "exit", Status: &status})
		return
	}
	if err == nil {
		err = state.Err
	}
	if err != nil {
		s.fail(err.Error())
		return
	}
	s.stop(state, reason)
}

func (s *session) stop(state *api.DebuggerState, reason string) {
	frames, gid, err := s.stack(state)
	if err != nil {
		s.fail(err.Error())
		return
	}
	event := Event{Event: "stop", Reason: reason}
	if state.CurrentThread != nil && state.CurrentThread.Breakpoint != nil {
		event.Reason, event.Breakpoint = "breakpoint", state.CurrentThread.Breakpoint.ID
	}
	user := userFrames(frames)
	if len(user) == 0 {
		// Report the native position rather than hide where the program stopped.
		if len(frames) > 0 {
			event.Function, event.File, event.Line = frames[0].native, frames[0].File, frames[0].Line
		}
		s.emit(event)
		return
	}
	top := user[0]
	event.Function, event.File, event.Line = top.Function, top.File, top.Line
	event.Source = s.names.sourceLine(top.File, top.Line)
	event.Stack = toFrames(user)
	event.Locals = s.locals(gid, top.index, top.Function)
	s.emit(event)
}

func (s *session) inspect(command string) {
	state, err := s.client.GetState()
	if err != nil {
		s.fail(err.Error())
		return
	}
	frames, gid, err := s.stack(state)
	if err != nil {
		s.fail(err.Error())
		return
	}
	user := userFrames(frames)
	if len(user) == 0 {
		s.fail(command + ": the program is not stopped in Manuscript source")
		return
	}
	event := Event{Event: command, Command: command}
	if command == "stack" {
		event.Stack = toFrames(user)
	} else {
		event.Locals = s.locals(gid, user[0].index, user[0].Function)
	}
	s.emit(event)
}

func (s *session) print(name string) {
	if name == "" {
		s.fail("print takes a local variable name")
		return
	}
	state, err := s.client.GetState()
	if err != nil {
		s.fail(err.Error())
		return
	}
	frames, gid, err := s.stack(state)
	if err != nil {
		s.fail(err.Error())
		return
	}
	user := userFrames(frames)
	if len(user) == 0 {
		s.fail("print: the program is not stopped in Manuscript source")
		return
	}
	for _, value := range s.locals(gid, user[0].index, user[0].Function) {
		if value.Name == name {
			s.emit(Event{Event: "value", Command: "print", Locals: []Value{value}})
			return
		}
	}
	s.fail("print: no local variable named " + name + " in " + user[0].Function)
}

type frame struct {
	Frame
	index  int
	user   bool
	native string
}

func (s *session) stack(state *api.DebuggerState) ([]frame, int64, error) {
	gid := int64(-1)
	if state.SelectedGoroutine != nil {
		gid = state.SelectedGoroutine.ID
	}
	stack, err := s.client.Stacktrace(gid, 64, 0, nil)
	if err != nil {
		return nil, gid, err
	}
	frames := make([]frame, 0, len(stack))
	for i, f := range stack {
		native := ""
		if f.Function != nil {
			native = f.Function.Name()
		}
		file := s.names.relative(f.File)
		frames = append(frames, frame{Frame: Frame{Function: s.names.function(f.File, f.Line), File: file, Line: f.Line}, index: i, user: s.names.Sources[file], native: native})
	}
	return frames, gid, nil
}

func userFrames(frames []frame) []frame {
	var user []frame
	for _, f := range frames {
		if f.user {
			user = append(user, f)
		}
	}
	return user
}

func toFrames(frames []frame) []Frame {
	out := make([]Frame, len(frames))
	for i, f := range frames {
		out[i] = f.Frame
	}
	return out
}

func (s *session) locals(gid int64, frame int, function string) []Value {
	variables, err := s.client.ListLocalVariables(api.EvalScope{GoroutineID: gid, Frame: frame}, loadConfig)
	if err != nil {
		s.fail(err.Error())
		return nil
	}
	var values []Value
	for i := range variables {
		if local, ok := s.names.Locals[function][variables[i].Name]; ok {
			values = append(values, Value{Name: local.Name, Type: local.Type, Value: render(&variables[i])})
		}
	}
	return values
}

// render shows the value a Manuscript program sees: an interface holding a
// scalar prints as that scalar, and other values use Delve's one-line form.
func render(v *api.Variable) string {
	for v.Kind == reflect.Interface && len(v.Children) == 1 {
		v = &v.Children[0]
	}
	if v.Unreadable != "" {
		return "<unreadable: " + v.Unreadable + ">"
	}
	if v.Kind == reflect.String || v.Value != "" {
		return v.Value
	}
	return v.SinglelineString()
}

func (s *session) emit(e Event) {
	if !s.ready() {
		return
	}
	s.ioErr = writeEvent(s.opts.Out, s.opts.JSON, e)
}

func writeEvent(out io.Writer, structured bool, e Event) error {
	var data []byte
	if structured {
		var err error
		data, err = json.Marshal(e)
		if err != nil {
			return fmt.Errorf("encode debug event: %w", err)
		}
		data = append(data, '\n')
	} else {
		data = []byte(e.text())
	}
	n, err := out.Write(data)
	if err == nil && n != len(data) {
		err = io.ErrShortWrite
	}
	if err != nil {
		return fmt.Errorf("write debug event: %w", err)
	}
	return nil
}

func (e Event) text() string {
	var b strings.Builder
	switch e.Event {
	case "error":
		fmt.Fprintf(&b, "error: %s\n", e.Message)
	case "exit":
		fmt.Fprintf(&b, "exited with status %d\n", *e.Status)
	case "breakpoint":
		fmt.Fprintf(&b, "breakpoint %d at %s\n", e.Breakpoint, position(e.Function, e.File, e.Line))
	case "cleared":
		fmt.Fprintf(&b, "cleared breakpoint %d\n", e.Breakpoint)
	case "breakpoints":
		for _, bp := range e.Breakpoints {
			fmt.Fprintf(&b, "breakpoint %d at %s\n", bp.ID, position(bp.Function, bp.File, bp.Line))
		}
		if len(e.Breakpoints) == 0 {
			b.WriteString("no breakpoints\n")
		}
	case "stop":
		reason := e.Reason
		if e.Breakpoint != 0 {
			reason = fmt.Sprintf("breakpoint %d", e.Breakpoint)
		}
		fmt.Fprintf(&b, "stopped (%s) at %s\n", reason, position(e.Function, e.File, e.Line))
		if e.Source != "" {
			fmt.Fprintf(&b, "  %d: %s\n", e.Line, e.Source)
		}
		writeStack(&b, e.Stack)
		writeLocals(&b, e.Locals)
	case "stack":
		writeStack(&b, e.Stack)
	case "locals", "value":
		writeLocals(&b, e.Locals)
		if len(e.Locals) == 0 {
			b.WriteString("no locals\n")
		}
	}
	return b.String()
}

func position(function, file string, line int) string {
	if function == "" {
		return fmt.Sprintf("%s:%d", file, line)
	}
	return fmt.Sprintf("%s (%s:%d)", function, file, line)
}

func writeStack(b *strings.Builder, stack []Frame) {
	for i, f := range stack {
		fmt.Fprintf(b, "  #%d %s\n", i, position(f.Function, f.File, f.Line))
	}
}

func writeLocals(b *strings.Builder, locals []Value) {
	for _, v := range locals {
		value := v.Value
		if v.Type == "String" {
			value = strconv.Quote(value)
		}
		if v.Type == "" {
			fmt.Fprintf(b, "  %s = %s\n", v.Name, value)
			continue
		}
		fmt.Fprintf(b, "  %s: %s = %s\n", v.Name, v.Type, value)
	}
}

// relative converts a Delve file name into the slash-separated form used by
// Names. Files outside Root keep their cleaned path.
func (n Names) relative(file string) string {
	if n.Root != "" && filepath.IsAbs(file) {
		if rel, err := filepath.Rel(n.Root, file); err == nil && !strings.HasPrefix(rel, "..") {
			return filepath.ToSlash(rel)
		}
	}
	return filepath.ToSlash(filepath.Clean(file))
}

// function names the declaration containing a source line. Lines after the
// last declaration of a file belong to it; an intervening non-function
// declaration ends the previous function.
func (n Names) function(file string, line int) string {
	file = n.relative(file)
	var found *Entity
	for i := range n.Entities {
		e := &n.Entities[i]
		if e.File == file && e.Line <= line && (found == nil || e.Line >= found.Line) {
			found = e
		}
	}
	if found == nil || !found.Function {
		return ""
	}
	return found.Name
}

func (n Names) sourceLine(file string, line int) string {
	data, err := os.ReadFile(filepath.Join(n.Root, filepath.FromSlash(file)))
	if err != nil {
		return ""
	}
	if line < 1 {
		return ""
	}
	for i := 1; i < line; i++ {
		end := bytes.IndexByte(data, '\n')
		if end < 0 {
			return ""
		}
		data = data[end+1:]
	}
	if end := bytes.IndexByte(data, '\n'); end >= 0 {
		data = data[:end]
	}
	// Copy only this line; a stop event must not retain the entire source file.
	return string(bytes.TrimRight(data, "\r"))
}

// location turns file:line or a function name into a Delve location expression.
func (n Names) location(spec string) (string, error) {
	if colon := strings.LastIndexByte(spec, ':'); colon > 0 {
		if line, err := strconv.Atoi(spec[colon+1:]); err == nil && line > 0 {
			file := spec[:colon]
			if !filepath.IsAbs(file) && n.Root != "" {
				file = filepath.Join(n.Root, filepath.FromSlash(file))
			}
			return file + ":" + strconv.Itoa(line), nil
		}
	}
	var matches []Entity
	for _, e := range n.Entities {
		if e.Function && e.Name == spec {
			matches = append(matches, e)
		}
	}
	switch len(matches) {
	case 0:
		return "", fmt.Errorf("break %q: use file:line or the name of a function declared in Manuscript source", spec)
	case 1:
		return filepath.Join(n.Root, filepath.FromSlash(matches[0].File)) + ":" + strconv.Itoa(matches[0].Body), nil
	}
	var where []string
	for _, e := range matches {
		where = append(where, e.File+":"+strconv.Itoa(e.Line))
	}
	return "", fmt.Errorf("break %q is ambiguous (%s); use file:line", spec, strings.Join(where, ", "))
}
