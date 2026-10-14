package debugger

import (
	"errors"
	"fmt"
	"os"
	"time"

	"golang.org/x/sys/unix"
)

type scriptPIDFD struct{ fd, group int }

func scriptProcessSupported() error { return nil }

func openScriptProcess(pid int) (scriptProcess, error) { return openScriptPIDFD(pid, unix.PidfdOpen) }

func openScriptPIDFD(pid int, open func(int, int) (int, error)) (scriptProcess, error) {
	fd, err := open(pid, 0)
	if err != nil {
		return nil, fmt.Errorf("script debugging requires an identity-bound Linux pidfd (no PID-only fallback): %w", err)
	}
	process := &scriptPIDFD{fd: fd}
	group, err := unix.Getpgid(pid)
	if err != nil {
		_ = process.Close()
		return nil, fmt.Errorf("script debugging requires Delve's private process group: %w", err)
	}
	if group != pid {
		_ = process.Close()
		return nil, fmt.Errorf("script debugging requires Delve's private process group (got %d for %d)", group, pid)
	}
	process.group = group
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

func (p *scriptPIDFD) Interrupt() error {
	err := unix.PidfdSendSignal(p.fd, unix.SIGKILL, nil, 0)
	if errors.Is(err, unix.ESRCH) {
		return os.ErrProcessDone
	}
	return err
}

func (p *scriptPIDFD) Reap() error {
	for {
		var info unix.Siginfo
		err := unix.Waitid(unix.P_PIDFD, p.fd, &info, unix.WEXITED|unix.WNOHANG, nil)
		if errors.Is(err, unix.EINTR) {
			continue
		}
		if errors.Is(err, unix.ECHILD) {
			return nil // Delve may already have reaped the leader.
		}
		if err != nil {
			return err
		}
		// Linux ptraced stops can be reported even with only WEXITED.
		// CLD_EXITED/KILLED/DUMPED (1..3) alone establish completion.
		if info.Signo != 0 && info.Code >= 1 && info.Code <= 3 {
			return nil
		}
		group, err := unix.Getpgid(p.group)
		if err != nil {
			return err
		}
		if group != p.group {
			return fmt.Errorf("debug target left its private process group; cannot safely drain ptrace wait records")
		}
		// A killed ptraced leader cannot become waitable until its exited
		// siblings' wait records are drained. Delve has joined and relinquished wait ownership;
		// this private group is retained by the still-unreaped leader above.
		// Retry the pidfd after each wait, including a wait that reaps the leader.
		var status unix.WaitStatus
		pid, err := unix.Wait4(-p.group, &status, unix.WALL|unix.WNOHANG, nil)
		if err != nil && !errors.Is(err, unix.EINTR) && !errors.Is(err, unix.ECHILD) {
			return err
		}
		if pid == 0 || err != nil {
			time.Sleep(time.Millisecond)
		}
	}
}

func (p *scriptPIDFD) Close() error { return unix.Close(p.fd) }
