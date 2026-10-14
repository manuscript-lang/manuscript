package msruntime

import (
	"errors"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/manuscript-lang/manuscript/internal/hostos"
)

func init() {
	LibraryMethods = append(LibraryMethods,
		LibraryMethod{"Terminal", "capabilities", "TerminalCapabilities", nil},
		LibraryMethod{"Terminal", "size", libraryResult("TerminalSize", "TerminalError"), nil},
		LibraryMethod{"Terminal", "raw_mode", libraryResult("RawTerminal", "TerminalError"), []LibraryParam{{"alternate_screen", "Bool"}}},
		LibraryMethod{"RawTerminal", "close", "Unit", nil},
		LibraryMethod{"RawTerminal", "next_event", libraryResult("Optional[TerminalEvent]", "TerminalError"), []LibraryParam{{"timeout", "Optional[Duration]"}}},
		LibraryMethod{"RawTerminal", "size", libraryResult("TerminalSize", "TerminalError"), nil},
		LibraryMethod{"RawTerminal", "move_cursor", libraryResult("Unit", "TerminalError"), []LibraryParam{{"row", "Int"}, {"column", "Int"}}},
		LibraryMethod{"RawTerminal", "show_cursor", libraryResult("Unit", "TerminalError"), []LibraryParam{{"visible", "Bool"}}},
		LibraryMethod{"RawTerminal", "erase", libraryResult("Unit", "TerminalError"), []LibraryParam{{"region", "EraseRegion"}}},
	)
	libraryAdd("terminal", "terminal", "Terminal", nil, func(ctx *Execution, _ string, _ []Value) Value {
		return hostValue(ctx, "terminal")
	})
}

// terminalActive is the raw terminal currently holding the host terminal, if
// any. Process shutdown restores it even when no scope closed it.
var terminalActive struct {
	sync.Mutex
	current *libraryRawTerminal
}

func terminalRestoreAll() {
	terminalActive.Lock()
	current := terminalActive.current
	terminalActive.Unlock()
	if current != nil {
		current.close()
	}
}

func terminalError(err error) string {
	if errors.Is(err, errors.ErrUnsupported) {
		return "Unsupported"
	}
	return "Failed"
}

type libraryTerminal struct{}

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

func terminalSize(r string, files ...*os.File) Value {
	var err error
	for _, file := range files {
		var columns, rows int
		if columns, rows, err = hostos.TerminalSize(file); err == nil {
			return libraryOK(r, Record{"@std/TerminalSize", map[string]Value{"columns": int64(columns), "rows": int64(rows)}})
		}
	}
	if err != nil && !errors.Is(err, errors.ErrUnsupported) {
		return libraryError(r, "NotTerminal", "")
	}
	return libraryError(r, terminalError(err), "")
}

func (libraryTerminal) Operation(name string) Function {
	return libraryMethod("Terminal", name, func(ctx *Execution, r string, a []Value) Value {
		CheckCancelled(ctx)
		switch name {
		case "capabilities":
			in, out := hostos.IsTerminal(os.Stdin), hostos.IsTerminal(os.Stdout)
			raw := hostos.TerminalSupported && in && out
			return Record{"@std/TerminalCapabilities", map[string]Value{"input_is_terminal": in, "output_is_terminal": out, "error_is_terminal": hostos.IsTerminal(os.Stderr), "raw_mode": raw, "resize_events": raw && hostos.ResizeSignal != nil, "colors": terminalColors(out)}}
		case "size":
			return terminalSize(r, os.Stdout, os.Stdin, os.Stderr)
		}
		return libraryNewRawTerminal(ctx, r, a[0].(bool))
	})
}

type libraryRawTerminal struct {
	mu        sync.Mutex
	closed    bool
	restore   func() error
	alternate bool
	hidden    bool
	done      chan struct{}
	pumped    chan struct{}
	input     chan terminalEvent
	resize    chan os.Signal
	gate      chan struct{}
}

func libraryNewRawTerminal(ctx *Execution, r string, alternate bool) Value {
	if !hostos.TerminalSupported {
		return libraryError(r, "Unsupported", "")
	}
	if !hostos.IsTerminal(os.Stdin) || !hostos.IsTerminal(os.Stdout) {
		return libraryError(r, "NotTerminal", "")
	}
	terminalActive.Lock()
	defer terminalActive.Unlock()
	if terminalActive.current != nil {
		return libraryError(r, "Busy", "")
	}
	restore, err := hostos.MakeRaw(os.Stdin)
	if err != nil {
		return libraryError(r, terminalError(err), err.Error())
	}
	t := &libraryRawTerminal{restore: restore, alternate: alternate, done: make(chan struct{}), pumped: make(chan struct{}), input: make(chan terminalEvent, 256), resize: make(chan os.Signal, 1), gate: make(chan struct{}, 1)}
	if hostos.ResizeSignal != nil {
		signal.Notify(t.resize, hostos.ResizeSignal)
	}
	if alternate {
		t.write("\x1b[?1049h")
	}
	terminalActive.current = t
	go t.pump()
	return libraryOK(r, ViewOf("@std/RawTerminal", t))
}

// pump decodes stdin until the terminal closes. It polls so close can stop it
// without waiting for a keypress, and so a lone Escape resolves quickly.
func (t *libraryRawTerminal) pump() {
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

func (t *libraryRawTerminal) write(text string) error {
	_, err := os.Stdout.WriteString(text)
	return err
}

func (t *libraryRawTerminal) close() {
	t.mu.Lock()
	if t.closed {
		t.mu.Unlock()
		return
	}
	t.closed = true
	close(t.done)
	t.mu.Unlock()
	<-t.pumped
	signal.Stop(t.resize)
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

func (t *libraryRawTerminal) isClosed() bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.closed
}

func (t *libraryRawTerminal) Operation(name string) Function {
	return libraryMethod("RawTerminal", name, func(ctx *Execution, r string, a []Value) Value {
		if name == "close" {
			t.close()
			return Unit{}
		}
		CheckCancelled(ctx)
		if t.isClosed() {
			return libraryError(r, "Closed", "")
		}
		switch name {
		case "size":
			return terminalSize(r, os.Stdout, os.Stdin)
		case "next_event":
			return t.next(ctx, r, time.Duration(a[0].(Duration)))
		}
		var sequence string
		switch name {
		case "move_cursor":
			row, column := a[0].(int64), a[1].(int64)
			if row < 0 || column < 0 || row > 65534 || column > 65534 {
				return libraryError(r, "InvalidInput", "")
			}
			sequence = "\x1b[" + strconv.FormatInt(row+1, 10) + ";" + strconv.FormatInt(column+1, 10) + "H"
		case "show_cursor":
			visible := a[0].(bool)
			t.mu.Lock()
			t.hidden = !visible
			t.mu.Unlock()
			sequence = map[bool]string{true: "\x1b[?25h", false: "\x1b[?25l"}[visible]
		case "erase":
			sequence = map[string]string{"Screen": "\x1b[2J", "Line": "\x1b[2K", "LineEnd": "\x1b[K", "LineStart": "\x1b[1K"}[a[0].(Alternative).Tag]
		}
		if err := t.write(sequence); err != nil {
			return libraryError(r, "Failed", err.Error())
		}
		return libraryOK(r, Unit{})
	})
}

// next waits for one event. A negative timeout waits indefinitely; zero polls.
func (t *libraryRawTerminal) next(ctx *Execution, r string, timeout time.Duration) Value {
	select {
	case t.gate <- struct{}{}:
	case <-t.done:
		return libraryError(r, "Closed", "")
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	}
	defer func() { <-t.gate }()
	var expired <-chan time.Time
	if timeout >= 0 {
		timer := time.NewTimer(timeout)
		defer timer.Stop()
		expired = timer.C
	}
	optionalType := "@std/Optional[@std/TerminalEvent]"
	for {
		select {
		case <-t.done:
			return libraryError(r, "Closed", "")
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		case <-expired:
			return libraryOK(r, Alternative{Type: optionalType, Tag: "none"})
		case <-t.resize:
			size := terminalSize(r, os.Stdout, os.Stdin).(Alternative)
			if size.Tag != "ok" {
				continue
			}
			fields := size.Fields[0].(Record).Fields
			event := terminalEvent{Kind: "resize", Columns: fields["columns"].(int64), Rows: fields["rows"].(int64)}
			return libraryOK(r, Alternative{Type: optionalType, Tag: "some", Fields: []Value{terminalValue(event)}})
		case event, ok := <-t.input:
			if !ok { // input ended: hangup or read failure
				return libraryError(r, "Closed", "")
			}
			return libraryOK(r, Alternative{Type: optionalType, Tag: "some", Fields: []Value{terminalValue(event)}})
		}
	}
}

func terminalValue(event terminalEvent) Value {
	const kind = "@std/TerminalEvent"
	switch event.Kind {
	case "text":
		return Alternative{Type: kind, Tag: "Text", Fields: []Value{event.Text}}
	case "resize":
		return Alternative{Type: kind, Tag: "Resize", Fields: []Value{event.Columns, event.Rows}}
	}
	return Alternative{Type: kind, Tag: "Key", Fields: []Value{event.Text, event.Ctrl, event.Alt, event.Shift}}
}
