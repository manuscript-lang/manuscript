package debugger

import (
	"fmt"
	"time"

	"github.com/go-delve/delve/service/rpccommon"
	"golang.org/x/sys/unix"
)

type scriptDebugserver struct {
	interrupt func() error
	queue     int
}

func scriptProcessSupported() error { return nil }

func scriptInterruptsInspection() bool { return true }

func bindScriptProcess(server *rpccommon.ServerImpl, pid int) (scriptProcess, error) {
	interrupt, err := server.SessionInterrupt()
	if err != nil {
		return nil, err
	}
	return openScriptExitObservation(pid, interrupt)
}

func openScriptExitObservation(pid int, interrupt func() error) (scriptProcess, error) {
	queue, err := unix.Kqueue()
	if err != nil {
		return nil, err
	}
	unix.CloseOnExec(queue)
	// Register while Delve still owns a stopped target; the knote retains that
	// process identity, including after helper shutdown reparents the target.
	change := unix.Kevent_t{Ident: uint64(pid), Filter: unix.EVFILT_PROC, Flags: unix.EV_ADD | unix.EV_ENABLE | unix.EV_ONESHOT, Fflags: unix.NOTE_EXIT}
	if _, err := unix.Kevent(queue, []unix.Kevent_t{change}, nil, nil); err != nil {
		unix.Close(queue)
		return nil, err
	}
	return &scriptDebugserver{interrupt: interrupt, queue: queue}, nil
}

func (p *scriptDebugserver) Interrupt() error { return p.interrupt() }

func (p *scriptDebugserver) Reap() error {
	events := make([]unix.Kevent_t, 1)
	deadline := time.Now().Add(10 * time.Second)
	for {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			return fmt.Errorf("debugserver target did not exit after session cleanup")
		}
		timeout := unix.NsecToTimespec(remaining.Nanoseconds())
		n, err := unix.Kevent(p.queue, nil, events, &timeout)
		if err == unix.EINTR {
			continue
		}
		if err != nil {
			return err
		}
		if n == 0 {
			return fmt.Errorf("debugserver target did not exit after session cleanup")
		}
		if events[0].Flags&unix.EV_ERROR != 0 {
			return unix.Errno(events[0].Data)
		}
		return nil
	}
}

func (p *scriptDebugserver) Close() error { return unix.Close(p.queue) }
