package gdbserial

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sync"
	"time"

	"github.com/go-delve/delve/pkg/proc"
)

const scriptIOTimeout = 3 * time.Second

// A script retains this connection identity; cancellation never reads mutable
// target selection, validity, running state, or the connection's replacement.
type scriptSessionControl struct {
	mu       sync.Mutex
	conn     net.Conn
	cancel   bool
	active   bool
	deadline time.Time
	teardown bool
}

func (s *scriptSessionControl) interrupt() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cancel {
		return nil
	}
	s.cancel = true
	s.deadline = time.Now().Add(scriptIOTimeout)
	s.conn.SetReadDeadline(s.deadline)
	s.conn.SetWriteDeadline(s.deadline)
	if !s.active {
		return nil
	}
	_, err := s.conn.Write([]byte{ctrlC})
	return err
}

func (s *scriptSessionControl) cancelled() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.cancel
}

func (s *scriptSessionControl) ioDeadline(normal time.Time) time.Time {
	if s.cancel && !s.teardown && (normal.IsZero() || s.deadline.Before(normal)) {
		return s.deadline
	}
	return normal
}

func (s *scriptSessionControl) setReadDeadline(normal time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.conn.SetReadDeadline(s.ioDeadline(normal))
}

func (s *scriptSessionControl) setWriteDeadline(normal time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.conn.SetWriteDeadline(s.ioDeadline(normal))
}

func (s *scriptSessionControl) beginTeardown() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.teardown = true // command already joined; allow fresh bounded kill I/O
	s.conn.SetDeadline(time.Now().Add(scriptIOTimeout))
}

func (p *gdbProcess) SessionInterrupt() (func() error, error) {
	if !p.scripted || p.conn.session == nil {
		return nil, fmt.Errorf("backend was not launched as a scripted debugserver session")
	}
	return p.conn.session.interrupt, nil
}

func (conn *gdbConn) sendExecution(packet []byte) error {
	if conn.session == nil {
		return conn.send(packet)
	}
	s := conn.session
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cancel {
		return context.Canceled
	}
	// No-ack negotiation makes this only a bounded packet write, with no
	// response reader under the cancellation lock.
	s.conn.SetWriteDeadline(time.Now().Add(scriptIOTimeout))
	err := conn.sendPacket(packet)
	s.active = err == nil
	return err
}

func (conn *gdbConn) finishExecution(err error) error {
	if conn.session == nil {
		return err
	}
	s := conn.session
	s.mu.Lock()
	defer s.mu.Unlock()
	s.active = false
	var exited proc.ErrProcessExited
	if s.cancel && !errors.As(err, &exited) {
		return context.Canceled
	}
	return err
}

// Called only after commands join. Closing the -K connection makes debugserver
// exit without detaching; XNU kills any still-traced target on tracer exit.
// Both natural exit (Close) and kill/error (Detach/launch) join the same helper.
func (p *gdbProcess) closeScriptSession() error {
	p.scriptClose.Do(func() {
		if p.conn.conn != nil {
			p.conn.conn.Close()
		}
		if p.waitChan != nil {
			select {
			case <-p.waitChan:
				p.process = nil
			case <-time.After(scriptIOTimeout):
				p.scriptCloseErr = fmt.Errorf("debugserver did not exit after session close")
			}
		}
	})
	return p.scriptCloseErr
}
