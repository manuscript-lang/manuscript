package msruntime

import (
	"github.com/manuscript-lang/manuscript/internal/hostos"
	"os"
	"os/signal"
	"sync"
	"syscall"
)

func init() {
	LibraryMethods = append(LibraryMethods, LibraryMethod{"ProcessControl", "watch_signals", libraryResult("SignalStream", "ProcessError"), []LibraryParam{{"signals", "List[Int]"}, {"capacity", "Int"}}}, LibraryMethod{"SignalStream", "close", "Unit", nil}, LibraryMethod{"SignalStream", "next", libraryResult("Int", "ProcessError"), nil})
}

type librarySignalStream struct {
	mu     sync.Mutex
	closed bool
	events chan os.Signal
	done   chan struct{}
	gate   chan struct{}
}

func libraryNewSignalStream(ctx *Execution, r string, a []Value) Value {
	capacity := a[1].(int64)
	if capacity <= 0 || capacity > 1048576 {
		return libraryError(r, "InvalidInput", "")
	}
	var signals []os.Signal
	for _, value := range a[0].(*List).Items {
		n := value.(int64)
		if n <= 0 || n > 64 || n == int64(syscall.SIGKILL) || n == hostos.Constants()["SIGSTOP"] {
			return libraryError(r, "InvalidInput", "")
		}
		signals = append(signals, syscall.Signal(n))
	}
	if len(signals) == 0 {
		return libraryError(r, "InvalidInput", "")
	}
	stream := &librarySignalStream{events: make(chan os.Signal, int(capacity)), done: make(chan struct{}), gate: make(chan struct{}, 1)}
	signal.Notify(stream.events, signals...)
	return libraryOK(r, ViewOf("@std/SignalStream", stream))
}
func (s *librarySignalStream) Operation(name string) Function {
	return libraryMethod("SignalStream", name, func(ctx *Execution, r string, _ []Value) Value {
		if name == "close" {
			s.mu.Lock()
			if !s.closed {
				s.closed = true
				close(s.done)
			}
			s.mu.Unlock()
			signal.Stop(s.events)
			s.gate <- struct{}{}
			<-s.gate
			return Unit{}
		}
		select {
		case s.gate <- struct{}{}:
		case <-s.done:
			return libraryError(r, "Closed", "")
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		}
		defer func() { <-s.gate }()
		select {
		case <-s.done:
			return libraryError(r, "Closed", "")
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		case value := <-s.events:
			CheckCancelled(ctx)
			return libraryOK(r, int64(value.(syscall.Signal)))
		}
		return Panic("unreachable signal wait")
	})
}
