//go:build !windows

package debugger

import (
	"golang.org/x/sys/unix"
	"os"
	"testing"
	"time"
)

func TestScriptFileRestoresFlags(t *testing.T) {
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	defer writer.Close()
	raw, err := reader.SyscallConn()
	if err != nil {
		t.Fatal(err)
	}
	flags := func() int {
		var result int
		var callErr error
		if err := raw.Control(func(fd uintptr) { result, callErr = unix.FcntlInt(fd, unix.F_GETFL, 0) }); err != nil {
			t.Fatal(err)
		}
		if callErr != nil {
			t.Fatal(callErr)
		}
		return result
	}
	before := flags()
	copy, restore, err := scriptFile(reader)
	if err != nil {
		t.Fatal(err)
	}
	copy.Close()
	restore()
	if after := flags(); after != before {
		t.Fatalf("flags changed: %x -> %x", before, after)
	}
	// The original Go file still supports poller deadlines after duplication.
	if err := reader.SetReadDeadline(time.Now()); err != nil {
		t.Fatal(err)
	}
}
