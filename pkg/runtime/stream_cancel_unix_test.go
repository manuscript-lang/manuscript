//go:build unix

package msruntime

import (
	"context"
	"os"
	"syscall"
	"testing"
	"time"
)

// blockingPipe returns a pipe whose read end is a blocking descriptor, as the
// standard input of a shell pipeline is: it supports no read deadlines.
func blockingPipe(t *testing.T) (read *os.File, write *os.File) {
	t.Helper()
	var fds [2]int
	if err := syscall.Pipe(fds[:]); err != nil {
		t.Fatal(err)
	}
	read, write = os.NewFile(uintptr(fds[0]), "read"), os.NewFile(uintptr(fds[1]), "write")
	t.Cleanup(func() { read.Close(); write.Close() })
	return read, write
}

func TestHostStreamReadCancelsOnBlockingDescriptor(t *testing.T) {
	read, write := blockingPipe(t)
	stream := newHostStream(read, false)
	reader, cancel := context.WithCancel(context.Background())
	ctx := &Execution{Context: reader, calls: &callState{}}
	time.AfterFunc(30*time.Millisecond, cancel)

	start := time.Now()
	stopped := make(chan any, 1)
	go func() {
		defer func() { stopped <- recover() }()
		stream.Read(ctx, Some(8))
	}()
	select {
	case r := <-stopped:
		if _, ok := r.(cancelled); !ok {
			t.Fatalf("read ended with %v, want cancellation", r)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("read stayed blocked after cancellation")
	}
	if time.Since(start) > 2*time.Second {
		t.Fatalf("cancellation took %v", time.Since(start))
	}

	// The read the cancelled call started keeps running: its bytes reach the
	// next reader, split across calls without loss.
	if _, err := write.Write([]byte("abcdef")); err != nil {
		t.Fatal(err)
	}
	fresh := &Execution{Context: context.Background(), calls: &callState{}}
	var got []byte
	for len(got) < 6 {
		result := stream.Read(fresh, Some(4))
		if result.Failed || !result.Val.Some {
			t.Fatalf("read = %+v", result)
		}
		got = append(got, result.Val.Val.Data...)
	}
	if string(got) != "abcdef" {
		t.Fatalf("got %q", got)
	}
}

func TestHostStreamCloseInterruptsBlockingRead(t *testing.T) {
	read, _ := blockingPipe(t)
	stream := newHostStream(read, false)
	ctx := &Execution{Context: context.Background(), calls: &callState{}}
	finished := make(chan Result[Option[*Bytes], IoError], 1)
	go func() { finished <- stream.Read(ctx, Some(8)) }()
	time.Sleep(30 * time.Millisecond)
	stream.Close(ctx)
	select {
	case result := <-finished:
		if !result.Failed {
			t.Fatalf("read succeeded after close: %+v", result)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("close did not release the blocked read")
	}
}
