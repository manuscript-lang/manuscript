//go:build !windows

package debugger

import (
	"context"
	"errors"
	"io"
	"os"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func namedDuplicate(t *testing.T, file *os.File, name string) *os.File {
	t.Helper()
	raw, err := file.SyscallConn()
	if err != nil {
		t.Fatal(err)
	}
	var fd int
	var dupErr error
	if err := raw.Control(func(original uintptr) { fd, dupErr = unix.FcntlInt(original, unix.F_DUPFD_CLOEXEC, 0) }); err != nil || dupErr != nil {
		t.Fatal(errors.Join(err, dupErr))
	}
	alias := os.NewFile(uintptr(fd), name)
	t.Cleanup(func() { _ = alias.Close() })
	return alias
}

func descriptorFlags(t *testing.T, file *os.File) int {
	t.Helper()
	raw, err := file.SyscallConn()
	if err != nil {
		t.Fatal(err)
	}
	var flags int
	var flagErr error
	if err := raw.Control(func(fd uintptr) { flags, flagErr = unix.FcntlInt(fd, unix.F_GETFL, 0) }); err != nil || flagErr != nil {
		t.Fatal(errors.Join(err, flagErr))
	}
	return flags
}

func TestDuplicateIORecognizesRedirectedNullStreams(t *testing.T) {
	null, err := os.OpenFile(os.DevNull, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer null.Close()
	for _, name := range []string{"/dev/stdin", "/dev/stdout", "/dev/stderr"} {
		t.Run(name, func(t *testing.T) {
			original := namedDuplicate(t, null, name)
			flags := descriptorFlags(t, original)
			owned, restore, err := duplicateIO(original)
			if err != nil {
				t.Fatalf("redirected null stream rejected: %v", err)
			}
			if _, err := owned.Write([]byte("discard")); err != nil {
				t.Fatal(err)
			}
			if err := errors.Join(owned.Close(), restore()); err != nil {
				t.Fatal(err)
			}
			if descriptorFlags(t, original) != flags {
				t.Fatal("borrowed null stream flags changed")
			}
			if _, err := original.Write([]byte("still open")); err != nil {
				t.Fatal(err)
			}
			if _, err := original.Read(make([]byte, 1)); !errors.Is(err, io.EOF) {
				t.Fatalf("borrowed null stream no longer reads EOF: %v", err)
			}
		})
	}
}

func TestDuplicateIODoesNotTrustNullDisplayName(t *testing.T) {
	input, output, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	defer output.Close()
	alias := namedDuplicate(t, input, os.DevNull)
	owned, restore, err := duplicateIO(alias)
	if err != nil {
		t.Fatal(err)
	}
	if err := owned.SetReadDeadline(time.Now().Add(10 * time.Millisecond)); err != nil {
		t.Fatal(err)
	}
	if _, err := owned.Read(make([]byte, 1)); !errors.Is(err, os.ErrDeadlineExceeded) {
		t.Fatalf("misnamed pipe lost bounded reads: %v", err)
	}
	if err := errors.Join(owned.Close(), restore()); err != nil {
		t.Fatal(err)
	}
	if _, err := output.Write([]byte("x")); err != nil {
		t.Fatal(err)
	}
	if _, err := alias.Read(make([]byte, 1)); err != nil {
		t.Fatal(err)
	}
	zero, err := os.Open("/dev/zero")
	if err != nil {
		t.Fatal(err)
	}
	defer zero.Close()
	zeroAlias := namedDuplicate(t, zero, os.DevNull)
	flags := descriptorFlags(t, zeroAlias)
	if file, undo, err := duplicateIO(zeroAlias); err == nil {
		_ = file.Close()
		_ = undo()
		t.Fatal("non-pollable device was exempted by its display name")
	}
	if descriptorFlags(t, zeroAlias) != flags {
		t.Fatal("failed duplication changed borrowed flags")
	}
}

func TestBoundedDiagnosticPreservesSharedBorrowedOutput(t *testing.T) {
	input, output, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	defer output.Close()
	stderr := namedDuplicate(t, output, "/dev/stderr")
	if err := stderr.SetWriteDeadline(time.Now().Add(-time.Hour)); err != nil {
		t.Fatal(err)
	}
	flags := descriptorFlags(t, output)
	owned, undo, err := duplicateIO(output)
	if err != nil {
		t.Fatal(err)
	}
	if err := owned.SetWriteDeadline(time.Now().Add(10 * time.Millisecond)); err != nil {
		t.Fatal(err)
	}
	if _, err := owned.Write(make([]byte, 1024*1024)); !errors.Is(err, os.ErrDeadlineExceeded) {
		t.Fatalf("output did not fill: %v", err)
	}
	if err := errors.Join(owned.Close(), undo()); err != nil {
		t.Fatal(err)
	}
	if err := ReportError(context.Background(), stderr, io.ErrUnexpectedEOF); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("full shared stderr did not bound its diagnostic: %v", err)
	}
	if descriptorFlags(t, output) != flags || descriptorFlags(t, stderr) != flags {
		t.Fatal("diagnostic changed borrowed shared flags")
	}
	if err := input.SetReadDeadline(time.Now().Add(10 * time.Millisecond)); err != nil {
		t.Fatal(err)
	}
	for {
		if _, err := input.Read(make([]byte, 4096)); errors.Is(err, os.ErrDeadlineExceeded) {
			break
		} else if err != nil {
			t.Fatal(err)
		}
	}
	if _, err := stderr.Write([]byte("x")); !errors.Is(err, os.ErrDeadlineExceeded) {
		t.Fatalf("diagnostic reset the borrowed write deadline: %v", err)
	}
	if err := stderr.SetWriteDeadline(time.Time{}); err != nil {
		t.Fatal(err)
	}
	if err := input.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	if _, err := stderr.Write([]byte("x")); err != nil {
		t.Fatal(err)
	}
	if _, err := input.Read(make([]byte, 1)); err != nil {
		t.Fatal(err)
	}
}
