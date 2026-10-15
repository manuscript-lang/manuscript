package msruntime

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/manuscript-lang/manuscript/internal/nativeabi"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func fixtureForTest(t *testing.T, hooks map[string]func(*Execution)) (*TestFixture, func(*Execution, []Value) Value) {
	t.Helper()
	typ := "test/" + t.Name()
	for _, name := range []string{"before_all", "before_each", "after_each", "after_all"} {
		Register(Implementation{Receiver: typ, Contract: "@std/TestHooks", Name: name, Build: func(receiver Value, _ map[string]string, _ map[string]TypeScope) Function {
			return NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
				if hook := hooks[name]; hook != nil {
					hook(ctx)
				}
				return Unit{}
			})
		}})
	}
	fixture := &TestFixture{File: t.Name(), Create: NewFunction(nil, typ, func(ctx *Execution, _ []Value) Value {
		if hook := hooks["make_fixture"]; hook != nil {
			hook(ctx)
		}
		return Record{Type: typ, Fields: map[string]Value{}}
	})}
	body := func(*Execution, []Value) Value { return Unit{} }
	return fixture, body
}

func TestFileFixtureKeepsOwnerAndTestHostsSeparate(t *testing.T) {
	made, before, after, closed := 0, 0, 0, 0
	var owner *Execution
	fixture, body := fixtureForTest(t, map[string]func(*Execution){
		"make_fixture": func(ctx *Execution) { made++; owner = ctx },
		"before_each": func(ctx *Execution) {
			before++
			if owner.Context.Err() != nil || owner.Host == ctx.Host {
				t.Error("fixture owner expired or test hosts shared")
			}
		},
		"after_each": func(*Execution) { after++ },
		"after_all":  func(*Execution) { closed++ },
	})
	tests := []Test{{Name: "first", Run: NewFunction([]string{"fixture"}, "Unit", body), Fixture: fixture}, {Name: "second", Run: NewFunction([]string{"fixture"}, "Unit", body), Fixture: fixture}}
	if status := RunTestsWith(tests, TestOptions{Repeat: 2, Shuffle: true, Seed: 4}); status != 0 {
		t.Fatal(status)
	}
	if made != 1 || before != 4 || after != 4 || closed != 1 || owner.Context.Err() == nil {
		t.Fatalf("lifecycle %d %d %d %d cancelled %v", made, before, after, closed, owner.Context.Err())
	}
}

func TestFileFixtureSetupFailuresAreReportedAndNotRetried(t *testing.T) {
	for _, phase := range []string{"make_fixture", "before_all"} {
		t.Run(phase, func(t *testing.T) {
			calls, closed := 0, 0
			fixture, body := fixtureForTest(t, map[string]func(*Execution){phase: func(*Execution) { calls++; Panic("setup broke") }, "after_all": func(*Execution) { closed++ }})
			path := filepath.Join(t.TempDir(), "events")
			file, err := os.Create(path)
			if err != nil {
				t.Fatal(err)
			}
			reporter := &testReporter{file: file}
			status := runTestsWith([]Test{{Name: "one", Run: NewFunction(nil, "Unit", body), Fixture: fixture}, {Name: "two", Run: NewFunction(nil, "Unit", body), Fixture: fixture}}, TestOptions{}, reporter)
			reporter.close()
			data, _ := os.ReadFile(path)
			if status != 1 || calls != 1 || closed != map[bool]int{true: 1, false: 0}[phase == "before_all"] || strings.Contains(string(data), `"event":"run"`) {
				t.Fatalf("status %d calls %d closed %d events %s", status, calls, closed, data)
			}
			decoder := json.NewDecoder(strings.NewReader(string(data)))
			var events []nativeabi.TestEvent
			for decoder.More() {
				var event nativeabi.TestEvent
				if err := decoder.Decode(&event); err != nil {
					t.Fatal(err)
				}
				events = append(events, event)
			}
			if len(events) != 3 || events[1].Phase != phase || events[2].Reason != "fixture_error" {
				t.Fatalf("events %+v", events)
			}
		})
	}
}

func TestFileFixtureCancellationRunsTeardown(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	closed := false
	fixture, _ := fixtureForTest(t, map[string]func(*Execution){"after_all": func(ctx *Execution) {
		if ctx.Context.Err() != nil {
			t.Error("teardown inherited cancellation")
		}
		closed = true
	}})
	body := NewFunction([]string{"fixture"}, "Unit", func(ctx *Execution, _ []Value) Value {
		cancel()
		<-ctx.Context.Done()
		CheckCancelled(ctx)
		return Unit{}
	})
	if status := runTestsContext([]Test{{Name: "cancelled", Run: body, Fixture: fixture}, {Name: "later", Run: body, Fixture: fixture}}, TestOptions{Timeout: time.Second}, nil, ctx); status == 0 || !closed {
		t.Fatalf("status %d closed %v", status, closed)
	}
}

func TestFileFixtureTimeoutDoesNotReuseUnjoinedState(t *testing.T) {
	release, finished := make(chan struct{}), make(chan struct{})
	defer func() { close(release); <-finished }()
	closed, ranLater := false, false
	fixture, _ := fixtureForTest(t, map[string]func(*Execution){"after_all": func(*Execution) { closed = true }})
	body := NewFunction([]string{"fixture"}, "Unit", func(*Execution, []Value) Value { <-release; close(finished); return Unit{} })
	later := NewFunction([]string{"fixture"}, "Unit", func(*Execution, []Value) Value { ranLater = true; return Unit{} })
	status := RunTestsWith([]Test{{Name: "stuck", Run: body, Fixture: fixture}, {Name: "later", Run: later, Fixture: fixture}}, TestOptions{Timeout: 10 * time.Millisecond})
	if status == 0 || closed || ranLater {
		t.Fatalf("status %d closed %v later %v", status, closed, ranLater)
	}
}

func TestFileFixtureTimeoutRetainsCleanupFault(t *testing.T) {
	fixture, _ := fixtureForTest(t, map[string]func(*Execution){"after_each": func(*Execution) { Panic("cleanup failed") }})
	state := &fixtureState{definition: fixture, instance: Record{Type: "test/" + t.Name(), Fields: map[string]Value{}}}
	body := NewFunction([]string{"fixture"}, "Unit", func(ctx *Execution, _ []Value) Value { <-ctx.Context.Done(); CheckCancelled(ctx); return Unit{} })
	failure := runTest(state.test(Test{Name: "timeout", Run: body}), 10*time.Millisecond)
	if !strings.Contains(fmt.Sprint(failure), "timed out") || !strings.Contains(fmt.Sprint(failure), "cleanup failed") {
		t.Fatalf("lost cleanup fault: %v", failure)
	}
}

func TestFileFixtureJoinsTestWorkBeforeAfterEach(t *testing.T) {
	var joined atomic.Bool
	fixture, _ := fixtureForTest(t, map[string]func(*Execution){"after_each": func(*Execution) {
		if !joined.Load() {
			t.Error("after_each ran before test workers joined")
		}
	}})
	body := NewFunction([]string{"fixture"}, "Unit", func(ctx *Execution, _ []Value) Value {
		group := NewTaskGroup(ctx, nil).(*TaskGroup)
		started := make(chan struct{})
		group.start(ctx, "Unit", NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
			close(started)
			<-child.Context.Done()
			joined.Store(true)
			return Unit{}
		}))
		<-started
		return Unit{}
	})
	if status := RunTestsWith([]Test{{Name: "joins", Run: body, Fixture: fixture}}, TestOptions{Timeout: time.Second}); status != 0 {
		t.Fatal(status)
	}
}

func TestFileFixtureAbandonedJoinDoesNotRunAfterEach(t *testing.T) {
	var afterEach atomic.Bool
	definition, _ := fixtureForTest(t, map[string]func(*Execution){"after_each": func(*Execution) { afterEach.Store(true) }})
	state := &fixtureState{definition: definition, instance: Record{Type: "test/" + t.Name(), Fields: map[string]Value{}}}
	release, started, finished := make(chan struct{}), make(chan struct{}), make(chan struct{})
	body := NewFunction([]string{"fixture"}, "Unit", func(ctx *Execution, _ []Value) Value {
		group := NewTaskGroup(ctx, nil).(*TaskGroup)
		group.start(ctx, "Unit", NewFunction(nil, "Unit", func(*Execution, []Value) Value { close(started); <-release; return Unit{} }))
		<-started
		return Unit{}
	})
	wrapped := state.test(Test{Name: "join", Run: body})
	test := Test{Name: "join", Run: NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value { defer close(finished); return Invoke(ctx, wrapped.Run, nil) })}
	failure := runTest(test, 10*time.Millisecond)
	state.poisoned.Store(true)
	close(release)
	select {
	case <-finished:
	case <-time.After(time.Second):
		t.Fatal("test did not finish after worker release")
	}
	timeout, ok := failure.(testTimeout)
	if !ok || !timeout.abandoned || afterEach.Load() {
		t.Fatalf("failure %v after_each %v", failure, afterEach.Load())
	}
}
