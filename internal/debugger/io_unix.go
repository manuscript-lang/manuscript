//go:build !windows

package debugger

import (
	"errors"
	"fmt"
	"os"
	"time"

	"golang.org/x/sys/unix"
)

func cancellationThread() (cancel, finish func() error, err error) {
	return func() error { return nil }, func() error { return nil }, nil
}

func duplicateIO(original *os.File) (*os.File, func() error, error) {
	raw, err := original.SyscallConn()
	if err != nil {
		return nil, nil, err
	}
	fd, flags := -1, 0
	var duplicateErr error
	err = raw.Control(func(originalFD uintptr) {
		flags, duplicateErr = unix.FcntlInt(originalFD, unix.F_GETFL, 0)
		if duplicateErr != nil {
			return
		}
		fd, duplicateErr = unix.FcntlInt(originalFD, unix.F_DUPFD_CLOEXEC, 0)
		if duplicateErr == nil {
			duplicateErr = unix.SetNonblock(fd, true)
		}
	})
	undo := func() error {
		var flagErr error
		if err := raw.Control(func(originalFD uintptr) { _, flagErr = unix.FcntlInt(originalFD, unix.F_SETFL, flags) }); err != nil {
			return err
		}
		return flagErr
	}
	if err != nil || duplicateErr != nil {
		err = errors.Join(err, duplicateErr)
		if fd >= 0 {
			err = errors.Join(err, unix.Close(fd), undo())
		}
		return nil, nil, err
	}
	// Set O_NONBLOCK before NewFile. In particular Delve's paging writer can
	// call Fd; Go preserves a preexisting flag, keeping concurrent Close useful.
	file := os.NewFile(uintptr(fd), original.Name())
	info, err := file.Stat()
	if err == nil && !info.Mode().IsRegular() {
		var nullInfo os.FileInfo
		nullInfo, err = os.Stat(os.DevNull)
		if err == nil && !os.SameFile(info, nullInfo) {
			err = file.SetDeadline(time.Time{})
		}
	}
	if err != nil {
		return nil, nil, fmt.Errorf("prepare cancellable %s: %w", original.Name(), errors.Join(err, file.Close(), undo()))
	}
	return file, undo, nil
}

func boundedFileWrite(file *os.File) bool {
	return file.SetWriteDeadline(time.Time{}) == nil
}

func replaceConsoleStdio(_, _, _ *os.File) (func() error, error) {
	return func() error { return nil }, nil
}
