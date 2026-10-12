package msruntime

import (
	"fmt"
	"sync"
	"time"
)

func init() {
	LibraryMethods = append(LibraryMethods, LibraryMethod{"ScheduledTimer", "close", "Unit", nil}, LibraryMethod{"ScheduledTimer", "refresh", libraryResult("Unit", "TimerError"), nil}, LibraryMethod{"ScheduledTimer", "status", "WorkStatus", nil})
	for _, name := range []string{"schedule_timeout", "schedule_interval", "schedule_immediate"} {
		immediate, repeating := name == "schedule_immediate", name == "schedule_interval"
		params := []LibraryParam{{"delay", "Duration"}, {"operation", "fn()->Result[Unit][String]"}}
		if immediate {
			params = params[1:]
		}
		libraryAdd("timers", name, libraryResult("ScheduledTimer", "TimerError"), params, func(ctx *Execution, r string, a []Value) Value {
			delay := Duration(0)
			operation := a[0]
			if !immediate {
				delay = a[0].(Duration)
				operation = a[1]
			}
			if delay < 0 || repeating && delay == 0 {
				return libraryError(r, "InvalidInput", "")
			}
			background := NewBackground(ctx, []Argument{{"limit", int64(1)}, {"history_limit", int64(1)}}).(*Background)
			delivered := false
			defer func() {
				if !delivered {
					background.close(Shield(ctx))
				}
			}()
			scheduled := &libraryScheduledTimer{timer: newLibraryTimer(time.Duration(delay), repeating), background: background, operation: operation, repeating: repeating, status: "Running"}
			if failure := scheduled.start(ctx, r); failure != nil {
				scheduled.timer.Operation("close").Body(Shield(ctx), nil)
				return failure
			}
			delivered = true
			return libraryOK(r, ViewOf("@std/ScheduledTimer", scheduled))
		})
	}
}

type libraryScheduledTimer struct {
	mu         sync.Mutex
	timer      *libraryTimer
	background *Background
	operation  Value
	repeating  bool
	id         OperationId
	closed     bool
	status     string
	generation uint64
}

func (t *libraryScheduledTimer) start(ctx *Execution, r string) Value {
	operation := NewFunction(nil, "@std/Result[Unit][String]", func(ctx *Execution, _ []Value) Value {
		for {
			t.timer.mu.Lock()
			fired, changed, closed := t.timer.fired, t.timer.changed, t.timer.closed
			t.timer.mu.Unlock()
			if closed {
				return libraryOK("@std/Result[Unit][String]", Unit{})
			}
			t.mu.Lock()
			status := t.status
			t.mu.Unlock()
			if !t.repeating && fired || status == "Failed" {
				select {
				case <-changed:
					continue
				case <-ctx.Context.Done():
					CheckCancelled(ctx)
				case <-t.timer.done:
					return libraryOK("@std/Result[Unit][String]", Unit{})
				}
			}
			tick := t.timer.Operation("wait").Body(ctx, nil).(Alternative)
			if tick.Tag != "ok" {
				return libraryOK("@std/Result[Unit][String]", Unit{})
			}
			t.mu.Lock()
			generation := t.generation
			t.mu.Unlock()
			outcome := Invoke(ctx, t.operation, nil).(Alternative)
			if outcome.Tag == "error" {
				reportDiagnostic(fmt.Sprint("Scheduled timer failure: ", outcome.Fields[0]))
			}
			t.mu.Lock()
			if generation == t.generation {
				if outcome.Tag == "error" {
					t.status = "Failed"
				} else if !t.repeating {
					t.status = "Succeeded"
				}
			}
			t.mu.Unlock()
		}
	})
	result := t.background.start(ctx, operation).(Alternative)
	if result.Tag == "error" {
		return libraryError(r, "Closed", "")
	}
	t.id = result.Fields[0].(OperationId)
	return nil
}
func (t *libraryScheduledTimer) Operation(name string) Function {
	return libraryMethod("ScheduledTimer", name, func(ctx *Execution, r string, _ []Value) Value {
		if name == "close" {
			t.mu.Lock()
			t.closed = true
			if t.status == "Running" {
				t.status = "Cancelled"
			}
			t.mu.Unlock()
			t.timer.Operation("close").Body(Shield(ctx), nil)
			t.background.close(Shield(ctx))
			return Unit{}
		}
		t.mu.Lock()
		defer t.mu.Unlock()
		if name == "status" {
			background := t.background.Operation("status").Body(ctx, []Value{t.id}).(Alternative)
			if background.Tag == "Crashed" || background.Tag == "Cancelled" && t.status == "Running" {
				return background
			}
			return Alternative{Type: "@std/WorkStatus", Tag: t.status}
		}
		if t.closed {
			return libraryError(r, "Closed", "")
		}
		refreshed := t.timer.Operation("refresh").Body(ctx, nil).(Alternative)
		if refreshed.Tag != "ok" {
			return refreshed
		}
		t.generation++
		t.status = "Running"
		status := t.background.Operation("status").Body(ctx, []Value{t.id}).(Alternative)
		if status.Tag != "Running" {
			if failure := t.start(ctx, r); failure != nil {
				return failure
			}
		}
		return libraryOK(r, Unit{})
	})
}
