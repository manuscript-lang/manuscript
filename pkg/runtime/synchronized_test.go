package msruntime

import (
	"context"
	"strings"
	"sync"
	"testing"
	"time"
)

func synchronizedInt() *Synchronized {
	return ConstructWithContext(RootExecution(), "@std/Synchronized[Int]", []Argument{{"value", int64(0)}}).(*Synchronized)
}
func lockCell(ctx *Execution, cell *Synchronized) *SynchronizedGuard {
	return Invoke(ctx, cell.Operation("lock"), nil).(*SynchronizedGuard)
}
func TestSynchronizedConcurrentUpdates(t *testing.T) {
	cell := synchronizedInt()
	root := RootExecution()
	var wait sync.WaitGroup
	for range 20 {
		wait.Add(1)
		go func() {
			defer wait.Done()
			child := newExecution(root, root.Context)
			for range 100 {
				guard := lockCell(child, cell)
				value := Invoke(child, guard.Operation("get"), nil).(int64)
				Invoke(child, guard.Operation("set"), []Argument{{"value", value + 1}})
				guard.close()
			}
		}()
	}
	wait.Wait()
	guard := lockCell(root, cell)
	defer guard.close()
	if value := Invoke(root, guard.Operation("get"), nil); value != int64(2000) {
		t.Fatalf("lost update: %v", value)
	}
}
func TestSynchronizedCancelledWaiterAndHolder(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	holderContext, cancelHolder := context.WithCancel(root.Context)
	holder := newExecution(root, holderContext)
	guard := lockCell(holder, cell)
	waitContext, cancelWait := context.WithCancel(root.Context)
	waiter := newExecution(root, waitContext)
	started, done := make(chan struct{}), make(chan any, 1)
	go func() {
		close(started)
		done <- recovered(func() { lockCell(waiter, cell) })
	}()
	<-started
	cancelWait()
	select {
	case failure := <-done:
		if _, ok := failure.(cancelled); !ok {
			t.Fatal(failure)
		}
	case <-time.After(time.Second):
		t.Fatal("cancelled waiter remained blocked")
	}
	cancelHolder()
	cell.mu.Lock()
	stillHeld := cell.holder == guard
	cell.mu.Unlock()
	if !stillHeld {
		t.Fatal("cancellation forcibly released the holder")
	}
	// Cleanup is shielded; it releases even after the holder was cancelled.
	Cleanup(holder, guard)
	next := lockCell(root, cell)
	next.close()
}
func TestSynchronizedReentryAndClosedAliases(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	saved := guard.Operation("set")
	for _, ctx := range []*Execution{root, Shield(root), inherit(root, root.Context)} {
		failure := recovered(func() { lockCell(ctx, cell) })
		if fault, ok := failure.(Fault); !ok || !strings.Contains(fault.Message, "this operation") {
			t.Fatal(failure)
		}
	}
	guard.close()
	next := lockCell(root, cell)
	defer next.close()
	var wait sync.WaitGroup
	for range 20 {
		wait.Add(1)
		go func() { defer wait.Done(); guard.close() }()
	}
	wait.Wait()
	failure := recovered(func() { Invoke(root, saved, []Argument{{"value", int64(7)}}) })
	if _, ok := failure.(Fault); !ok {
		t.Fatal("stale alias remained usable", failure)
	}
	if Invoke(root, next.Operation("get"), nil) != int64(0) {
		t.Fatal("stale alias modified new lock's value")
	}
}
func TestSynchronizedCloseRacesAccess(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	saved := guard.Operation("set")
	var wait sync.WaitGroup
	for range 50 {
		wait.Add(1)
		go func() {
			defer wait.Done()
			failure := recovered(func() { Invoke(root, saved, []Argument{{"value", int64(1)}}) })
			if failure != nil {
				if _, ok := failure.(Fault); !ok {
					t.Error(failure)
				}
			}
		}()
	}
	guard.close()
	next := lockCell(root, cell)
	Invoke(root, next.Operation("set"), []Argument{{"value", int64(2)}})
	wait.Wait()
	if Invoke(root, next.Operation("get"), nil) != int64(2) {
		t.Fatal("old guard accessed reacquired value")
	}
	next.close()
}
func TestSharedBuilderFreezeRace(t *testing.T) {
	root := RootExecution()
	builder := newBuilder("@std/ListBuilder[Int]")
	var wait sync.WaitGroup
	for range 100 {
		wait.Add(1)
		go func() {
			defer wait.Done()
			failure := recovered(func() { Invoke(root, builder.Operation("append"), []Argument{{"value", int64(1)}}) })
			if failure != nil {
				if _, ok := failure.(Fault); !ok {
					t.Error(failure)
				}
			}
		}()
	}
	snapshot := Invoke(root, builder.Operation("freeze"), nil).(*List)
	wait.Wait()
	again := Invoke(root, builder.Operation("freeze"), nil).(*List)
	if len(snapshot.Items) != len(again.Items) {
		t.Fatal("frozen snapshot changed")
	}
}

// Cancel at the actual acquisition-delivery boundary, after the guard exists
// but before NewAcquisition can deliver it to the caller.
type cancelOnGuardContext struct {
	context.Context
	cell      *Synchronized
	cancelled bool
}

func (c *cancelOnGuardContext) Err() error {
	c.cell.mu.Lock()
	defer c.cell.mu.Unlock()
	c.cancelled = c.cancelled || c.cell.holder != nil
	if c.cancelled {
		return context.Canceled
	}
	return nil
}
func TestSynchronizedUndeliveredAcquisition(t *testing.T) {
	cell := synchronizedInt()
	root := RootExecution()
	ctx := newExecution(root, &cancelOnGuardContext{Context: root.Context, cell: cell})
	failure := recovered(func() { lockCell(ctx, cell) })
	if _, ok := failure.(cancelled); !ok {
		t.Fatal("delivered cancelled acquisition", failure)
	}
	guard := lockCell(root, cell)
	guard.close()
}

func guardOp(ctx *Execution, g *SynchronizedGuard, name string) any {
	return recovered(func() { Invoke(ctx, g.Operation(name), nil) })
}

func TestSynchronizedWaitNotifyAll(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	waiterCtx := newExecution(root, root.Context)
	guard := lockCell(waiterCtx, cell)
	done := make(chan any, 1)
	go func() { done <- guardOp(waiterCtx, guard, "wait") }()
	// The lock is free while waiting: another task can lock and notify.
	var notifier *SynchronizedGuard
	notifierCtx := newExecution(root, root.Context)
	notifier = lockCell(notifierCtx, cell)
	for {
		cell.mu.Lock()
		n := len(cell.waiters)
		cell.mu.Unlock()
		if n == 1 {
			break
		}
		time.Sleep(time.Millisecond)
	}
	if failure := guardOp(notifierCtx, notifier, "notify_all"); failure != nil {
		t.Fatal(failure)
	}
	select {
	case <-done:
		t.Fatal("wait returned before the lock was released")
	case <-time.After(20 * time.Millisecond):
	}
	notifier.close()
	if failure := <-done; failure != nil {
		t.Fatal(failure)
	}
	if value := Invoke(waiterCtx, guard.Operation("get"), nil); value != int64(0) {
		t.Fatalf("guard unusable after wait: %v", value)
	}
	guard.close()
}

func TestSynchronizedWaitCancelledDoesNotReacquire(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	ctxCancel, cancel := context.WithCancel(root.Context)
	waiterCtx := newExecution(root, ctxCancel)
	guard := lockCell(waiterCtx, cell)
	done := make(chan any, 1)
	go func() { done <- guardOp(waiterCtx, guard, "wait") }()
	for {
		cell.mu.Lock()
		n := len(cell.waiters)
		cell.mu.Unlock()
		if n == 1 {
			break
		}
		time.Sleep(time.Millisecond)
	}
	// Another operation holds the lock; cancellation must not wait for it.
	holder := lockCell(newExecution(root, root.Context), cell)
	cancel()
	select {
	case failure := <-done:
		if _, ok := failure.(cancelled); !ok {
			t.Fatal(failure)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("cancelled wait blocked on the held lock")
	}
	guard.close() // no-op: must not release the other holder
	if cell.holder != holder {
		t.Fatal("cancelled waiter's close released another acquisition")
	}
	holder.close()
	if len(cell.waiters) != 0 {
		t.Fatal("waiter leaked")
	}
}

func TestSynchronizedWaitRequiresOwner(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	owner := newExecution(root, root.Context)
	guard := lockCell(owner, cell)
	other := newExecution(root, root.Context)
	for _, name := range []string{"wait", "notify_all"} {
		if guardOp(other, guard, name) == nil {
			t.Fatalf("%s through another operation must fault", name)
		}
	}
	guard.close()
	for _, name := range []string{"wait", "notify_all"} {
		if guardOp(owner, guard, name) == nil {
			t.Fatalf("%s on a closed guard must fault", name)
		}
	}
}

func TestSynchronizedAliasCloseDuringWaitFaults(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	waiterCtx := newExecution(root, root.Context)
	guard := lockCell(waiterCtx, cell)
	done := make(chan any, 1)
	go func() { done <- guardOp(waiterCtx, guard, "wait") }()
	for {
		cell.mu.Lock()
		n := len(cell.waiters)
		cell.mu.Unlock()
		if n == 1 {
			break
		}
		time.Sleep(time.Millisecond)
	}
	guard.close() // alias close while the owner waits
	notifierCtx := newExecution(root, root.Context)
	notifier := lockCell(notifierCtx, cell)
	Invoke(notifierCtx, notifier.Operation("notify_all"), nil)
	notifier.close()
	if failure := <-done; failure == nil {
		t.Fatal("wait must fault after the guard was closed during the wait")
	}
	if cell.holder != nil {
		t.Fatal("closed guard was reinstalled as holder")
	}
}
