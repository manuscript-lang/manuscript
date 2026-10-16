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

type testFixtureValue struct{ hooks map[string]func(*Execution) }

func (f testFixtureValue) call(ctx *Execution, name string) Unit {
	if hook := f.hooks[name]; hook != nil {
		hook(ctx)
	}
	return Unit{}
}
func (f testFixtureValue) BeforeAll(ctx *Execution) Unit  { return f.call(ctx, "before_all") }
func (f testFixtureValue) BeforeEach(ctx *Execution) Unit { return f.call(ctx, "before_each") }
func (f testFixtureValue) AfterEach(ctx *Execution) Unit  { return f.call(ctx, "after_each") }
func (f testFixtureValue) AfterAll(ctx *Execution) Unit   { return f.call(ctx, "after_all") }

func fixtureForTest(t *testing.T, hooks map[string]func(*Execution)) (*TestFixture, func(*Execution) Unit) {
	t.Helper()
	fixture := &TestFixture{File: t.Name(), Create: func(ctx *Execution) TestHooks {
		if hook := hooks["make_fixture"]; hook != nil {
			hook(ctx)
		}
		return testFixtureValue{hooks}
	}}
	return fixture, func(*Execution) Unit { return Unit{} }
}

func TestFileFixtureKeepsOwnerAndTestHostsSeparate(t *testing.T) {
	made, before, after, closed := 0, 0, 0, 0
	var owner *Execution
	fixture, body := fixtureForTest(t, map[string]func(*Execution){
		"make_fixture": func(ctx *Execution) { made++; owner = ctx },
		"before_each": func(ctx *Execution) {
			before++
			if owner.Context.Err() != nil || owner.State.Host == ctx.State.Host {
				t.Error("fixture owner expired or test hosts shared")
			}
		},
		"after_each": func(*Execution) { after++ },
		"after_all":  func(*Execution) { closed++ },
	})
	tests := []Test{{Name: "first", Run: unitRun(body), Fixture: fixture}, {Name: "second", Run: unitRun(body), Fixture: fixture}}
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
			fixture, body := fixtureForTest(t, map[string]func(*Execution){phase: func(*Execution) { calls++; Raise("setup broke") }, "after_all": func(*Execution) { closed++ }})
			path := filepath.Join(t.TempDir(), "events")
			file, err := os.Create(path)
			if err != nil {
				t.Fatal(err)
			}
			reporter := &testReporter{file: file}
			status := runTestsWith([]Test{{Name: "one", Run: unitRun(body), Fixture: fixture}, {Name: "two", Run: unitRun(body), Fixture: fixture}}, TestOptions{}, nil, reporter)
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
	body := func(ctx *Execution) Unit {
		cancel()
		<-ctx.Context.Done()
		return CheckCancelled(ctx)
	}
	if status := runTestsContext([]Test{{Name: "cancelled", Run: unitRun(body), Fixture: fixture}, {Name: "later", Run: unitRun(body), Fixture: fixture}}, TestOptions{Timeout: time.Second}, nil, nil, ctx); status == 0 || !closed {
		t.Fatalf("status %d closed %v", status, closed)
	}
}

func TestFileFixtureTimeoutDoesNotReuseUnjoinedState(t *testing.T) {
	release, finished := make(chan struct{}), make(chan struct{})
	defer func() { close(release); <-finished }()
	closed, ranLater := false, false
	fixture, _ := fixtureForTest(t, map[string]func(*Execution){"after_all": func(*Execution) { closed = true }})
	body := func(*Execution) Unit { <-release; close(finished); return Unit{} }
	later := func(*Execution) Unit { ranLater = true; return Unit{} }
	status := RunTestsWith([]Test{{Name: "stuck", Run: unitRun(body), Fixture: fixture}, {Name: "later", Run: unitRun(later), Fixture: fixture}}, TestOptions{Timeout: 10 * time.Millisecond})
	if status == 0 || closed || ranLater {
		t.Fatalf("status %d closed %v later %v", status, closed, ranLater)
	}
}

func TestFileFixtureTimeoutRetainsCleanupFault(t *testing.T) {
	fixture, _ := fixtureForTest(t, map[string]func(*Execution){"after_each": func(*Execution) { Raise("cleanup failed") }})
	state := &fixtureState{definition: fixture, hooks: testFixtureValue{map[string]func(*Execution){"after_each": func(*Execution) { Raise("cleanup failed") }}}}
	body := func(ctx *Execution) Unit { <-ctx.Context.Done(); return CheckCancelled(ctx) }
	failure := runTest(state.test(Test{Name: "timeout", Run: unitRun(body)}), 10*time.Millisecond, nil)
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
	body := func(ctx *Execution) Unit {
		group := NewTaskGroup(None[Duration]())
		started := make(chan struct{})
		TaskGroup_Start(ctx, group, func(child *Execution) Unit {
			close(started)
			<-child.Context.Done()
			joined.Store(true)
			return Unit{}
		})
		<-started
		return Unit{}
	}
	if status := RunTestsWith([]Test{{Name: "joins", Run: unitRun(body), Fixture: fixture}}, TestOptions{Timeout: time.Second}); status != 0 {
		t.Fatal(status)
	}
}

func TestFileFixtureAbandonedJoinDoesNotRunAfterEach(t *testing.T) {
	var afterEach atomic.Bool
	state := &fixtureState{hooks: testFixtureValue{map[string]func(*Execution){"after_each": func(*Execution) { afterEach.Store(true) }}}}
	release, started, finished := make(chan struct{}), make(chan struct{}), make(chan struct{})
	body := func(ctx *Execution) Unit {
		group := NewTaskGroup(None[Duration]())
		TaskGroup_Start(ctx, group, func(*Execution) Unit { close(started); <-release; return Unit{} })
		<-started
		return Unit{}
	}
	wrapped := state.test(Test{Name: "join", Run: unitRun(body)})
	test := Test{Name: "join", Run: func(ctx *Execution) Result[Unit, Error] { defer close(finished); return wrapped.Run(ctx) }}
	failure := runTest(test, 10*time.Millisecond, nil)
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
