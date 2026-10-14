package msruntime

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
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

func TestSynchronizedReentryAcrossExecutionViews(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	defer guard.close()
	for name, caller := range map[string]*Execution{"same operation": root, "shielded operation": Shield(root), "inherited view": inherit(root, root.Context)} {
		t.Run(name, func(t *testing.T) {
			outcome := awaitSynchronizedCall(t, synchronizedCall(func() Value { locked := lockCell(caller, cell); locked.close(); return Unit{} }))
			if fault, ok := outcome.failure.(Fault); !ok || !strings.Contains(fault.Message, "this operation") {
				t.Fatal("reentry did not fault", outcome)
			}
		})
	}
}

func TestSynchronizedAncestorContentionWaits(t *testing.T) {
	for _, mode := range []string{"ordinary child", "shielded child", "nested child"} {
		t.Run(mode, func(t *testing.T) {
			root := RootExecution()
			cell := synchronizedInt()
			guard := lockCell(root, cell)
			group := NewTaskGroup(root, nil).(*TaskGroup)
			blocked := make(chan struct{})
			t.Cleanup(func() {
				guard.close()
				if failure := recovered(func() { group.close(Shield(root)) }); failure != nil && !t.Failed() {
					t.Error(failure)
				}
			})
			read := NewFunction(nil, "Int", func(child *Execution, _ []Value) Value {
				if mode == "shielded child" {
					child = Shield(child)
				}
				child = inherit(child, &synchronizedWaitContext{Context: child.Context, entered: blocked})
				locked := lockCell(child, cell)
				defer locked.close()
				return Invoke(child, locked.Operation("get"), nil)
			})
			callback := read
			if mode == "nested child" {
				callback = NewFunction(nil, "Int", func(child *Execution, _ []Value) Value {
					nested := NewTaskGroup(child, nil).(*TaskGroup)
					defer nested.close(Shield(child))
					task := groupTask(child, nested, read)
					result := taskResult(child, task)
					if result.Tag != "ok" {
						return Panic("nested child failed")
					}
					return result.Fields[0]
				})
			}
			task := groupTask(root, group, callback)
			awaitSynchronizedSignal(t, blocked)
			select {
			case <-task.done:
				t.Fatal("contention completed before release")
			default:
			}
			Invoke(root, guard.Operation("set"), []Argument{{"value", int64(7)}})
			guard.close()
			outcome := awaitSynchronizedCall(t, synchronizedCall(func() Value { return taskResult(root, task) }))
			if outcome.failure != nil || outcome.value.(Alternative).Tag != "ok" || outcome.value.(Alternative).Fields[0] != int64(7) {
				t.Fatal(outcome)
			}
			group.close(root)
		})
	}
}

func TestSynchronizedAncestorJoinCycleCancelled(t *testing.T) {
	for _, boundary := range []string{"task", "group"} {
		for _, joinFirst := range []bool{false, true} {
			order := "lock first"
			if joinFirst {
				order = "join first"
			}
			t.Run(boundary+"/"+order, func(t *testing.T) {
				base := RootExecution()
				active, cancel := context.WithCancel(base.Context)
				defer cancel()
				root := inherit(base, active)
				cell := synchronizedInt()
				guard := lockCell(root, cell)
				group := NewTaskGroup(root, nil).(*TaskGroup)
				acquire := make(chan struct{})
				var allow sync.Once
				t.Cleanup(func() { guard.close(); cancel(); allow.Do(func() { close(acquire) }); group.close(Shield(root)) })
				blocked := make(chan struct{})
				task := groupTask(root, group, NewFunction(nil, "Int", func(child *Execution, _ []Value) Value {
					<-acquire
					child = inherit(child, &synchronizedWaitContext{Context: child.Context, entered: blocked})
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
					allow.Do(func() { close(acquire) })
				} else {
					allow.Do(func() { close(acquire) })
					awaitSynchronizedSignal(t, blocked)
					done = synchronizedCall(join)
				}
				awaitSynchronizedSignal(t, blocked)
				awaitSynchronizedSignal(t, waiting.entered)
				select {
				case outcome := <-done:
					t.Fatal("cycle did not block", outcome)
				default:
				}
				cancel()
				outcome := awaitSynchronizedCall(t, done)
				if _, ok := outcome.failure.(cancelled); !ok {
					t.Fatal("cancelled join changed failure identity", outcome)
				}
				cell.mu.Lock()
				held := cell.holder == guard
				cell.mu.Unlock()
				if !held {
					t.Fatal("cancellation forcibly released executing holder")
				}
				Cleanup(root, guard)
				next := lockCell(base, cell)
				next.close()
			})
		}
	}
}

func TestSynchronizedDeadlineStopsOrdinaryWait(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	defer guard.close()
	deadline, cancel := context.WithTimeout(root.Context, 40*time.Millisecond)
	defer cancel()
	child := newExecution(root, deadline)
	outcome := awaitSynchronizedCall(t, synchronizedCall(func() Value { return lockCell(child, cell) }))
	if _, ok := outcome.failure.(cancelled); !ok || deadline.Err() != context.DeadlineExceeded {
		t.Fatal(outcome, deadline.Err())
	}
	cell.mu.Lock()
	held := cell.holder == guard
	cell.mu.Unlock()
	if !held {
		t.Fatal("deadline released executing holder")
	}
}

func TestSynchronizedTaskGroupTimeoutBreaksOrdinaryCycle(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	defer guard.close()
	group := NewTaskGroup(root, []Argument{{"timeout", Duration(40 * time.Millisecond)}}).(*TaskGroup)
	t.Cleanup(func() { guard.close(); group.close(root) })
	task := groupTask(root, group, NewFunction(nil, "Int", func(child *Execution, _ []Value) Value {
		locked := lockCell(child, cell)
		defer locked.close()
		return int64(1)
	}))
	outcome := awaitSynchronizedCall(t, synchronizedCall(func() Value { return taskResult(root, task) }))
	if outcome.failure != nil {
		t.Fatal(outcome)
	}
	result := outcome.value.(Alternative)
	if result.Tag != "error" || result.Fields[0].(Alternative).Tag != "Timeout" {
		t.Fatal(result)
	}
	cell.mu.Lock()
	held := cell.holder == guard
	cell.mu.Unlock()
	if !held {
		t.Fatal("group timeout released executing holder")
	}
	Invoke(root, guard.Operation("set"), []Argument{{"value", int64(3)}})
}

func TestSynchronizedNilLifetimesRemainIndependent(t *testing.T) {
	owner, other := RootExecution(), RootExecution()
	owner.Lifetime = nil
	other.Lifetime = nil
	cell := synchronizedInt()
	guard := lockCell(owner, cell)
	defer guard.close()
	waiting := &synchronizedWaitContext{Context: other.Context, entered: make(chan struct{})}
	other = inherit(other, waiting)
	done := synchronizedCall(func() Value { locked := lockCell(other, cell); locked.close(); return Unit{} })
	awaitSynchronizedSignal(t, waiting.entered)
	select {
	case outcome := <-done:
		t.Fatal("independent nil lifetimes did not wait", outcome)
	default:
	}
	guard.close()
	if outcome := awaitSynchronizedCall(t, done); outcome.failure != nil {
		t.Fatal(outcome)
	}
}

// Disposable children exercise real wait cycles without leaving stuck goroutines
// in this test process. The parent controls cancellation and alias release.
func TestSynchronizedBlockingCycleSubprocess(t *testing.T) {
	const variable = "MANUSCRIPT_SYNCHRONIZED_CYCLE_CHILD"
	if mode := os.Getenv(variable); mode != "" {
		runSynchronizedCycleChild(t, mode)
		return
	}
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	for _, mode := range []string{"ordinary", "shielded"} {
		t.Run(mode, func(t *testing.T) {
			deadline, cancel := context.WithTimeout(context.Background(), 8*time.Second)
			defer cancel()
			command := exec.CommandContext(deadline, executable, "-test.run=^TestSynchronizedBlockingCycleSubprocess$", "-test.count=1", "-test.timeout=6s")
			command.Env = append(os.Environ(), variable+"="+mode)
			input, err := command.StdinPipe()
			if err != nil {
				t.Fatal(err)
			}
			defer input.Close()
			output, err := command.StdoutPipe()
			if err != nil {
				t.Fatal(err)
			}
			var diagnostics strings.Builder
			command.Stderr = &diagnostics
			if err := command.Start(); err != nil {
				t.Fatal(err)
			}
			exited := make(chan error, 1)
			lines := make(chan string, 32)
			go func() {
				scanner := bufio.NewScanner(output)
				for scanner.Scan() {
					select {
					case lines <- scanner.Text():
					case <-deadline.Done():
						close(lines)
						exited <- command.Wait()
						return
					}
				}
				close(lines)
				exited <- command.Wait()
			}()
			wait := func(marker string) {
				t.Helper()
				for {
					select {
					case line, ok := <-lines:
						if !ok {
							t.Fatal("child exited before", marker)
						}
						if line == marker {
							return
						}
					case <-deadline.Done():
						t.Fatal("child did not reach", marker)
					}
				}
			}
			if mode == "ordinary" {
				wait("CYCLE_WAITING")
				if _, err := fmt.Fprintln(input, "cancel"); err != nil {
					t.Fatal(err)
				}
				wait("CANCELLED_RELEASED")
			} else {
				wait("CANCELLED_SHIELDED_WAITING")
				if _, err := fmt.Fprintln(input, "release"); err != nil {
					t.Fatal(err)
				}
				wait("RELEASED_JOIN_FINISHED")
			}
			input.Close()
			select {
			case err := <-exited:
				if err != nil {
					t.Fatal(err, diagnostics.String())
				}
			case <-deadline.Done():
				t.Fatal("child process did not exit")
			}
		})
	}
}

func runSynchronizedCycleChild(t *testing.T, mode string) {
	base := RootExecution()
	active, cancel := context.WithCancel(base.Context)
	defer cancel()
	root := inherit(base, active)
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	group := NewTaskGroup(root, nil).(*TaskGroup)
	t.Cleanup(func() { guard.close(); cancel(); group.close(Shield(root)) })
	blocked, started := make(chan struct{}), make(chan struct{})
	task := groupTask(root, group, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
		if mode == "shielded" {
			defer func() {
				shield := inherit(Shield(child), &synchronizedWaitContext{Context: Shield(child).Context, entered: blocked})
				locked := lockCell(shield, cell)
				locked.close()
			}()
			close(started)
			<-child.Context.Done()
			CheckCancelled(child)
		} else {
			child = inherit(child, &synchronizedWaitContext{Context: child.Context, entered: blocked})
			locked := lockCell(child, cell)
			locked.close()
		}
		return Unit{}
	}))
	waiting := &synchronizedWaitContext{Context: root.Context, entered: make(chan struct{})}
	done := synchronizedCall(func() Value { return taskResult(inherit(root, waiting), task) })
	awaitSynchronizedSignal(t, waiting.entered)
	reader := bufio.NewReader(os.Stdin)
	if mode == "shielded" {
		awaitSynchronizedSignal(t, started)
		cancel()
		awaitSynchronizedSignal(t, blocked)
		select {
		case outcome := <-done:
			t.Fatal("shielded cleanup was abandoned", outcome)
		default:
		}
		cell.mu.Lock()
		held := cell.holder == guard
		cell.mu.Unlock()
		if !held {
			t.Fatal("cancel released holder")
		}
		fmt.Println("CANCELLED_SHIELDED_WAITING")
		command, err := reader.ReadString('\n')
		if err != nil || command != "release\n" {
			t.Fatal(command, err)
		}
		guard.close()
	} else {
		awaitSynchronizedSignal(t, blocked)
		select {
		case outcome := <-done:
			t.Fatal("cycle did not wait", outcome)
		default:
		}
		fmt.Println("CYCLE_WAITING")
		command, err := reader.ReadString('\n')
		if err != nil || command != "cancel\n" {
			t.Fatal(command, err)
		}
		cancel()
	}
	outcome := awaitSynchronizedCall(t, done)
	if _, ok := outcome.failure.(cancelled); !ok {
		t.Fatal("join cancellation identity", outcome)
	}
	if mode == "ordinary" {
		cell.mu.Lock()
		held := cell.holder == guard
		cell.mu.Unlock()
		if !held {
			t.Fatal("cancel released holder")
		}
		Cleanup(root, guard)
		next := lockCell(base, cell)
		next.close()
		fmt.Println("CANCELLED_RELEASED")
	} else {
		fmt.Println("RELEASED_JOIN_FINISHED")
	}
}
