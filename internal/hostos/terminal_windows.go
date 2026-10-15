//go:build windows

package hostos

import (
	"os"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// ResizeSupported reports whether WatchResize can observe window changes.
const ResizeSupported = true

// TerminalSupported reports whether raw terminal control exists on this host.
const TerminalSupported = true

var (
	procPeekConsoleInput = kernel32.NewProc("PeekConsoleInputW")
	procReadConsoleInput = kernel32.NewProc("ReadConsoleInputW")
)

const (
	keyEvent    = 0x0001
	resizePoll  = 100 * time.Millisecond
	recordCount = 64
)

// inputRecord mirrors INPUT_RECORD; Event holds a KEY_EVENT_RECORD whose first
// four bytes are the key-down flag.
type inputRecord struct {
	EventType uint16
	_         uint16
	Event     [16]byte
}

// IsTerminal reports whether file is open on a console.
func IsTerminal(file *os.File) bool {
	return control(file, func(fd uintptr) error {
		var mode uint32
		return windows.GetConsoleMode(windows.Handle(fd), &mode)
	}) == nil
}

// TerminalSize returns the character columns and rows of the console window.
func TerminalSize(file *os.File) (columns, rows int, err error) {
	err = control(file, func(fd uintptr) error {
		var info windows.ConsoleScreenBufferInfo
		if err := windows.GetConsoleScreenBufferInfo(windows.Handle(fd), &info); err != nil {
			return err
		}
		columns = int(info.Window.Right-info.Window.Left) + 1
		rows = int(info.Window.Bottom-info.Window.Top) + 1
		return nil
	})
	return
}

// MakeRaw disables line input, echo, and Ctrl-C processing, and asks the
// console to deliver keys as VT escape sequences, which the runtime decoder
// already understands. It returns the function that restores the previous mode.
func MakeRaw(file *os.File) (func() error, error) {
	var saved uint32
	err := control(file, func(fd uintptr) error {
		h := windows.Handle(fd)
		if err := windows.GetConsoleMode(h, &saved); err != nil {
			return err
		}
		raw := saved &^ (windows.ENABLE_ECHO_INPUT | windows.ENABLE_LINE_INPUT | windows.ENABLE_PROCESSED_INPUT | windows.ENABLE_MOUSE_INPUT | windows.ENABLE_WINDOW_INPUT)
		raw |= windows.ENABLE_VIRTUAL_TERMINAL_INPUT
		return windows.SetConsoleMode(h, raw)
	})
	if err != nil {
		return nil, err
	}
	return func() error {
		return control(file, func(fd uintptr) error { return windows.SetConsoleMode(windows.Handle(fd), saved) })
	}, nil
}

// EnableANSI turns on virtual terminal processing so the console interprets
// cursor and erase sequences, and returns the function that restores the mode.
// Consoles without support return an error.
func EnableANSI(file *os.File) (func() error, error) {
	var saved uint32
	err := control(file, func(fd uintptr) error {
		h := windows.Handle(fd)
		if err := windows.GetConsoleMode(h, &saved); err != nil {
			return err
		}
		return windows.SetConsoleMode(h, saved|windows.ENABLE_PROCESSED_OUTPUT|windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING)
	})
	if err != nil {
		return nil, err
	}
	return func() error {
		return control(file, func(fd uintptr) error { return windows.SetConsoleMode(windows.Handle(fd), saved) })
	}, nil
}

// WatchResize polls the window size, since consoles have no resize signal.
func WatchResize(file *os.File, done <-chan struct{}) <-chan struct{} {
	changed := make(chan struct{}, 1)
	lastColumns, lastRows, _ := TerminalSize(file)
	go func() {
		ticker := time.NewTicker(resizePoll)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				columns, rows, err := TerminalSize(file)
				if err != nil || (columns == lastColumns && rows == lastRows) {
					continue
				}
				lastColumns, lastRows = columns, rows
				select {
				case changed <- struct{}{}:
				default:
				}
			case <-done:
				return
			}
		}
	}()
	return changed
}

// WaitReadable waits up to timeout until a key press can be read from the
// console input. Focus, mouse, and other non-key records signal the console
// handle without making a read return, so they are discarded.
func WaitReadable(file *os.File, timeout time.Duration) (bool, error) {
	deadline := time.Now().Add(timeout)
	ready := false
	err := control(file, func(fd uintptr) error {
		h := windows.Handle(fd)
		for {
			remaining := time.Until(deadline)
			if remaining < 0 {
				remaining = 0
			}
			event, err := windows.WaitForSingleObject(h, uint32(remaining.Milliseconds()))
			if err != nil {
				return err
			}
			if event == uint32(windows.WAIT_TIMEOUT) {
				return nil
			}
			var records [recordCount]inputRecord
			var count uint32
			if r, _, err := procPeekConsoleInput.Call(uintptr(h), uintptr(unsafe.Pointer(&records[0])), recordCount, uintptr(unsafe.Pointer(&count))); r == 0 {
				return err
			}
			for _, record := range records[:count] {
				if record.EventType == keyEvent && record.Event[0] != 0 {
					ready = true
					return nil
				}
			}
			if count == 0 {
				continue
			}
			// Only non-key records are pending: drop them and keep waiting.
			if r, _, err := procReadConsoleInput.Call(uintptr(h), uintptr(unsafe.Pointer(&records[0])), uintptr(count), uintptr(unsafe.Pointer(&count))); r == 0 {
				return err
			}
		}
	})
	return ready, err
}
