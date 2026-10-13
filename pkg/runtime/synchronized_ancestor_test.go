package msruntime

import (
	"context"
	"strings"
	"sync"
	"testing"
	"time"
)

// Observes entry into a cancellable wait without using scheduling delays.
// Install it on the joining/waiting call, not the group's construction context.
type synchronizedWaitContext struct {
	context.Context
	entered chan struct{}
	once    sync.Once
}

func (c *synchronizedWaitContext) Done() <-chan struct{} {
	c.once.Do(func() { close(c.entered) })
	return c.Context.Done()
}

type synchronizedCallOutcome struct {
	value   Value
	failure any
}

func synchronizedCall(call func() Value) <-chan synchronizedCallOutcome {
	done := make(chan synchronizedCallOutcome, 1)
	go func() {
		outcome := synchronizedCallOutcome{}
		outcome.failure = recovered(func() { outcome.value = call() })
		done <- outcome
	}()
	return done
}

func awaitSynchronizedSignal(t *testing.T, signal <-chan struct{}) {
	t.Helper()
	select {
	case <-signal:
	case <-time.After(2 * time.Second):
		t.Fatal("synchronization barrier was not reached")
	}
}

func awaitSynchronizedCall(t *testing.T, done <-chan synchronizedCallOutcome) synchronizedCallOutcome {
	t.Helper()
	select {
	case outcome := <-done:
		return outcome
	case <-time.After(2 * time.Second):
		t.Fatal("synchronization call remained blocked")
		return synchronizedCallOutcome{}
	}
}

func requireSynchronizedAncestorCrash(t *testing.T, outcome synchronizedCallOutcome) {
	t.Helper()
	if outcome.failure != nil {
		t.Fatal("join faulted instead of reporting task failure", outcome.failure)
	}
	result := outcome.value.(Alternative)
	if result.Tag != "error" {
		t.Fatal("expected ancestor lock fault", result)
	}
	cause := result.Fields[0].(Alternative)
	if cause.Tag != "Crashed" || !strings.Contains(cause.Fields[1].(string), "lock held by this operation or an ancestor") {
		t.Fatal("unexpected task failure", cause)
	}
}

func TestSynchronizedReentryAcrossExecutionViews(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	defer guard.close()
	for name, caller := range map[string]*Execution{
		"same operation":      root,
		"shielded operation":  Shield(root),
		"inherited view":      inherit(root, root.Context),
		"nested descendant":   newExecution(newExecution(root, root.Context), root.Context),
		"shielded descendant": Shield(newExecution(root, root.Context)),
	} {
		t.Run(name, func(t *testing.T) {
			outcome := awaitSynchronizedCall(t, synchronizedCall(func() Value {
				locked := lockCell(caller, cell)
				locked.close()
				return Unit{}
			}))
			if fault, ok := outcome.failure.(Fault); !ok || !strings.Contains(fault.Message, "ancestor") {
				t.Fatal("reentrant lock was not rejected", outcome)
			}
		})
	}
}

func TestSynchronizedAncestorCloseJoinsShieldedCleanup(t *testing.T) {
	for _, boundary := range []string{"group close", "execution exit", "scheduler close"} {
		t.Run(boundary, func(t *testing.T) {
			root := RootExecution()
			cell := synchronizedInt()
			guard := lockCell(root, cell)
			entered := make(chan struct{})
			callback := NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
				defer func() {
					locked := lockCell(Shield(child), cell)
					locked.close()
				}()
				close(entered)
				<-child.Context.Done()
				CheckCancelled(child)
				return Unit{}
			})
			var closeWork func() Value
			reported := make(chan Value, 1)
			if boundary == "scheduler close" {
				reporter := NewFunction([]string{"failure"}, "Unit", func(_ *Execution, args []Value) Value {
					reported <- args[0]
					return Unit{}
				})
				service := NewScheduler(root, []Argument{{"reporter", reporter}}).(*Scheduler)
				service.start(root, callback)
				closeWork = func() Value { service.close(root); return Unit{} }
			} else {
				group := NewTaskGroup(root, nil).(*TaskGroup)
				groupTask(root, group, callback)
				if boundary == "execution exit" {
					closeWork = func() Value { FinishExecution(root); return Unit{} }
				} else {
					closeWork = func() Value { group.close(Shield(root)); return Unit{} }
				}
			}
			t.Cleanup(func() {
				guard.close()
				// If the test times out, release before retrying shutdown so a
				// regressed ancestor check cannot leave test goroutines blocked.
				if failure := recovered(func() { closeWork() }); failure != nil && !t.Failed() {
					t.Error(failure)
				}
			})
			awaitSynchronizedSignal(t, entered)
			outcome := awaitSynchronizedCall(t, synchronizedCall(closeWork))
			if boundary == "scheduler close" {
				if outcome.failure != nil {
					t.Fatal(outcome.failure)
				}
				select {
				case value := <-reported:
					failure := value.(Alternative)
					if failure.Tag != "Crashed" || !strings.Contains(failure.Fields[1].(string), "ancestor") {
						t.Fatal(failure)
					}
				default:
					t.Fatal("scheduler close returned before reporting cleanup failure")
				}
			} else if fault, ok := outcome.failure.(Fault); !ok || !strings.Contains(fault.Message, "ancestor") {
				t.Fatal("shutdown did not report the shielded ancestor-lock fault", outcome)
			}
		})
	}
}

// Characterizes #148 under the current documented conservative contract.
// There is no ancestor join while the child attempts acquisition. A future
// actual-cycle policy must change the overlapping case to wait and return 7.
func TestSynchronizedAncestorContentionCurrentContract(t *testing.T) {
	for _, overlap := range []bool{false, true} {
		name := "released before child acquisition"
		if overlap {
			name = "held while child runs without a parent join"
		}
		t.Run(name, func(t *testing.T) {
			root := RootExecution()
			cell := synchronizedInt()
			guard := lockCell(root, cell)
			group := NewTaskGroup(root, nil).(*TaskGroup)
			acquire := make(chan struct{})
			var release sync.Once
			// Release the lock and callback barrier before any cleanup join, even
			// when a regressed guard lets the callback block indefinitely.
			t.Cleanup(func() {
				guard.close()
				release.Do(func() { close(acquire) })
				if failure := recovered(func() { group.close(Shield(root)) }); failure != nil && !t.Failed() {
					t.Error(failure)
				}
			})
			task := groupTask(root, group, NewFunction(nil, "Int", func(child *Execution, _ []Value) Value {
				<-acquire
				locked := lockCell(child, cell)
				defer locked.close()
				return Invoke(child, locked.Operation("get"), nil)
			}))
			Invoke(root, guard.Operation("set"), []Argument{{"value", int64(7)}})
			if !overlap {
				guard.close()
			}
			release.Do(func() { close(acquire) })
			// Observe completion first; invoking join here would obscure the
			// distinction between ordinary contention and a real wait cycle.
			awaitSynchronizedSignal(t, task.done)
			guard.close()
			outcome := awaitSynchronizedCall(t, synchronizedCall(func() Value { return taskResult(root, task) }))
			if overlap {
				requireSynchronizedAncestorCrash(t, outcome)
			} else if outcome.failure != nil || outcome.value.(Alternative).Tag != "ok" || outcome.value.(Alternative).Fields[0] != int64(7) {
				t.Fatal("released ancestor lock did not deliver the committed value", outcome)
			}
		})
	}
}

// Covers both orders that an actual-cycle detector must handle: acquisition
// before join, and join before acquisition. An ancestor-only check currently
// rejects the first lock attempt; removing it would hang both cases.
func TestSynchronizedAncestorJoinLockCycle(t *testing.T) {
	for _, boundary := range []string{"task", "group"} {
		for _, joinFirst := range []bool{false, true} {
			order := "lock first"
			if joinFirst {
				order = "join first"
			}
			t.Run(boundary+"/"+order, func(t *testing.T) {
				root := RootExecution()
				cell := synchronizedInt()
				guard := lockCell(root, cell)
				group := NewTaskGroup(root, nil).(*TaskGroup)
				acquire := make(chan struct{})
				var release sync.Once
				t.Cleanup(func() {
					guard.close()
					release.Do(func() { close(acquire) })
					if failure := recovered(func() { group.close(Shield(root)) }); failure != nil && !t.Failed() {
						t.Error(failure)
					}
				})
				task := groupTask(root, group, NewFunction(nil, "Int", func(child *Execution, _ []Value) Value {
					<-acquire
					locked := lockCell(child, cell)
					defer locked.close()
					return int64(1)
				}))
				waiting := &synchronizedWaitContext{Context: root.Context, entered: make(chan struct{})}
				join := func() Value {
					caller := inherit(root, waiting)
					if boundary == "task" {
						return taskResult(caller, task)
					}
					return groupResult(caller, group)
				}
				var done <-chan synchronizedCallOutcome
				if joinFirst {
					done = synchronizedCall(join)
					awaitSynchronizedSignal(t, waiting.entered)
					release.Do(func() { close(acquire) })
				} else {
					release.Do(func() { close(acquire) })
					awaitSynchronizedSignal(t, task.done)
					done = synchronizedCall(join)
				}
				requireSynchronizedAncestorCrash(t, awaitSynchronizedCall(t, done))
			})
		}
	}
}

func TestSynchronizedGuardAliasReleasesWhileOwnerJoins(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	group := NewTaskGroup(root, nil).(*TaskGroup)
	release := make(chan struct{})
	var allow sync.Once
	t.Cleanup(func() {
		guard.close()
		allow.Do(func() { close(release) })
		group.close(Shield(root))
	})
	task := groupTask(root, group, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
		<-release
		// A different operation may release an alias of the owner's guard.
		// Being blocked in a join does not make the owner the only possible
		// source of lock release; a cycle policy must account for this fact.
		Invoke(child, guard.Operation("close"), nil)
		return Unit{}
	}))
	waiting := &synchronizedWaitContext{Context: root.Context, entered: make(chan struct{})}
	done := synchronizedCall(func() Value { return taskResult(inherit(root, waiting), task) })
	awaitSynchronizedSignal(t, waiting.entered)
	allow.Do(func() { close(release) })
	outcome := awaitSynchronizedCall(t, done)
	if outcome.failure != nil || outcome.value.(Alternative).Tag != "ok" {
		t.Fatal("guard alias could not release while its owner joined", outcome)
	}
	next := lockCell(root, cell)
	next.close()
}

func TestSynchronizedAncestorLockDuringCancelledCleanup(t *testing.T) {
	base := RootExecution()
	parentContext, cancel := context.WithCancel(base.Context)
	defer cancel()
	root := inherit(base, parentContext)
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	group := NewTaskGroup(root, nil).(*TaskGroup)
	t.Cleanup(func() {
		guard.close()
		cancel()
		if failure := recovered(func() { group.close(Shield(root)) }); failure != nil && !t.Failed() {
			t.Error(failure)
		}
	})
	entered := make(chan struct{})
	task := groupTask(root, group, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
		defer func() {
			locked := lockCell(Shield(child), cell)
			locked.close()
		}()
		close(entered)
		<-child.Context.Done()
		CheckCancelled(child)
		return Unit{}
	}))
	awaitSynchronizedSignal(t, entered)
	cancel()
	// Shielded joining still depends on child cleanup. Cancellation cannot
	// dissolve this lock/join cycle, nor may it forcibly release the guard.
	outcome := awaitSynchronizedCall(t, synchronizedCall(func() Value { return taskResult(Shield(root), task) }))
	requireSynchronizedAncestorCrash(t, outcome)
	cell.mu.Lock()
	held := cell.holder == guard
	cell.mu.Unlock()
	if !held {
		t.Fatal("parent cancellation released an executing critical section")
	}
}

func TestSynchronizedBlockedCancellationRacesRelease(t *testing.T) {
	for range 100 {
		root := RootExecution()
		cell := synchronizedInt()
		holder := newExecution(root, root.Context)
		guard := lockCell(holder, cell)
		waitContext, cancel := context.WithCancel(root.Context)
		t.Cleanup(cancel)
		t.Cleanup(guard.close)
		waiting := &synchronizedWaitContext{Context: waitContext, entered: make(chan struct{})}
		waiter := newExecution(root, waiting) // Independent of the holder.
		done := synchronizedCall(func() Value { return lockCell(waiter, cell) })
		awaitSynchronizedSignal(t, waiting.entered)
		var racers sync.WaitGroup
		racers.Add(2)
		go func() { defer racers.Done(); cancel() }()
		go func() { defer racers.Done(); guard.close() }()
		racers.Wait()
		outcome := awaitSynchronizedCall(t, done)
		if outcome.failure == nil {
			outcome.value.(*SynchronizedGuard).close()
		} else if _, ok := outcome.failure.(cancelled); !ok {
			t.Fatal("cancellation/release race produced a programming fault", outcome.failure)
		}
		cell.mu.Lock()
		held := cell.holder != nil
		cell.mu.Unlock()
		if held {
			t.Fatal("cancellation/release race leaked an acquisition")
		}
		// A completed race leaves the cell available for the next operation.
		next := lockCell(root, cell)
		next.close()
	}
}

// Cancel immediately after the delivery checkpoint samples an active context.
// A later check must not unwind without disposing the already acquired guard.
type synchronizedDeliveryCancelContext struct {
	context.Context
	cell   *Synchronized
	cancel context.CancelFunc
}

func (c *synchronizedDeliveryCancelContext) Err() error {
	err := c.Context.Err()
	c.cell.mu.Lock()
	acquired := c.cell.holder != nil
	c.cell.mu.Unlock()
	if acquired && err == nil {
		c.cancel()
	}
	return err
}

func TestSynchronizedCancellationAtDeliveryCheckpoint(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	active, cancel := context.WithCancel(root.Context)
	defer cancel()
	caller := newExecution(root, &synchronizedDeliveryCancelContext{Context: active, cell: cell, cancel: cancel})
	var guard *SynchronizedGuard
	failure := recovered(func() { guard = lockCell(caller, cell) })
	if failure == nil {
		// Delivery won its checkpoint. Later cancellation belongs to caller
		// unwinding, so the delivered guard must remain usable by cleanup.
		Cleanup(caller, guard)
	} else if _, ok := failure.(cancelled); !ok {
		t.Fatal(failure)
	}
	cell.mu.Lock()
	leaked := cell.holder
	cell.mu.Unlock()
	if leaked != nil {
		leaked.close()
		t.Fatal("cancellation after the disposal check leaked an undelivered guard")
	}
	next := lockCell(root, cell)
	next.close()
}
