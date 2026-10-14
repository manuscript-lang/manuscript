package debugger

import (
	"errors"
	"fmt"
	"os"

	"golang.org/x/sys/unix"
)

type scriptPIDFD struct{ fd int }

func scriptProcessSupported() error { return nil }

func openScriptProcess(pid int) (scriptProcess, error) { return openScriptPIDFD(pid, unix.PidfdOpen) }

func openScriptPIDFD(pid int, open func(int, int) (int, error)) (scriptProcess, error) {
	fd, err := open(pid, 0)
	if err != nil {
		return nil, fmt.Errorf("script debugging requires an identity-bound Linux pidfd (no PID-only fallback): %w", err)
	}
	process := &scriptPIDFD{fd: fd}
	// Verify the required signal/wait APIs while Delve still owns a stopped
	// target. Restricted or older kernels must not fall back to kill(pid).
	if err := unix.PidfdSendSignal(fd, 0, nil, 0); err == nil {
		var info unix.Siginfo
		err = unix.Waitid(unix.P_PIDFD, fd, &info, unix.WEXITED|unix.WNOHANG|unix.WNOWAIT, nil)
		if err == nil {
			return process, nil
		}
		_ = process.Close()
		return nil, fmt.Errorf("script debugging requires pidfd wait support: %w", err)
	} else {
		_ = process.Close()
		return nil, fmt.Errorf("script debugging requires pidfd signal support: %w", err)
	}
}

func (p *scriptPIDFD) Kill() error {
	err := unix.PidfdSendSignal(p.fd, unix.SIGKILL, nil, 0)
	if errors.Is(err, unix.ESRCH) {
		return os.ErrProcessDone
	}
	return err
}

func (p *scriptPIDFD) Reap() {
	var info unix.Siginfo
	for {
		err := unix.Waitid(unix.P_PIDFD, p.fd, &info, unix.WEXITED, nil)
		if !errors.Is(err, unix.EINTR) {
			return
		} // Delve may already have reaped it.
	}
}

func (p *scriptPIDFD) Close() error { return unix.Close(p.fd) }
