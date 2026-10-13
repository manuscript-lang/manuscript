package msruntime

import (
	"context"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
)

func requireWorkWaitsClear(t *testing.T, root *Execution, nodes ...*workWaitNode) {
	t.Helper()
	workWaits.Lock()
	defer workWaits.Unlock()
	for _, node := range append(nodes, lifetimeWaitNode(root.Lifetime)) {
		if len(node.dependencies) != 0 {
			t.Error("completed work retained dependencies", len(node.dependencies))
		}
	}
	for wait := range workWaits.locks {
		if wait.lifetime == root.Lifetime || strictExecutionAncestor(root.Lifetime, wait.lifetime) {
			t.Error("completed work retained a lock waiter")
		}
	}
}

func TestSynchronizedSuccessfulTaskJoinDoesNotJoinSibling(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	group := NewTaskGroup(root, nil).(*TaskGroup)
	t.Cleanup(func() { guard.close(); group.close(Shield(root)) })
	blocked := make(chan struct{})
	sibling := groupTask(root, group, NewFunction(nil, "Int", func(child *Execution, _ []Value) Value {
		child = inherit(child, &synchronizedLockWaitContext{Context: child.Context, cell: cell, lifetime: child.Lifetime, entered: blocked})
		locked := lockCell(child, cell)
		defer locked.close()
		return int64(7)
	}))
	awaitSynchronizedSignal(t, blocked)
	fast := groupTask(root, group, NewFunction(nil, "Int", func(*Execution, []Value) Value { return int64(9) }))
	outcome := awaitSynchronizedCall(t, synchronizedCall(func() Value { return taskResult(root, fast) }))
	if outcome.failure != nil || outcome.value.(Alternative).Tag != "ok" || outcome.value.(Alternative).Fields[0] != int64(9) {
		t.Fatal("successful task join depended on a blocked sibling", outcome)
	}
	guard.close()
	outcome = awaitSynchronizedCall(t, synchronizedCall(func() Value { return taskResult(root, sibling) }))
	if outcome.failure != nil || outcome.value.(Alternative).Tag != "ok" {
		t.Fatal("unjoined sibling faulted", outcome)
	}
	group.close(root)
	requireWorkWaitsClear(t, root, &group.waits, &fast.waits, &sibling.waits)
}

func TestSynchronizedFailedTaskJoinIncludesSiblingCleanup(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	group := NewTaskGroup(root, nil).(*TaskGroup)
	t.Cleanup(func() {
		guard.close()
		if failure := recovered(func() { group.close(Shield(root)) }); failure != nil && !t.Failed() {
			t.Error(failure)
		}
	})
	entered, cleanupWaiting := make(chan struct{}), make(chan struct{})
	cleanupFault := make(chan any, 1)
	sibling := groupTask(root, group, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
		defer func() {
			shield := Shield(child)
			shield = inherit(shield, &synchronizedLockWaitContext{Context: shield.Context, cell: cell, lifetime: shield.Lifetime, entered: cleanupWaiting})
			failure := recovered(func() { locked := lockCell(shield, cell); locked.close() })
			cleanupFault <- failure
			if failure != nil {
				panic(failure)
			}
		}()
		close(entered)
		<-child.Context.Done()
		CheckCancelled(child)
		return Unit{}
	}))
	awaitSynchronizedSignal(t, entered)
	failed := groupTask(root, group, NewFunction(nil, "Unit", func(*Execution, []Value) Value { return Panic("first failure") }))
	awaitSynchronizedSignal(t, failed.done)
	awaitSynchronizedSignal(t, cleanupWaiting)
	outcome := awaitSynchronizedCall(t, synchronizedCall(func() Value { return taskResult(root, failed) }))
	if outcome.failure != nil {
		t.Fatal("failed task join faulted its caller", outcome.failure)
	}
	result := outcome.value.(Alternative)
	if result.Tag != "error" || result.Fields[0].(Alternative).Tag != "Crashed" || !strings.Contains(result.Fields[0].(Alternative).Fields[1].(string), "first failure") {
		t.Fatal("lost the first committed group fault", result)
	}
	select {
	case failure := <-cleanupFault:
		if fault, ok := failure.(Fault); !ok || !strings.Contains(fault.Message, "ancestor waiting") {
			t.Fatal("sibling cleanup was not included in failed-task join", failure)
		}
	default:
		t.Fatal("failed task join returned before sibling cleanup")
	}
	guard.close()
	group.close(root)
	requireWorkWaitsClear(t, root, &group.waits, &failed.waits, &sibling.waits)
}

func TestSynchronizedNestedAncestorCycle(t *testing.T) {
	for _, joinFirst := range []bool{false, true} {
		name := "lock first"
		if joinFirst {
			name = "join first"
		}
		t.Run(name, func(t *testing.T) {
			root := RootExecution()
			cell := synchronizedInt()
			guard := lockCell(root, cell)
			group := NewTaskGroup(root, nil).(*TaskGroup)
			acquire := make(chan struct{})
			var allow sync.Once
			t.Cleanup(func() {
				guard.close()
				allow.Do(func() { close(acquire) })
				if failure := recovered(func() { group.close(Shield(root)) }); failure != nil && !t.Failed() {
					t.Error(failure)
				}
			})
			lockWaiting, nestedWaiting := make(chan struct{}), make(chan struct{})
			groupTask(root, group, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
				nested := NewTaskGroup(child, nil).(*TaskGroup)
				defer nested.close(Shield(child))
				groupTask(child, nested, NewFunction(nil, "Unit", func(descendant *Execution, _ []Value) Value {
					<-acquire
					descendant = inherit(descendant, &synchronizedLockWaitContext{Context: descendant.Context, cell: cell, lifetime: descendant.Lifetime, entered: lockWaiting})
					locked := lockCell(descendant, cell)
					defer locked.close()
					return Unit{}
				}))
				caller := inherit(child, &synchronizedWaitContext{Context: child.Context, entered: nestedWaiting})
				outcome := groupResult(caller, nested)
				if outcome.Tag == "error" {
					return Panic(outcome.Fields[0].(Alternative).Fields[1].(string))
				}
				return Unit{}
			}))
			awaitSynchronizedSignal(t, nestedWaiting)
			var done <-chan synchronizedCallOutcome
			if joinFirst {
				waiting := &synchronizedWaitContext{Context: root.Context, entered: make(chan struct{})}
				done = synchronizedCall(func() Value { return groupResult(inherit(root, waiting), group) })
				awaitSynchronizedSignal(t, waiting.entered)
				allow.Do(func() { close(acquire) })
			} else {
				allow.Do(func() { close(acquire) })
				awaitSynchronizedSignal(t, lockWaiting)
				done = synchronizedCall(func() Value { return groupResult(root, group) })
			}
			requireSynchronizedAncestorCrash(t, awaitSynchronizedCall(t, done))
			guard.close()
			group.close(root)
			requireWorkWaitsClear(t, root, &group.waits)
		})
	}
}

func TestSynchronizedStaleLockDependency(t *testing.T) {
	for _, scenario := range []struct{ cancel, reacquire bool }{{false, false}, {true, false}, {false, true}} {
		cancelWait := scenario.cancel
		name := "release before join while waiter is unscheduled"
		if cancelWait {
			name = "cancellation before join while waiter is unscheduled"
		}
		if scenario.reacquire {
			name = "reacquired guard detects a fresh dependency"
		}
		t.Run(name, func(t *testing.T) {
			root := RootExecution()
			cell := synchronizedInt()
			guard := lockCell(root, cell)
			group := NewTaskGroup(root, nil).(*TaskGroup)
			resume := make(chan struct{})
			var allow sync.Once
			t.Cleanup(func() { guard.close(); allow.Do(func() { close(resume) }); group.close(Shield(root)) })
			registered := make(chan struct{})
			cancel := make(chan context.CancelFunc, 1)
			task := groupTask(root, group, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
				active, stop := context.WithCancel(child.Context)
				defer stop()
				cancel <- stop
				child = inherit(child, &synchronizedLockWaitContext{Context: active, cell: cell, lifetime: child.Lifetime, entered: registered, resume: resume})
				locked := lockCell(child, cell)
				defer locked.close()
				return Unit{}
			}))
			awaitSynchronizedSignal(t, registered)
			stop := <-cancel
			var next *SynchronizedGuard
			defer func() {
				if next != nil {
					next.close()
				}
			}()
			if cancelWait {
				stop()
			} else {
				guard.close()
				if scenario.reacquire {
					next = lockCell(root, cell)
					guard.close() // Stale alias cannot invalidate the new holder.
				}
			}
			waiting := &synchronizedWaitContext{Context: root.Context, entered: make(chan struct{})}
			done := synchronizedCall(func() Value { return taskResult(inherit(root, waiting), task) })
			awaitSynchronizedSignal(t, waiting.entered)
			allow.Do(func() { close(resume) })
			outcome := awaitSynchronizedCall(t, done)
			if outcome.failure != nil {
				t.Fatal(outcome.failure)
			}
			result := outcome.value.(Alternative)
			if scenario.reacquire {
				requireSynchronizedAncestorCrash(t, outcome)
				cell.mu.Lock()
				held := cell.holder == next
				cell.mu.Unlock()
				if !held {
					t.Fatal("stale guard released the new acquisition")
				}
				next.close()
			} else if cancelWait {
				if result.Tag != "error" || result.Fields[0].(Alternative).Tag != "Cancelled" {
					t.Fatal("cancelled stale wait became a programming fault", result)
				}
			} else if result.Tag != "ok" {
				t.Fatal("released stale wait became a programming fault", result)
			}
			guard.close()
			group.close(root)
			requireWorkWaitsClear(t, root, &group.waits, &task.waits)
		})
	}
}

func TestSynchronizedAliasBreakableCycleRemainsConservative(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	group := NewTaskGroup(root, nil).(*TaskGroup)
	release := make(chan struct{})
	var allow sync.Once
	t.Cleanup(func() { guard.close(); allow.Do(func() { close(release) }); group.close(Shield(root)) })
	blocked := make(chan struct{})
	waiter := groupTask(root, group, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
		child = inherit(child, &synchronizedLockWaitContext{Context: child.Context, cell: cell, lifetime: child.Lifetime, entered: blocked})
		locked := lockCell(child, cell)
		defer locked.close()
		return Unit{}
	}))
	groupTask(root, group, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
		<-release
		Invoke(Shield(child), guard.Operation("close"), nil)
		return Unit{}
	}))
	awaitSynchronizedSignal(t, blocked)
	done := synchronizedCall(func() Value { return groupResult(root, group) })
	awaitSynchronizedSignal(t, waiter.done) // Cycle accepted before alias release.
	allow.Do(func() { close(release) })
	requireSynchronizedAncestorCrash(t, awaitSynchronizedCall(t, done))
	group.close(root)
	requireWorkWaitsClear(t, root, &group.waits, &waiter.waits)
}

func TestSynchronizedSchedulerContentionUsesConstructionParent(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	service := NewScheduler(root, nil).(*Scheduler)
	t.Cleanup(func() { guard.close(); service.close(root) })
	blocked := make(chan struct{})
	read := make(chan Value, 1)
	// A foreign submitter does not replace the service's construction parent.
	result := service.start(RootExecution(), NewFunction(nil, "@std/Result[Unit][String]", func(child *Execution, _ []Value) Value {
		if child.Lifetime.parent != root.Lifetime {
			return Panic("scheduler work was reparented")
		}
		child = inherit(child, &synchronizedLockWaitContext{Context: child.Context, cell: cell, lifetime: child.Lifetime, entered: blocked})
		locked := lockCell(child, cell)
		defer locked.close()
		read <- Invoke(child, locked.Operation("get"), nil)
		return Alternative{"@std/Result[Unit][String]", "ok", []Value{Unit{}}}
	})).(Alternative)
	id := result.Fields[0].(OperationId)
	service.mu.Lock()
	job := service.active[id]
	service.mu.Unlock()
	awaitSynchronizedSignal(t, blocked)
	Invoke(root, guard.Operation("set"), []Argument{{"value", int64(7)}})
	guard.close()
	awaitSynchronizedSignal(t, job.done)
	if value := <-read; value != int64(7) {
		t.Fatal(value)
	}
	service.close(root)
	requireWorkWaitsClear(t, root, &service.waits, &job.waits)
}

func TestSynchronizedSchedulerRestartJoinsShieldedCleanup(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	reported := make(chan Value, 1)
	reporter := NewFunction([]string{"failure"}, "Unit", func(_ *Execution, args []Value) Value { reported <- args[0]; return Unit{} })
	service := NewScheduler(root, []Argument{{"reporter", reporter}}).(*Scheduler)
	t.Cleanup(func() { guard.close(); service.close(root) })
	entered := make(chan struct{})
	var calls atomic.Int64
	callback := NewFunction(nil, "@std/Result[Unit][String]", func(child *Execution, _ []Value) Value {
		if calls.Add(1) == 1 {
			defer func() { locked := lockCell(Shield(child), cell); locked.close() }()
			close(entered)
			<-child.Context.Done()
			CheckCancelled(child)
		}
		return Alternative{"@std/Result[Unit][String]", "ok", []Value{Unit{}}}
	})
	result := service.schedule(root, 0, false, callback).(Alternative)
	id := result.Fields[0].(OperationId)
	awaitSynchronizedSignal(t, entered)
	outcome := awaitSynchronizedCall(t, synchronizedCall(func() Value { return service.restart(root, id) }))
	if outcome.failure != nil || outcome.value.(Alternative).Tag != "ok" {
		t.Fatal("restart did not join old cleanup and admit fresh work", outcome)
	}
	guard.close()
	service.close(root)
	select {
	case value := <-reported:
		failure := value.(Alternative)
		if failure.Tag != "Crashed" || !strings.Contains(failure.Fields[1].(string), "ancestor waiting") {
			t.Fatal(failure)
		}
	default:
		t.Fatal("restart lost the old operation's cleanup crash")
	}
	requireWorkWaitsClear(t, root, &service.waits)
}

func TestSynchronizedSchedulerCloseIncludesReporters(t *testing.T) {
	for _, duringClose := range []bool{false, true} {
		name := "reporter waits before close"
		if duringClose {
			name = "reporter admitted during close"
		}
		t.Run(name, func(t *testing.T) {
			root := RootExecution()
			cell := synchronizedInt()
			guard := lockCell(root, cell)
			blocked, started := make(chan struct{}), make(chan struct{})
			faults := make(chan any, 1)
			reporter := NewFunction([]string{"failure"}, "Unit", func(child *Execution, _ []Value) Value {
				child = inherit(child, &synchronizedLockWaitContext{Context: child.Context, cell: cell, lifetime: child.Lifetime, entered: blocked})
				failure := recovered(func() { locked := lockCell(child, cell); locked.close() })
				faults <- failure
				if failure != nil {
					panic(failure)
				}
				return Unit{}
			})
			service := NewScheduler(root, []Argument{{"reporter", reporter}}).(*Scheduler)
			t.Cleanup(func() { guard.close(); service.close(root) })
			service.start(root, NewFunction(nil, "@std/Result[Unit][String]", func(child *Execution, _ []Value) Value {
				close(started)
				if duringClose {
					<-child.Context.Done()
					return Panic("report accepted during shutdown")
				}
				return Alternative{"@std/Result[Unit][String]", "error", []Value{"domain failure"}}
			}))
			awaitSynchronizedSignal(t, started)
			if !duringClose {
				awaitSynchronizedSignal(t, blocked)
			}
			outcome := awaitSynchronizedCall(t, synchronizedCall(func() Value { service.close(root); return Unit{} }))
			if outcome.failure != nil {
				t.Fatal("scheduler close faulted instead of joining reporter failure", outcome.failure)
			}
			select {
			case failure := <-faults:
				if fault, ok := failure.(Fault); !ok || !strings.Contains(fault.Message, "ancestor waiting") {
					t.Fatal("reporter cycle was not rejected", failure)
				}
			default:
				t.Fatal("close returned before reporter cleanup")
			}
			guard.close()
			requireWorkWaitsClear(t, root, &service.waits)
		})
	}
}

func TestSynchronizedJoinRacesCancellationAndRelease(t *testing.T) {
	for range 100 {
		func() {
			root := RootExecution()
			cell := synchronizedInt()
			guard := lockCell(root, cell)
			group := NewTaskGroup(root, nil).(*TaskGroup)
			defer func() {
				guard.close()
				if failure := recovered(func() { group.close(Shield(root)) }); failure != nil && !t.Failed() {
					t.Error(failure)
				}
			}()
			blocked := make(chan struct{})
			cancellation := make(chan context.CancelFunc, 1)
			task := groupTask(root, group, NewFunction(nil, "Int", func(child *Execution, _ []Value) Value {
				active, cancel := context.WithCancel(child.Context)
				defer cancel()
				cancellation <- cancel
				child = inherit(child, &synchronizedLockWaitContext{Context: active, cell: cell, lifetime: child.Lifetime, entered: blocked})
				locked := lockCell(child, cell)
				defer locked.close()
				return int64(7)
			}))
			awaitSynchronizedSignal(t, blocked)
			cancel := <-cancellation
			gate := make(chan struct{})
			done := synchronizedCall(func() Value { <-gate; return taskResult(root, task) })
			var racers sync.WaitGroup
			racers.Add(2)
			go func() { defer racers.Done(); <-gate; guard.close() }()
			go func() { defer racers.Done(); <-gate; cancel() }()
			close(gate)
			racers.Wait()
			outcome := awaitSynchronizedCall(t, done)
			if outcome.failure != nil {
				t.Fatal("racing join faulted the ancestor", outcome.failure)
			}
			result := outcome.value.(Alternative)
			if result.Tag == "ok" {
				if result.Fields[0] != int64(7) {
					t.Fatal(result)
				}
			} else {
				cause := result.Fields[0].(Alternative)
				if cause.Tag != "Cancelled" && (cause.Tag != "Crashed" || !strings.Contains(cause.Fields[1].(string), "ancestor waiting")) {
					t.Fatal(cause)
				}
			}
			group.close(root)
			requireWorkWaitsClear(t, root, &group.waits, &task.waits)
			cell.mu.Lock()
			held := cell.holder != nil
			cell.mu.Unlock()
			if held {
				t.Fatal("join/cancellation/release race leaked a guard")
			}
			next := lockCell(root, cell)
			next.close()
		}()
	}
}

func TestSynchronizedCancelledTransitiveWaitDoesNotFaultOtherTask(t *testing.T) {
	root := RootExecution()
	firstCell, secondCell := synchronizedInt(), synchronizedInt()
	guard := lockCell(root, firstCell)
	firstGroup := NewTaskGroup(root, nil).(*TaskGroup)
	secondGroup := NewTaskGroup(root, nil).(*TaskGroup)
	resume := make(chan struct{})
	var allow sync.Once
	t.Cleanup(func() {
		guard.close()
		allow.Do(func() { close(resume) })
		firstGroup.close(Shield(root))
		secondGroup.close(Shield(root))
	})
	secondBlocked := make(chan struct{})
	second := groupTask(root, secondGroup, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
		owned := lockCell(child, secondCell)
		defer owned.close()
		child = inherit(child, &synchronizedLockWaitContext{Context: child.Context, cell: firstCell, lifetime: child.Lifetime, entered: secondBlocked})
		locked := lockCell(child, firstCell)
		defer locked.close()
		return Unit{}
	}))
	awaitSynchronizedSignal(t, secondBlocked)
	firstBlocked := make(chan struct{})
	cancellation := make(chan context.CancelFunc, 1)
	first := groupTask(root, firstGroup, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
		active, cancel := context.WithCancel(child.Context)
		defer cancel()
		cancellation <- cancel
		child = inherit(child, &synchronizedLockWaitContext{Context: active, cell: secondCell, lifetime: child.Lifetime, entered: firstBlocked, resume: resume})
		locked := lockCell(child, secondCell)
		defer locked.close()
		return Unit{}
	}))
	awaitSynchronizedSignal(t, firstBlocked)
	(<-cancellation)()
	waiting := &synchronizedWaitContext{Context: root.Context, entered: make(chan struct{})}
	done := synchronizedCall(func() Value { return taskResult(inherit(root, waiting), first) })
	awaitSynchronizedSignal(t, waiting.entered)
	// The cancelled A -> B lock edge must not complete root -> A -> B -> root.
	select {
	case <-second.done:
		t.Fatal("cancelled transitive dependency faulted unrelated group work")
	default:
	}
	allow.Do(func() { close(resume) })
	outcome := awaitSynchronizedCall(t, done)
	if outcome.failure != nil || outcome.value.(Alternative).Fields[0].(Alternative).Tag != "Cancelled" {
		t.Fatal(outcome)
	}
	guard.close()
	outcome = awaitSynchronizedCall(t, synchronizedCall(func() Value { return taskResult(root, second) }))
	if outcome.failure != nil || outcome.value.(Alternative).Tag != "ok" {
		t.Fatal("cancelled transitive wait introduced a false ancestor cycle", outcome)
	}
	firstGroup.close(root)
	secondGroup.close(root)
	requireWorkWaitsClear(t, root, &firstGroup.waits, &secondGroup.waits, &first.waits, &second.waits)
}
