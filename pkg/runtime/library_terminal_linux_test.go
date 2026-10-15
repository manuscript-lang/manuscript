//go:build linux

package msruntime

import (
	"context"
	"os"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func openPseudoTerminal(t *testing.T) (master, slave *os.File) {
	t.Helper()
	master, err := os.OpenFile("/dev/ptmx", os.O_RDWR, 0)
	if err != nil {
		t.Skip("no pseudo-terminal:", err)
	}
	fd := int(master.Fd())
	if err = unix.IoctlSetPointerInt(fd, unix.TIOCSPTLCK, 0); err != nil {
		t.Skip(err)
	}
	number, err := unix.IoctlGetInt(fd, unix.TIOCGPTN)
	if err != nil {
		t.Skip(err)
	}
	slave, err = os.OpenFile("/dev/pts/"+strconv.Itoa(number), os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		t.Skip(err)
	}
	t.Cleanup(func() { master.Close(); slave.Close() })
	return master, slave
}

func localFlags(t *testing.T, file *os.File) uint32 {
	t.Helper()
	state, err := unix.IoctlGetTermios(int(file.Fd()), unix.TCGETS)
	if err != nil {
		t.Fatal(err)
	}
	return state.Lflag
}

func TestRawTerminalOnPseudoTerminal(t *testing.T) {
	master, slave := openPseudoTerminal(t)
	stdin, stdout := os.Stdin, os.Stdout
	os.Stdin, os.Stdout = slave, slave
	defer func() { os.Stdin, os.Stdout = stdin, stdout }()
	if err := unix.IoctlSetWinsize(int(slave.Fd()), unix.TIOCSWINSZ, &unix.Winsize{Row: 24, Col: 80}); err != nil {
		t.Fatal(err)
	}
	before := localFlags(t, slave)
	ctx := &Execution{Context: context.Background()}
	opened := newRawTerminal(true)
	if opened.Failed {
		t.Fatalf("raw_mode: %+v", opened)
	}
	raw := opened.Val.(*osRawTerminal)
	if localFlags(t, slave)&(unix.ICANON|unix.ECHO|unix.ISIG) != 0 {
		t.Fatal("raw mode left line discipline enabled")
	}
	if again := newRawTerminal(false); !again.Failed || again.Err != (TerminalError_Busy{}) {
		t.Fatalf("second raw mode: %+v", again)
	}

	next := func(timeout time.Duration) Result[Option[TerminalEvent], TerminalError] {
		return raw.next(ctx, Some(Duration(timeout)))
	}
	event := func(timeout time.Duration) TerminalEvent {
		result := next(timeout)
		if result.Failed || !result.Val.Some {
			t.Fatalf("no event: %+v", result)
		}
		return result.Val.Val
	}
	master.WriteString("a\x1b[A")
	first, second := event(2*time.Second), event(2*time.Second)
	if first != (TerminalEvent_Text{Text: "a"}) || second != (TerminalEvent_Key{Name: "up"}) {
		t.Fatalf("events: %+v %+v", first, second)
	}
	if none := next(20 * time.Millisecond); none.Failed || none.Val.Some {
		t.Fatalf("timeout: %+v", none)
	}

	unix.IoctlSetWinsize(int(slave.Fd()), unix.TIOCSWINSZ, &unix.Winsize{Row: 30, Col: 100})
	syscall.Kill(os.Getpid(), syscall.SIGWINCH)
	if resize := event(2 * time.Second); resize != (TerminalEvent_Resize{Columns: 100, Rows: 30}) {
		t.Fatalf("resize: %+v", resize)
	}

	cancelled, cancel := context.WithCancel(context.Background())
	go func() { time.Sleep(30 * time.Millisecond); cancel() }()
	func() {
		defer func() {
			if recover() == nil {
				t.Error("cancelled wait returned")
			}
		}()
		raw.next(&Execution{Context: cancelled}, None[Duration]())
	}()

	raw.close()
	if after := localFlags(t, slave); after != before {
		t.Fatalf("settings not restored: %x != %x", after, before)
	}
	if closed := raw.NextEvent(ctx, Some(Duration(time.Second))); !closed.Failed || closed.Err != (TerminalError_Closed{}) {
		t.Fatalf("after close: %+v", closed)
	}
	var output []byte
	buffer := make([]byte, 256)
	master.SetReadDeadline(time.Now().Add(time.Second))
	for !strings.Contains(string(output), "\x1b[?1049l") {
		n, err := master.Read(buffer)
		output = append(output, buffer[:n]...)
		if err != nil {
			break
		}
	}
	if !strings.Contains(string(output), "\x1b[?1049h") || !strings.Contains(string(output), "\x1b[?1049l") {
		t.Fatalf("alternate screen sequences: %q", output)
	}
}
