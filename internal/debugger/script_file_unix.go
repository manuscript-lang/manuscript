//go:build !windows

package debugger

import (
	"golang.org/x/sys/unix"
	"os"
	"syscall"
	"time"
)

// Inherited stdio is normally a blocking NewFile. Register an owned duplicate
// with Go's poller so Close/deadlines can interrupt a protocol read/write.
func scriptFile(file *os.File) (*os.File, func(), error) {
	raw, err := file.SyscallConn()
	if err != nil {
		return nil, nil, err
	}
	fd, flags := -1, 0
	var setupErr error
	err = raw.Control(func(original uintptr) {
		flags, setupErr = unix.FcntlInt(original, unix.F_GETFL, 0)
		if setupErr == nil {
			fd, setupErr = syscall.Dup(int(original))
		}
	})
	if err != nil {
		return nil, nil, err
	}
	if setupErr != nil {
		return nil, nil, setupErr
	}
	syscall.CloseOnExec(fd)
	if err := syscall.SetNonblock(fd, true); err != nil {
		_ = syscall.Close(fd)
		return nil, nil, err
	}
	restore := func() {
		_ = raw.Control(func(original uintptr) { _, _ = unix.FcntlInt(original, unix.F_SETFL, flags) })
	}
	return os.NewFile(uintptr(fd), file.Name()), restore, nil
}

func interruptScriptOutput(file *os.File) { _ = file.SetWriteDeadline(time.Now()) }
