package gdbserial

import (
	"bufio"
	"context"
	"errors"
	"io"
	"net"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/go-delve/delve/pkg/logflags"
	"github.com/go-delve/delve/pkg/proc"
)

func scriptTestConn(t *testing.T) (*gdbConn, net.Conn) {
	t.Helper()
	local, remote := net.Pipe()
	t.Cleanup(func() { local.Close(); remote.Close() })
	conn := &gdbConn{conn: local, rdr: bufio.NewReader(local), inbuf: make([]byte, 2), log: logflags.GdbWireLogger(), direction: proc.Forward, goos: "darwin"}
	conn.session = &scriptSessionControl{conn: local}
	return conn, remote
}

func scriptReadPacket(t *testing.T, remote net.Conn) string {
	t.Helper()
	var packet []byte
	var b [1]byte
	for {
		if _, err := io.ReadFull(remote, b[:]); err != nil {
			t.Error(err)
			return ""
		}
		packet = append(packet, b[0])
		if b[0] == '#' {
			break
		}
	}
	var sum [2]byte
	if _, err := io.ReadFull(remote, sum[:]); err != nil {
		t.Error(err)
	}
	return string(packet[:len(packet)-1])
}

func TestScriptSessionLatchBeforeDispatch(t *testing.T) {
	for _, stepping := range []bool{false, true} {
		conn, _ := scriptTestConn(t)
		if err := conn.session.interrupt(); err != nil {
			t.Fatal(err)
		}
		var err error
		if stepping {
			err = conn.step(&gdbThread{strID: "1"}, nil, false)
		} else {
			_, err = conn.resume(&proc.ContinueOnceContext{}, nil, nil)
		}
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("pre-dispatch cancellation lost: %v", err)
		}
	}
}

func TestScriptSessionInterruptContinueAndStep(t *testing.T) {
	for _, operation := range []string{"continue", "step"} {
		t.Run(operation, func(t *testing.T) {
			conn, remote := scriptTestConn(t)
			dispatched := make(chan struct{})
			stubDone := make(chan struct{})
			go func() {
				defer close(stubDone)
				packet := scriptReadPacket(t, remote)
				want := "$vCont;c"
				if operation == "step" {
					want = "$vCont;s:1"
				}
				if packet != want {
					t.Errorf("packet %q, want %q", packet, want)
				}
				close(dispatched)
				var interrupt [1]byte
				if _, err := io.ReadFull(remote, interrupt[:]); err != nil || interrupt[0] != ctrlC {
					t.Errorf("interrupt: %v %v", interrupt, err)
					return
				}
				remote.Write([]byte("$T02thread:1;#d4")) // recv trusts checksum in no-ack mode
			}()
			done := make(chan error, 1)
			go func() {
				if operation == "step" {
					done <- conn.step(&gdbThread{strID: "1"}, nil, false)
					return
				}
				_, err := conn.resume(&proc.ContinueOnceContext{}, nil, nil)
				done <- err
			}()
			<-dispatched
			if err := conn.session.interrupt(); err != nil {
				t.Fatal(err)
			}
			select {
			case err := <-done:
				if !errors.Is(err, context.Canceled) {
					t.Fatal(err)
				}
			case <-time.After(5 * time.Second):
				t.Fatal("command did not join")
			}
			<-stubDone
			if err := conn.sendExecution([]byte("$vCont;c")); !errors.Is(err, context.Canceled) {
				t.Fatal("later dispatch escaped latch", err)
			}
		})
	}
}

func TestScriptSessionPreservesNaturalExit(t *testing.T) {
	conn, _ := scriptTestConn(t)
	conn.session.interrupt()
	exited := proc.ErrProcessExited{Pid: 123, Status: 9}
	if err := conn.finishExecution(exited); !errors.As(err, &exited) {
		t.Fatal(err)
	}
}

func TestScriptSessionKillAndNaturalExitJoinHelper(t *testing.T) {
	for _, natural := range []bool{false, true} {
		conn, remote := scriptTestConn(t)
		wait := make(chan *os.ProcessState, 1)
		p := &gdbProcess{conn: *conn, scripted: true, waitChan: wait, exited: natural, bi: proc.NewBinaryInfo("darwin", "amd64")}
		stubDone := make(chan struct{})
		go func() {
			defer close(stubDone)
			if !natural {
				if packet := scriptReadPacket(t, remote); packet != "$k" {
					t.Errorf("teardown packet %q", packet)
				}
				remote.Write([]byte("$X09#c1"))
			}
			var b [1]byte
			remote.Read(b[:])
			close(wait)
		}()
		if !natural {
			if err := p.Detach(0, true); err != nil {
				t.Fatal(err)
			}
		}
		if err := p.Close(); err != nil {
			t.Fatal(err)
		}
		<-stubDone
	}
}

func TestScriptSessionBoundsBlockedDispatchWrite(t *testing.T) {
	conn, _ := scriptTestConn(t) // stub never reads the dispatch packet
	started := make(chan struct{}, 1)
	notify := &scriptWriteNotifyConn{Conn: conn.conn, started: started}
	conn.conn, conn.session.conn = notify, notify
	done := make(chan error, 1)
	go func() { done <- conn.sendExecution([]byte("$vCont;c")) }()
	<-started
	interrupted := make(chan error, 1)
	go func() { interrupted <- conn.session.interrupt() }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("packet write prevented cancellation")
	}
	select {
	case err := <-interrupted:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("cancel latch did not join")
	}
}

type scriptWriteNotifyConn struct {
	net.Conn
	started chan struct{}
}

func (c *scriptWriteNotifyConn) Write(data []byte) (int, error) {
	select {
	case c.started <- struct{}{}:
	default:
	}
	return c.Conn.Write(data)
}

func TestScriptSessionJoinsHelperWithoutPIDSignal(t *testing.T) {
	conn, remote := scriptTestConn(t)
	wait := make(chan *os.ProcessState, 1)
	// A Process pointing at ourselves detects accidental fallback Kill.
	helper, err := os.FindProcess(os.Getpid())
	if err != nil {
		t.Fatal(err)
	}
	defer helper.Release()
	p := &gdbProcess{conn: *conn, scripted: true, process: helper, waitChan: wait}
	joined := make(chan struct{})
	go func() { var b [1]byte; remote.Read(b[:]); close(wait); close(joined) }()
	if err := p.closeScriptSession(); err != nil {
		t.Fatal(err)
	}
	<-joined
	if p.process != nil {
		t.Fatal("helper wait not joined")
	}
	var calls sync.WaitGroup
	for i := 0; i < 4; i++ {
		calls.Add(1)
		go func() {
			defer calls.Done()
			if err := p.closeScriptSession(); err != nil {
				t.Error(err)
			}
		}()
	}
	calls.Wait()
}

func TestScriptSessionRejectsMixedRemoteOutput(t *testing.T) {
	conn, _ := scriptTestConn(t)
	if repeat, _, err := conn.parseStopPacket([]byte("O68656c6c6f"), "1", nil); err == nil || repeat {
		t.Fatalf("mixed transport output accepted: %v %v", repeat, err)
	}
}

func TestScriptSessionCancelsBlockedMetadata(t *testing.T) {
	conn, remote := scriptTestConn(t)
	accepted := make(chan struct{})
	go func() { scriptReadPacket(t, remote); close(accepted) }()
	done := make(chan error, 1)
	go func() { _, err := conn.exec([]byte("$qfThreadInfo"), "post-stop metadata"); done <- err }()
	<-accepted
	if err := conn.session.interrupt(); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("blocked metadata reported success")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("cancelled metadata did not join")
	}
	// Teardown must permit a fresh kill after the cancellation deadline expired.
	conn.session.beginTeardown()
	stubDone := make(chan struct{})
	go func() {
		defer close(stubDone)
		if packet := scriptReadPacket(t, remote); packet != "$k" {
			t.Error(packet)
		}
		remote.Write([]byte("$X09#c1"))
	}()
	var exited proc.ErrProcessExited
	if err := conn.kill(); !errors.As(err, &exited) {
		t.Fatalf("fresh teardown kill: %v", err)
	}
	<-stubDone
}

func TestScriptSessionCancelsLaunchListen(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	ctx, cancel := context.WithCancel(context.Background())
	wait := make(chan *os.ProcessState, 1)
	p := &gdbProcess{scripted: true, scriptContext: ctx, waitChan: wait}
	done := make(chan error, 1)
	go func() { _, err := p.Listen(listener, "", "", 0, nil, proc.StopLaunched); done <- err }()
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("cancelled listener did not join")
	}
	close(wait)
	if err := p.closeScriptSession(); err != nil {
		t.Fatal(err)
	}
}

func TestScriptSessionRefreshesIdleBinaryReadDeadline(t *testing.T) {
	conn, remote := scriptTestConn(t)
	conn.session.setReadDeadline(time.Now().Add(-time.Second))
	stubDone := make(chan struct{})
	go func() {
		defer close(stubDone)
		if packet := scriptReadPacket(t, remote); packet != "$x100,1" {
			t.Error(packet)
		}
		remote.Write([]byte("$A#41"))
	}()
	data := make([]byte, 1)
	if err := conn.readMemoryBinary(data, 0x100); err != nil || data[0] != 'A' {
		t.Fatalf("query after idle: %q %v", data, err)
	}
	<-stubDone
}

func TestScriptSessionCancelsBlockedHeartbeatWrite(t *testing.T) {
	conn, remote := scriptTestConn(t)
	conn.isDebugserver = true
	started := make(chan struct{}, 2)
	notify := &scriptWriteNotifyConn{Conn: &scriptFirstReadTimeoutConn{Conn: conn.conn}, started: started}
	conn.conn, conn.session.conn = notify, notify
	conn.rdr = bufio.NewReader(notify)
	accepted := make(chan struct{})
	go func() { scriptReadPacket(t, remote); close(accepted) }()
	done := make(chan error, 1)
	go func() { _, err := conn.resume(&proc.ContinueOnceContext{}, nil, nil); done <- err }()
	<-started
	<-accepted
	select {
	case <-started: // heartbeat '?' packet enters a write the stub never reads
	case <-time.After(5 * time.Second):
		t.Fatal("missing heartbeat")
	}
	if err := conn.session.interrupt(); err == nil {
		t.Fatal("unread interrupt unexpectedly succeeded")
	}
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("heartbeat write prevented command join")
	}
}

// Exercise the heartbeat write without waiting for the production 10s interval.
type scriptFirstReadTimeoutConn struct {
	net.Conn
	timedOut bool
}

func (c *scriptFirstReadTimeoutConn) Read(data []byte) (int, error) {
	if !c.timedOut {
		c.timedOut = true
		return 0, os.ErrDeadlineExceeded
	}
	return c.Conn.Read(data)
}

func TestScriptSessionStartupCancelCannotBeReset(t *testing.T) {
	local, remote := net.Pipe()
	defer local.Close()
	defer remote.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	p := newScriptProcess(nil, true)
	p.scriptContext = ctx
	done := make(chan error, 1)
	go func() { _, err := p.Connect(local, "", "", 0, nil, proc.StopLaunched); done <- err }()
	var ack [1]byte
	if _, err := io.ReadFull(remote, ack[:]); err != nil {
		t.Fatal(err)
	}
	cancel()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("cancelled bootstrap succeeded")
		}
	case <-time.After(time.Second):
		t.Fatal("cancelled bootstrap did not join")
	}
	// Initialization and stopped queries refresh deadlines. They must never
	// reopen the closed startup connection after cancellation.
	p.conn.session = &scriptSessionControl{conn: local}
	p.conn.session.setReadDeadline(time.Now().Add(time.Minute))
	if err := p.conn.sendExecution([]byte("$vCont;c")); err == nil {
		t.Fatal("deadline reset erased startup cancellation")
	}
	p.bi.Close()
}

func TestScriptSessionKillDoesNotDetachAfterExtraStop(t *testing.T) {
	conn, remote := scriptTestConn(t)
	wait := make(chan *os.ProcessState, 1)
	p := &gdbProcess{conn: *conn, scripted: true, waitChan: wait}
	stubDone := make(chan struct{})
	go func() {
		defer close(stubDone)
		if packet := scriptReadPacket(t, remote); packet != "$k" {
			t.Error(packet)
		}
		remote.Write([]byte("$T02thread:1;#d4"))
		var b [1]byte
		if n, err := remote.Read(b[:]); n != 0 || err != io.EOF {
			t.Errorf("kill followed by a detach packet: %q %v", b, err)
		}
		close(wait)
	}()
	if err := p.Detach(0, true); err != nil {
		t.Fatal(err)
	}
	<-stubDone
}
