package msruntime

import (
	"context"
	"fmt"
	"sync/atomic"
	"time"
)

// TestFixture is one checked, file-local make_fixture factory and its dispatch scope.
type TestFixture struct {
	File   string
	Create Value
	Scope  TypeScope
}

type fixtureState struct {
	definition      *TestFixture
	owner           *Execution
	cancel          context.CancelFunc
	instance        Value
	created, failed bool
	poisoned        atomic.Bool
	retained        []context.CancelFunc
}

type fixtureOutcome struct {
	value     Value
	failure   any
	abandoned bool
	release   context.CancelFunc
}

// fixturePhase keeps successful creation contexts alive until file teardown.
// A timeout cancels only this phase; teardown gets its own bounded context.
func fixturePhase(owner *Execution, timeout time.Duration, operation func(*Execution) Value) fixtureOutcome {
	ctx, cancel := context.WithCancel(owner.Context)
	execution := inherit(owner, ctx)
	done := make(chan fixtureOutcome, 1)
	go func() {
		result := fixtureOutcome{}
		defer func() {
			if failure := recover(); failure != nil {
				result.failure = failure
			}
			done <- result
		}()
		result.value = operation(execution)
	}()
	var timer *time.Timer
	var elapsed <-chan time.Time
	if timeout > 0 {
		timer = time.NewTimer(timeout)
		elapsed = timer.C
		defer timer.Stop()
	}
	message := "fixture phase cancelled"
	select {
	case result := <-done:
		result.release = cancel
		return result
	case <-elapsed:
		message = fmt.Sprintf("fixture phase timed out after %s", timeout)
	case <-ctx.Done():
	}
	cancel()
	select {
	case result := <-done:
		if result.failure != nil {
			if _, cancelled := result.failure.(cancelled); !cancelled {
				message += "\nwhile cancelling: " + fmt.Sprint(result.failure)
			}
		}
		return fixtureOutcome{value: result.value, failure: message}
	case <-time.After(testCancelGrace):
		return fixtureOutcome{failure: message + " and did not stop when cancelled; further fixture use and teardown are unsafe", abandoned: true}
	}
}

func (s *fixtureState) hook(ctx *Execution, name string) Value {
	return Invoke(ctx, Bind(s.instance, "@std/TestHooks", name, s.definition.Scope), nil)
}

func (s *fixtureState) setup(timeout time.Duration) (string, fixtureOutcome) {
	result := fixturePhase(s.owner, timeout, func(ctx *Execution) Value {
		if err := ctx.Host.initialize(); err != nil {
			return Panic(err.Error())
		}
		return Invoke(ctx, s.definition.Create, nil)
	})
	if result.release != nil {
		s.retained = append(s.retained, result.release)
	}
	if result.failure != nil {
		s.failed = true
		if result.value != nil {
			s.instance = result.value
			s.created = true
		}
		s.poisoned.Store(result.abandoned)
		return "make_fixture", result
	}
	s.instance, s.created = result.value, true
	result = fixturePhase(s.owner, timeout, func(ctx *Execution) Value { return s.hook(ctx, "before_all") })
	if result.release != nil {
		s.retained = append(s.retained, result.release)
	}
	s.failed = result.failure != nil
	s.poisoned.Store(result.abandoned)
	return "before_all", result
}

func closeTestOwner(ctx *Execution) {
	defer Cleanup(ctx, hostValue(ctx, "stdin"))
	defer Cleanup(ctx, hostValue(ctx, "stdout"))
	defer Cleanup(ctx, hostValue(ctx, "stderr"))
	defer Cleanup(ctx, hostValue(ctx, "network"))
	defer FinishExecution(ctx)
}

func (s *fixtureState) shutdown(timeout time.Duration) fixtureOutcome {
	cleanupContext, cancel := context.WithCancel(context.Background())
	defer cancel()
	cleanupOwner := inherit(s.owner, cleanupContext)
	result := fixturePhase(cleanupOwner, timeout, func(ctx *Execution) Value {
		// Cleanup also runs when after_all itself faults.
		defer closeTestOwner(ctx)
		if s.created {
			return s.hook(ctx, "after_all")
		}
		return Unit{}
	})
	if result.release != nil {
		result.release()
	}
	if !result.abandoned {
		for _, release := range s.retained {
			release()
		}
		s.cancel()
	}
	return result
}

func testCleanupFailure(primary, cleanup any) any {
	if skip, ok := cleanup.(testSkip); ok {
		cleanup = Fault{Message: "after_each cannot skip a test: " + skip.Reason}
	}
	if primary == nil {
		return cleanup
	}
	if cleanup == nil {
		return primary
	}
	switch cleanup.(type) {
	case testSkip, cancelled:
		return primary
	}
	if fault, ok := primary.(Fault); ok {
		fault.Secondary = append(fault.Secondary, fmt.Sprint(cleanup))
		return fault
	}
	return cleanup
}

func (s *fixtureState) test(test Test) Test {
	original := test.Run
	test.Run = NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) (value Value) {
		defer func() {
			failure := recover()
			if s.poisoned.Load() {
				if failure != nil {
					panic(failure)
				}
				return
			}
			// Body-owned child work must stop before teardown mutates shared state.
			var joined any
			func() { defer func() { joined = recover() }(); FinishExecution(ctx) }()
			failure = testCleanupFailure(failure, joined)
			if s.poisoned.Load() {
				if failure != nil {
					panic(failure)
				}
				return
			}
			var cleanup any
			func() { defer func() { cleanup = recover() }(); s.hook(Shield(ctx), "after_each") }()
			if failure = testCleanupFailure(failure, cleanup); failure != nil {
				panic(failure)
			}
		}()
		s.hook(ctx, "before_each")
		return Invoke(ctx, original, []Argument{{Name: "fixture", Value: s.instance}})
	})
	return test
}

func testFailureText(failure any) string {
	if _, ok := failure.(cancelled); ok {
		return "operation cancelled"
	}
	return fmt.Sprint(failure)
}
