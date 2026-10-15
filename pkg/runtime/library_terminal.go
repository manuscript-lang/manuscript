package msruntime

import (
	"errors"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/manuscript-lang/manuscript/internal/hostos"
)

// terminalActive is the raw terminal currently holding the host terminal, if
// any. Process shutdown restores it even when no scope closed it.
var terminalActive struct {
	sync.Mutex
	current *osRawTerminal
}

func terminalRestoreAll() {
	terminalActive.Lock()
	current := terminalActive.current
	terminalActive.Unlock()
	if current != nil {
		current.close()
	}
}

func terminalFail[T any](err error, message string) Result[T, TerminalError] {
	if errors.Is(err, errors.ErrUnsupported) {
		return Fail[T, TerminalError](TerminalError_Unsupported{})
	}
	return Fail[T, TerminalError](TerminalError_Failed{Message: message})
}

// osTerminal is the host's terminal service.
type osTerminal struct{}

var _ Terminal = osTerminal{}

func terminalColors(output bool) int64 {
	if !output || os.Getenv("NO_COLOR") != "" {
		return 0
	}
	term := os.Getenv("TERM")
	colorTerm := os.Getenv("COLORTERM")
	switch {
	case term == "dumb":
		return 0
	case colorTerm == "truecolor" || colorTerm == "24bit":
		return 16777216
	case strings.Contains(term, "256color"):
		return 256
	}
	return 16
}

func terminalSize(files ...*os.File) Result[*TerminalSize, TerminalError] {
	var err error
	for _, file := range files {
		var columns, rows int
		if columns, rows, err = hostos.TerminalSize(file); err == nil {
			return Ok[*TerminalSize, TerminalError](&TerminalSize{Columns: int64(columns), Rows: int64(rows)})
		}
	}
	if err != nil && !errors.Is(err, errors.ErrUnsupported) {
		return Fail[*TerminalSize, TerminalError](TerminalError_NotTerminal{})
	}
	return terminalFail[*TerminalSize](err, "")
}

func (osTerminal) Capabilities(ctx *Execution) *TerminalCapabilities {
	CheckCancelled(ctx)
	in, out := hostos.IsTerminal(os.Stdin), hostos.IsTerminal(os.Stdout)
	raw := hostos.TerminalSupported && in && out
	return &TerminalCapabilities{InputIsTerminal: in, OutputIsTerminal: out, ErrorIsTerminal: hostos.IsTerminal(os.Stderr), RawMode: raw, ResizeEvents: raw && hostos.ResizeSupported, Colors: terminalColors(out)}
}

func (osTerminal) Size(ctx *Execution) Result[*TerminalSize, TerminalError] {
	CheckCancelled(ctx)
	return terminalSize(os.Stdout, os.Stdin, os.Stderr)
}

func (osTerminal) RawMode(ctx *Execution, alternate bool) Result[RawTerminal, TerminalError] {
	CheckCancelled(ctx)
	return newRawTerminal(alternate)
}

type osRawTerminal struct {
	mu        sync.Mutex
	closed    bool
	restore   func() error
	alternate bool
	hidden    bool
	done      chan struct{}
	pumped    chan struct{}
	input     chan terminalEvent
	resize    <-chan struct{}
	gate      chan struct{}
}

func newRawTerminal(alternate bool) Result[RawTerminal, TerminalError] {
	if !hostos.TerminalSupported {
		return Fail[RawTerminal, TerminalError](TerminalError_Unsupported{})
	}
	if !hostos.IsTerminal(os.Stdin) || !hostos.IsTerminal(os.Stdout) {
		return Fail[RawTerminal, TerminalError](TerminalError_NotTerminal{})
	}
	terminalActive.Lock()
	defer terminalActive.Unlock()
	if terminalActive.current != nil {
		return Fail[RawTerminal, TerminalError](TerminalError_Busy{})
	}
	restoreInput, err := hostos.MakeRaw(os.Stdin)
	if err != nil {
		return terminalFail[RawTerminal](err, err.Error())
	}
	restoreOutput, err := hostos.EnableANSI(os.Stdout)
	if err != nil {
		restoreInput()
		return terminalFail[RawTerminal](err, err.Error())
	}
	restore := func() error { return errors.Join(restoreOutput(), restoreInput()) }
	t := &osRawTerminal{restore: restore, alternate: alternate, done: make(chan struct{}), pumped: make(chan struct{}), input: make(chan terminalEvent, 256), gate: make(chan struct{}, 1)}
	if hostos.ResizeSupported {
		t.resize = hostos.WatchResize(os.Stdout, t.done)
	}
	if alternate {
		t.write("\x1b[?1049h")
	}
	terminalActive.current = t
	go t.pump()
	return Ok[RawTerminal, TerminalError](t)
}

// pump decodes stdin until the terminal closes. It polls so close can stop it
// without waiting for a keypress, and so a lone Escape resolves quickly.
func (t *osRawTerminal) pump() {
	defer close(t.pumped)
	defer close(t.input)
	var decoder terminalDecoder
	buffer := make([]byte, 4096)
	deliver := func(events []terminalEvent) bool {
		for _, event := range events {
			select {
			case t.input <- event:
			case <-t.done:
				return false
			}
		}
		return true
	}
	for {
		select {
		case <-t.done:
			return
		default:
		}
		wait := 100 * time.Millisecond
		if decoder.Pending() {
			wait = 40 * time.Millisecond
		}
		ready, err := hostos.WaitReadable(os.Stdin, wait)
		if err == nil && !ready {
			if decoder.Pending() && !deliver(decoder.Flush()) {
				return
			}
			continue
		}
		var n int
		if err == nil {
			n, err = os.Stdin.Read(buffer)
		}
		if n > 0 && !deliver(decoder.Feed(buffer[:n])) {
			return
		}
		if err != nil {
			return
		}
	}
}

func (t *osRawTerminal) write(text string) error {
	_, err := os.Stdout.WriteString(text)
	return err
}

func (t *osRawTerminal) close() {
	t.mu.Lock()
	if t.closed {
		t.mu.Unlock()
		return
	}
	t.closed = true
	close(t.done)
	t.mu.Unlock()
	<-t.pumped
	if t.hidden {
		t.write("\x1b[?25h")
	}
	if t.alternate {
		t.write("\x1b[?1049l")
	}
	t.restore()
	terminalActive.Lock()
	if terminalActive.current == t {
		terminalActive.current = nil
	}
	terminalActive.Unlock()
}

func (t *osRawTerminal) isClosed() bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.closed
}

var _ RawTerminal = (*osRawTerminal)(nil)

func (t *osRawTerminal) Close(*Execution) Unit {
	t.close()
	return Unit{}
}

func rawFail[T any](err TerminalError) Result[T, TerminalError] { return Fail[T, TerminalError](err) }

func (t *osRawTerminal) Size(ctx *Execution) Result[*TerminalSize, TerminalError] {
	CheckCancelled(ctx)
	if t.isClosed() {
		return rawFail[*TerminalSize](TerminalError_Closed{})
	}
	return terminalSize(os.Stdout, os.Stdin)
}

func (t *osRawTerminal) command(ctx *Execution, sequence string) Result[Unit, TerminalError] {
	if err := t.write(sequence); err != nil {
		return rawFail[Unit](TerminalError_Failed{Message: err.Error()})
	}
	return Ok[Unit, TerminalError](Unit{})
}

func (t *osRawTerminal) MoveCursor(ctx *Execution, row, column int64) Result[Unit, TerminalError] {
	CheckCancelled(ctx)
	if t.isClosed() {
		return rawFail[Unit](TerminalError_Closed{})
	}
	if row < 0 || column < 0 || row > 65534 || column > 65534 {
		return rawFail[Unit](TerminalError_InvalidInput{})
	}
	return t.command(ctx, "\x1b["+strconv.FormatInt(row+1, 10)+";"+strconv.FormatInt(column+1, 10)+"H")
}

func (t *osRawTerminal) ShowCursor(ctx *Execution, visible bool) Result[Unit, TerminalError] {
	CheckCancelled(ctx)
	if t.isClosed() {
		return rawFail[Unit](TerminalError_Closed{})
	}
	t.mu.Lock()
	t.hidden = !visible
	t.mu.Unlock()
	if visible {
		return t.command(ctx, "\x1b[?25h")
	}
	return t.command(ctx, "\x1b[?25l")
}

func (t *osRawTerminal) Erase(ctx *Execution, region EraseRegion) Result[Unit, TerminalError] {
	CheckCancelled(ctx)
	if t.isClosed() {
		return rawFail[Unit](TerminalError_Closed{})
	}
	switch region.(type) {
	case EraseRegion_Screen:
		return t.command(ctx, "\x1b[2J")
	case EraseRegion_Line:
		return t.command(ctx, "\x1b[2K")
	case EraseRegion_LineEnd:
		return t.command(ctx, "\x1b[K")
	}
	return t.command(ctx, "\x1b[1K")
}

// NextEvent waits for one event. An absent timeout waits indefinitely; zero
// polls.
func (t *osRawTerminal) NextEvent(ctx *Execution, timeout Option[Duration]) Result[Option[TerminalEvent], TerminalError] {
	CheckCancelled(ctx)
	if t.isClosed() {
		return rawFail[Option[TerminalEvent]](TerminalError_Closed{})
	}
	return t.next(ctx, timeout)
}

func (t *osRawTerminal) next(ctx *Execution, timeout Option[Duration]) Result[Option[TerminalEvent], TerminalError] {
	closed := rawFail[Option[TerminalEvent]](TerminalError_Closed{})
	some := func(event TerminalEvent) Result[Option[TerminalEvent], TerminalError] {
		return Ok[Option[TerminalEvent], TerminalError](Some(event))
	}
	select {
	case t.gate <- struct{}{}:
	case <-t.done:
		return closed
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	}
	defer func() { <-t.gate }()
	var expired <-chan time.Time
	if timeout.Some {
		timer := time.NewTimer(max(time.Duration(timeout.Val), 0))
		defer timer.Stop()
		expired = timer.C
	}
	for {
		select {
		case <-t.done:
			return closed
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		case <-expired:
			return Ok[Option[TerminalEvent], TerminalError](None[TerminalEvent]())
		case <-t.resize:
			size := terminalSize(os.Stdout, os.Stdin)
			if size.Failed {
				continue
			}
			return some(TerminalEvent_Resize{Columns: size.Val.Columns, Rows: size.Val.Rows})
		case event, ok := <-t.input:
			if !ok { // input ended: hangup or read failure
				return closed
			}
			return some(terminalValue(event))
		}
	}
}

func terminalValue(event terminalEvent) TerminalEvent {
	switch event.Kind {
	case "text":
		return TerminalEvent_Text{Text: event.Text}
	case "resize":
		return TerminalEvent_Resize{Columns: event.Columns, Rows: event.Rows}
	}
	return TerminalEvent_Key{Name: event.Text, Ctrl: event.Ctrl, Alt: event.Alt, Shift: event.Shift}
}

// Errors_Message_TerminalError is the Error message of TerminalError.
func Errors_Message_TerminalError(_ *Execution, cause TerminalError) string {
	switch cause := cause.(type) {
	case TerminalError_InvalidInput:
		return "terminal: invalid input"
	case TerminalError_NotTerminal:
		return "terminal: standard stream is not a terminal"
	case TerminalError_Unsupported:
		return "terminal: operation not supported"
	case TerminalError_Busy:
		return "terminal: terminal is already in use"
	case TerminalError_Closed:
		return "terminal: resource is closed"
	case TerminalError_Failed:
		return cause.Message
	}
	return "terminal: operation failed"
}
