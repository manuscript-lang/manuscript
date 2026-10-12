package msruntime

import (
	goruntime "runtime"
	"sync"
	"time"
)

func init() {
	libraryAdd("tasks", "yield_now", "Unit", nil, func(ctx *Execution, _ string, _ []Value) Value {
		CheckCancelled(ctx)
		goruntime.Gosched()
		CheckCancelled(ctx)
		return Unit{}
	})
}

type libraryTimer struct {
	mu                       sync.Mutex
	timer                    *time.Timer
	delay                    time.Duration
	repeating, closed, fired bool
	changed, done            chan struct{}
	gate                     chan struct{}
}

func newLibraryTimer(delay time.Duration, repeating bool) *libraryTimer {
	return &libraryTimer{timer: time.NewTimer(delay), delay: delay, repeating: repeating, changed: make(chan struct{}), done: make(chan struct{}), gate: make(chan struct{}, 1)}
}
func (t *libraryTimer) Operation(name string) Function {
	result := "Unit"
	if name == "wait" {
		result = libraryRuntimeType(libraryResult("Unit", "TimeError"))
	}
	if name == "restart" {
		result = libraryRuntimeType(libraryResult("Unit", "TimeError"))
	}
	return NewFunction(nil, result, func(ctx *Execution, _ []Value) Value {
		r := result
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
		if name == "restart" {
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
			t.fired = true
			if t.repeating {
				t.timer.Reset(t.delay)
			}
			t.mu.Unlock()
			return libraryOK(r, Unit{})
		}
	})
}
