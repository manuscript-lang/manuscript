package msruntime

import (
	"context"
	"fmt"
	"sync/atomic"
	"time"
)

// TestFixture is one checked, file-local make_fixture factory. Create builds
// the instance, publishes it to the file's tests, and returns it as TestHooks.
type TestFixture struct {
	File   string
	Create func(*Execution) TestHooks
}

type fixtureState struct {
	definition      *TestFixture
	owner           *Execution
	cancel          context.CancelFunc
	hooks           TestHooks
	created, failed bool
	poisoned        atomic.Bool
	retained        []context.CancelFunc
}

type fixtureOutcome struct {
	value     TestHooks
	failure   any
	abandoned bool
	release   context.CancelFunc
}

// fixturePhase keeps successful creation contexts alive until file teardown.
// A timeout cancels only this phase; teardown gets its own bounded context.
func fixturePhase(owner *Execution, timeout time.Duration, operation func(*Execution) TestHooks) fixtureOutcome {
	ctx, cancel := context.WithCancel(owner.Context)
	execution := owner.child(ctx)
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

func (s *fixtureState) setup(timeout time.Duration) (string, fixtureOutcome) {
	result := fixturePhase(s.owner, timeout, s.definition.Create)
	if result.release != nil {
		s.retained = append(s.retained, result.release)
	}
	if result.failure != nil {
		s.failed = true
		if result.value != nil {
			s.hooks = result.value
			s.created = true
		}
		s.poisoned.Store(result.abandoned)
		return "make_fixture", result
	}
	s.hooks, s.created = result.value, true
	result = fixturePhase(s.owner, timeout, func(ctx *Execution) TestHooks { s.hooks.BeforeAll(ctx); return nil })
	if result.release != nil {
		s.retained = append(s.retained, result.release)
	}
	s.failed = result.failure != nil
	s.poisoned.Store(result.abandoned)
	return "before_all", result
}

func (s *fixtureState) shutdown(timeout time.Duration) fixtureOutcome {
	cleanupContext, cancel := context.WithCancel(context.Background())
	defer cancel()
	cleanupOwner := s.owner.child(cleanupContext)
	result := fixturePhase(cleanupOwner, timeout, func(ctx *Execution) TestHooks {
		// Cleanup also runs when after_all itself faults.
		if hostShutdown != nil {
			defer Cleanup(ctx, hostShutdown)
		}
		defer FinishExecution(ctx)
		if s.created {
			s.hooks.AfterAll(ctx)
		}
		return nil
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
	test.Run = func(ctx *Execution) (value Unit) {
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
			func() { defer func() { cleanup = recover() }(); s.hooks.AfterEach(Shield(ctx)) }()
			if failure = testCleanupFailure(failure, cleanup); failure != nil {
				panic(failure)
			}
		}()
		s.hooks.BeforeEach(ctx)
		return original(ctx)
	}
	return test
}

func testFailureText(failure any) string {
	if _, ok := failure.(cancelled); ok {
		return "operation cancelled"
	}
	return fmt.Sprint(failure)
}
