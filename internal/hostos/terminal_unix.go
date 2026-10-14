//go:build linux || darwin

package hostos

import (
	"os"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

// ResizeSignal is delivered when the controlling terminal changes size.
var ResizeSignal os.Signal = syscall.SIGWINCH

// TerminalSupported reports whether raw terminal control exists on this host.
const TerminalSupported = true

// IsTerminal reports whether file is open on a terminal device.
func IsTerminal(file *os.File) bool {
	return control(file, func(fd uintptr) error {
		_, err := unix.IoctlGetTermios(int(fd), termiosGet)
		return err
	}) == nil
}

// TerminalSize returns the character columns and rows of the terminal.
func TerminalSize(file *os.File) (columns, rows int, err error) {
	err = control(file, func(fd uintptr) error {
		size, err := unix.IoctlGetWinsize(int(fd), unix.TIOCGWINSZ)
		if err != nil {
			return err
		}
		columns, rows = int(size.Col), int(size.Row)
		return nil
	})
	return
}

// MakeRaw disables line buffering, echo, signal keys, and input translation
// while keeping output post-processing, and returns the function that restores
// the previous settings.
func MakeRaw(file *os.File) (func() error, error) {
	var saved *unix.Termios
	err := control(file, func(fd uintptr) error {
		state, err := unix.IoctlGetTermios(int(fd), termiosGet)
		if err != nil {
			return err
		}
		saved = state
		raw := *state
		raw.Iflag &^= unix.IGNBRK | unix.BRKINT | unix.PARMRK | unix.ISTRIP | unix.INLCR | unix.IGNCR | unix.ICRNL | unix.IXON
		raw.Lflag &^= unix.ECHO | unix.ECHONL | unix.ICANON | unix.ISIG | unix.IEXTEN
		raw.Cflag &^= unix.CSIZE | unix.PARENB
		raw.Cflag |= unix.CS8
		raw.Cc[unix.VMIN] = 1
		raw.Cc[unix.VTIME] = 0
		return unix.IoctlSetTermios(int(fd), termiosSet, &raw)
	})
	if err != nil {
		return nil, err
	}
	return func() error {
		return control(file, func(fd uintptr) error { return unix.IoctlSetTermios(int(fd), termiosSet, saved) })
	}, nil
}

// WaitReadable waits up to timeout for input on file and reports readiness.
func WaitReadable(file *os.File, timeout time.Duration) (bool, error) {
	ready := false
	err := control(file, func(fd uintptr) error {
		fds := []unix.PollFd{{Fd: int32(fd), Events: unix.POLLIN}}
		for {
			n, err := unix.Poll(fds, int(timeout.Milliseconds()))
			if err == unix.EINTR {
				continue
			}
			ready = n > 0
			return err
		}
	})
	return ready, err
}
