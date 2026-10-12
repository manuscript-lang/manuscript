package msruntime

import (
	goruntime "runtime"
	"sync"
	"time"
)

func init() {
	for _, name := range []string{"set_timeout", "set_interval"} {
		repeating := name == "set_interval"
		libraryAdd("timers", name, libraryResult("Timer", "TimerError"), []LibraryParam{{"delay", "Duration"}}, func(ctx *Execution, r string, a []Value) Value {
			delay := a[0].(Duration)
			if delay < 0 || repeating && delay == 0 {
				return libraryError(r, "InvalidInput", "")
			}
			CheckCancelled(ctx)
			return libraryOK(r, ViewOf("@std/Timer", newLibraryTimer(time.Duration(delay), repeating)))
		})
	}
	libraryAdd("timers", "set_immediate", "Timer", nil, func(ctx *Execution, _ string, _ []Value) Value {
		CheckCancelled(ctx)
		return ViewOf("@std/Timer", newLibraryTimer(0, false))
	})
	libraryAdd("timers", "yield_now", "Unit", nil, func(ctx *Execution, _ string, _ []Value) Value {
		CheckCancelled(ctx)
		goruntime.Gosched()
		CheckCancelled(ctx)
		return Unit{}
	})
	libraryGeneric("timers", "delay", "T", []LibraryParam{{"T", ""}}, []LibraryParam{{"duration", "Duration"}, {"value", "T"}}, func(ctx *Execution, _ string, a []Value) Value {
		delay := a[0].(Duration)
		if delay < 0 {
			return Panic("delay duration must be nonnegative")
		}
		timer := time.NewTimer(time.Duration(delay))
		defer timer.Stop()
		select {
		case <-timer.C:
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		}
		CheckCancelled(ctx)
		return a[1]
	})
	LibraryMethods = append(LibraryMethods, LibraryMethod{"Timer", "close", "Unit", nil}, LibraryMethod{"Timer", "wait", libraryResult("Int", "TimerError"), nil}, LibraryMethod{"Timer", "refresh", libraryResult("Unit", "TimerError"), nil})
}

type libraryTimer struct {
	mu                       sync.Mutex
	timer                    *time.Timer
	delay                    time.Duration
	repeating, closed, fired bool
	ticks                    int64
	changed, done            chan struct{}
	gate                     chan struct{}
}

func newLibraryTimer(delay time.Duration, repeating bool) *libraryTimer {
	return &libraryTimer{timer: time.NewTimer(delay), delay: delay, repeating: repeating, changed: make(chan struct{}), done: make(chan struct{}), gate: make(chan struct{}, 1)}
}
func (t *libraryTimer) Operation(name string) Function {
	return libraryMethod("Timer", name, func(ctx *Execution, r string, _ []Value) Value {
		if name == "close" {
			t.mu.Lock()
			if !t.closed {
				t.closed = true
				t.timer.Stop()
				close(t.done)
			}
			t.mu.Unlock()
			t.gate <- struct{}{}
			<-t.gate
			return Unit{}
		}
		if name == "refresh" {
			t.mu.Lock()
			defer t.mu.Unlock()
			if t.closed {
				return libraryError(r, "Closed", "")
			}
			t.timer.Stop()
			t.timer = time.NewTimer(t.delay)
			t.fired = false
			close(t.changed)
			t.changed = make(chan struct{})
			return libraryOK(r, Unit{})
		}
		select {
		case t.gate <- struct{}{}:
		case <-t.done:
			return libraryError(r, "Closed", "")
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		}
		defer func() { <-t.gate }()
		for {
			t.mu.Lock()
			if t.closed || t.fired && !t.repeating {
				t.mu.Unlock()
				return libraryError(r, "Closed", "")
			}
			timer, changed := t.timer, t.changed
			t.mu.Unlock()
			select {
			case <-t.done:
				return libraryError(r, "Closed", "")
			case <-ctx.Context.Done():
				CheckCancelled(ctx)
			case <-changed:
				continue
			case <-timer.C:
			}
			CheckCancelled(ctx)
			t.mu.Lock()
			if t.closed {
				t.mu.Unlock()
				return libraryError(r, "Closed", "")
			}
			if t.timer != timer {
				t.mu.Unlock()
				continue
			}
			t.ticks++
			tick := t.ticks
			t.fired = true
			if t.repeating {
				t.timer.Reset(t.delay)
			}
			t.mu.Unlock()
			return libraryOK(r, tick)
		}
	})
}
