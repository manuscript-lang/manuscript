package rt

import (
	"context"
	"fmt"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func mustFault(t *testing.T, contains string, f func()) {
	t.Helper()
	defer func() {
		r := recover()
		fault, ok := r.(Fault)
		if !ok {
			t.Fatalf("expected a fault containing %q, got %v", contains, r)
		}
		if !strings.Contains(fault.Message, contains) {
			t.Fatalf("fault %q does not contain %q", fault.Message, contains)
		}
	}()
	f()
}

func cancelledExecution() (*Execution, context.CancelFunc) {
	ctx, cancel := context.WithCancel(context.Background())
	return rootExecution(ctx, nil), cancel
}

func TestTaskGroupResults(t *testing.T) {
	ctx := RootExecution()
	g := NewTaskGroup(None[Duration]())
	a := TaskGroup_Start(ctx, g, func(*Execution) int64 { return 42 })
	b := TaskGroup_Start(ctx, g, func(*Execution) string { return "hello" })
	if r := TaskGroup_Join(ctx, g); r.Failed {
		t.Fatalf("join failed: %v", r.Err)
	}
	if r := Task_Join(ctx, a); r.Failed || r.Val != 42 {
		t.Fatalf("a = %+v", r)
	}
	if r := Task_Join(ctx, b); r.Failed || r.Val != "hello" {
		t.Fatalf("b = %+v", r)
	}
	TaskGroup_Close(ctx, g)
	mustFault(t, "joined or closed", func() { TaskGroup_Start(ctx, g, func(*Execution) int64 { return 1 }) })
}

func TestTaskGroupCrashTakesPrecedenceAndSiblingsCancel(t *testing.T) {
	ctx := RootExecution()
	g := NewTaskGroup(None[Duration]())
	var cleaned atomic.Bool
	sibling := TaskGroup_Start(ctx, g, func(c *Execution) Unit {
		defer func() { cleaned.Store(true) }()
		<-c.Context.Done()
		return CheckCancelled(c)
	})
	TaskGroup_Start(ctx, g, func(*Execution) Unit { Raise("boom"); return Unit{} })
	r := TaskGroup_Join(ctx, g)
	crashed, ok := r.Err.(ExecutionError_Crashed)
	if !r.Failed || !ok || !strings.Contains(crashed.Message, "boom") {
		t.Fatalf("join = %+v", r)
	}
	if !cleaned.Load() {
		t.Fatal("sibling cleanup did not finish before join returned")
	}
	if r := Task_Join(ctx, sibling); !r.Failed {
		t.Fatal("cancelled sibling joined successfully")
	}
	TaskGroup_Close(ctx, g) // observed: no cleanup fault
}

func TestTaskGroupUnobservedFaultSurfacesOnClose(t *testing.T) {
	ctx := RootExecution()
	g := NewTaskGroup(None[Duration]())
	TaskGroup_Start(ctx, g, func(*Execution) Unit { Raise("lost"); return Unit{} })
	time.Sleep(20 * time.Millisecond)
	mustFault(t, "unobserved TaskGroup fault: lost", func() { TaskGroup_Close(ctx, g) })
}

func TestTaskGroupTimeout(t *testing.T) {
	ctx := RootExecution()
	g := NewTaskGroup(Some(Duration(20 * time.Millisecond)))
	TaskGroup_Start(ctx, g, func(c *Execution) Unit { <-c.Context.Done(); return CheckCancelled(c) })
	r := TaskGroup_Join(ctx, g)
	if _, ok := r.Err.(ExecutionError_Timeout); !ok {
		t.Fatalf("join = %+v", r)
	}
	zero := NewTaskGroup(Some(Duration(0)))
	var ran atomic.Bool
	TaskGroup_Start(ctx, zero, func(*Execution) Unit { ran.Store(true); return Unit{} })
	if r := TaskGroup_Join(ctx, zero); !r.Failed || ran.Load() {
		t.Fatalf("zero timeout = %+v ran=%v", r, ran.Load())
	}
	empty := NewTaskGroup(Some(Duration(0)))
	if r := TaskGroup_Join(ctx, empty); r.Failed {
		t.Fatal("empty group failed")
	}
	mustFault(t, "TaskGroup: timeout (nanoseconds) must be between 0", func() { NewTaskGroup(Some(Duration(-1))) })
}

func TestTaskGroupCloseCancels(t *testing.T) {
	ctx := RootExecution()
	g := NewTaskGroup(None[Duration]())
	task := TaskGroup_Start(ctx, g, func(c *Execution) Unit { <-c.Context.Done(); return CheckCancelled(c) })
	TaskGroup_Close(ctx, g)
	TaskGroup_Close(ctx, g)
	if r := Task_Join(ctx, task); !r.Failed {
		t.Fatal("cancelled task joined successfully")
	} else if _, ok := r.Err.(ExecutionError_Cancelled); !ok {
		t.Fatalf("err = %v", r.Err)
	}
}

func TestTaskGroupRejectsSelfJoin(t *testing.T) {
	ctx := RootExecution()
	g := NewTaskGroup(None[Duration]())
	result := make(chan any, 1)
	TaskGroup_Start(ctx, g, func(c *Execution) Unit {
		defer func() { result <- recover() }()
		TaskGroup_Join(c, g)
		return Unit{}
	})
	r := <-result
	if f, ok := r.(Fault); !ok || !strings.Contains(f.Message, "cannot join or close its own group") {
		t.Fatalf("recovered %v", r)
	}
	TaskGroup_Close(ctx, g)
}

func TestFinishExecutionClosesUnclosedGroup(t *testing.T) {
	ctx := RootExecution()
	var stopped atomic.Bool
	func() {
		defer FinishExecution(ctx)
		g := NewTaskGroup(None[Duration]())
		TaskGroup_Start(ctx, g, func(c *Execution) Unit {
			<-c.Context.Done()
			stopped.Store(true)
			return Unit{}
		})
	}()
	if !stopped.Load() {
		t.Fatal("work lifetime did not join the group")
	}
}

func TestTaskGroupParentCancellation(t *testing.T) {
	ctx, cancel := cancelledExecution()
	g := NewTaskGroup(None[Duration]())
	TaskGroup_Start(ctx, g, func(c *Execution) Unit { <-c.Context.Done(); return CheckCancelled(c) })
	cancel()
	defer func() {
		if _, ok := recover().(cancelled); !ok {
			t.Fatal("join by a cancelled caller must unwind")
		}
	}()
	TaskGroup_Join(ctx, g)
}

func okOp(*Execution) Result[Unit, Error] { return Ok[Unit, Error](Unit{}) }

func TestSchedulerStartStatusLimit(t *testing.T) {
	ctx := RootExecution()
	s := NewScheduler(Some(int64(1)), None[int64](), None[Duration](), None[func(*Execution, SchedulerFailure) Unit]())
	defer Scheduler_Close(ctx, s)
	release := make(chan struct{})
	first := Scheduler_Start(ctx, s, func(*Execution) Result[Unit, Error] { <-release; return okOp(nil) })
	if first.Failed {
		t.Fatal("first start failed")
	}
	if _, ok := Scheduler_Status(ctx, s, first.Val).(WorkStatus_Running); !ok {
		t.Fatal("not running")
	}
	if r := Scheduler_Start(ctx, s, okOp); !r.Failed {
		t.Fatal("limit not enforced")
	} else if _, ok := r.Err.(StartError_Full); !ok {
		t.Fatalf("err = %v", r.Err)
	}
	close(release)
	waitStatus(t, ctx, s, first.Val, func(w WorkStatus) bool { _, ok := w.(WorkStatus_Succeeded); return ok })
	if _, ok := Scheduler_Status(ctx, s, &OperationId{}).(WorkStatus_Unknown); !ok {
		t.Fatal("foreign id must be Unknown")
	}
}

func waitStatus(t *testing.T, ctx *Execution, s *Scheduler, id *OperationId, want func(WorkStatus) bool) {
	t.Helper()
	for i := 0; i < 500; i++ {
		if want(Scheduler_Status(ctx, s, id)) {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("status = %#v", Scheduler_Status(ctx, s, id))
}

func TestSchedulerReportsFailuresAndCrashes(t *testing.T) {
	ctx := RootExecution()
	reports := make(chan SchedulerFailure, 4)
	reporter := func(_ *Execution, f SchedulerFailure) Unit { reports <- f; return Unit{} }
	s := NewScheduler(None[int64](), None[int64](), None[Duration](), Some(reporter))
	failed := Scheduler_Start(ctx, s, func(*Execution) Result[Unit, Error] {
		return Fail[Unit, Error](testError("bad"))
	})
	crashed := Scheduler_Start(ctx, s, func(*Execution) Result[Unit, Error] { Raise("crash"); return okOp(nil) })
	waitStatus(t, ctx, s, failed.Val, func(w WorkStatus) bool { _, ok := w.(WorkStatus_Failed); return ok })
	waitStatus(t, ctx, s, crashed.Val, func(w WorkStatus) bool { _, ok := w.(WorkStatus_Crashed); return ok })
	Scheduler_Close(ctx, s)
	f1, f2 := <-reports, <-reports
	if len(reports) != 0 {
		t.Fatal("extra reports")
	}
	byOp := map[*OperationId]SchedulerFailure{failureOperation(f1): f1, failureOperation(f2): f2}
	if _, ok := byOp[failed.Val].(SchedulerFailure_Failed); !ok {
		t.Fatalf("failed report = %#v", byOp[failed.Val])
	}
	if c, ok := byOp[crashed.Val].(SchedulerFailure_Crashed); !ok || !strings.Contains(c.Message, "crash") {
		t.Fatalf("crash report = %#v", byOp[crashed.Val])
	}
	if _, ok := Scheduler_Status(ctx, s, failed.Val).(WorkStatus_Failed); !ok {
		t.Fatal("status not Failed")
	}
	if _, ok := Scheduler_Status(ctx, s, crashed.Val).(WorkStatus_Crashed); !ok {
		t.Fatal("status not Crashed")
	}
	if r := Scheduler_Start(ctx, s, okOp); !r.Failed {
		t.Fatal("closed scheduler accepted work")
	} else if _, ok := r.Err.(StartError_Closed); !ok {
		t.Fatal("not Closed")
	}
}

func TestSchedulerAfterEveryRestartCancel(t *testing.T) {
	ctx := RootExecution()
	s := NewScheduler(None[int64](), None[int64](), None[Duration](), None[func(*Execution, SchedulerFailure) Unit]())
	defer Scheduler_Close(ctx, s)
	if r := Scheduler_After(ctx, s, -1, okOp); !r.Failed {
		t.Fatal("negative delay accepted")
	}
	if r := Scheduler_Every(ctx, s, 0, okOp); !r.Failed {
		t.Fatal("zero interval accepted")
	}
	var runs atomic.Int64
	every := Scheduler_Every(ctx, s, Duration(5*time.Millisecond), func(*Execution) Result[Unit, Error] { runs.Add(1); return okOp(nil) })
	for runs.Load() < 3 {
		time.Sleep(time.Millisecond)
	}
	restarted := Scheduler_Restart(ctx, s, every.Val)
	if restarted.Failed || restarted.Val == every.Val {
		t.Fatal("restart must return a fresh id")
	}
	if _, ok := Scheduler_Status(ctx, s, every.Val).(WorkStatus_Cancelled); !ok {
		t.Fatalf("old id status = %#v", Scheduler_Status(ctx, s, every.Val))
	}
	Scheduler_Cancel(ctx, s, restarted.Val)
	waitStatus(t, ctx, s, restarted.Val, func(w WorkStatus) bool { _, ok := w.(WorkStatus_Cancelled); return ok })
	immediate := Scheduler_Start(ctx, s, okOp)
	if r := Scheduler_Restart(ctx, s, immediate.Val); !r.Failed {
		t.Fatal("start-created id restarted")
	}
	var ran atomic.Bool
	after := Scheduler_After(ctx, s, Duration(time.Hour), func(*Execution) Result[Unit, Error] { ran.Store(true); return okOp(nil) })
	Scheduler_Cancel(ctx, s, after.Val)
	waitStatus(t, ctx, s, after.Val, func(w WorkStatus) bool { _, ok := w.(WorkStatus_Cancelled); return ok })
	if ran.Load() {
		t.Fatal("cancelled delayed work ran")
	}
}

func TestSchedulerHistoryLimit(t *testing.T) {
	ctx := RootExecution()
	s := NewScheduler(None[int64](), Some(int64(0)), None[Duration](), None[func(*Execution, SchedulerFailure) Unit]())
	id := Scheduler_Start(ctx, s, okOp)
	Scheduler_Close(ctx, s)
	if _, ok := Scheduler_Status(ctx, s, id.Val).(WorkStatus_Unknown); !ok {
		t.Fatal("history_limit 0 must retain nothing")
	}
}

func TestSchedulerCloseFromOwnOperationFaults(t *testing.T) {
	ctx := RootExecution()
	s := NewScheduler(None[int64](), None[int64](), None[Duration](), None[func(*Execution, SchedulerFailure) Unit]())
	recovered := make(chan any, 1)
	Scheduler_Start(ctx, s, func(c *Execution) Result[Unit, Error] {
		defer func() { recovered <- recover() }()
		Scheduler_Close(c, s)
		return okOp(nil)
	})
	if f, ok := (<-recovered).(Fault); !ok || !strings.Contains(f.Message, "cannot close its own service") {
		t.Fatal("expected own-service close fault")
	}
	Scheduler_Close(ctx, s)
}

func TestSchedulerDrainLetsWorkFinish(t *testing.T) {
	ctx := RootExecution()
	s := NewScheduler(None[int64](), None[int64](), Some(Duration(time.Second)), None[func(*Execution, SchedulerFailure) Unit]())
	var finished atomic.Bool
	id := Scheduler_Start(ctx, s, func(c *Execution) Result[Unit, Error] {
		sleepFor(c, 30*time.Millisecond)
		finished.Store(true)
		return okOp(nil)
	})
	Scheduler_Close(ctx, s)
	if !finished.Load() {
		t.Fatal("drain cancelled work immediately")
	}
	if _, ok := Scheduler_Status(ctx, s, id.Val).(WorkStatus_Succeeded); !ok {
		t.Fatal("not Succeeded")
	}
}

func TestSchedulerConstructorFaults(t *testing.T) {
	none := None[func(*Execution, SchedulerFailure) Unit]()
	mustFault(t, "Scheduler: limit must be between 1", func() { NewScheduler(Some(int64(0)), None[int64](), None[Duration](), none) })
	mustFault(t, "Scheduler: history_limit must be between 0", func() { NewScheduler(None[int64](), Some(int64(-1)), None[Duration](), none) })
	mustFault(t, "Scheduler: drain (nanoseconds)", func() { NewScheduler(None[int64](), None[int64](), Some(Duration(-1)), none) })
}

func TestErrorMessages(t *testing.T) {
	ctx := RootExecution()
	for want, got := range map[string]string{
		"task execution: operation timed out": Errors_Message_ExecutionError(ctx, ExecutionError_Timeout{}),
		"task execution: operation cancelled": Errors_Message_ExecutionError(ctx, ExecutionError_Cancelled{}),
		"fault text":                          Errors_Message_ExecutionError(ctx, ExecutionError_Crashed{Message: "fault text"}),
		"scheduler: capacity exhausted":       Errors_Message_StartError(ctx, StartError_Full{}),
		"scheduler: resource is closed":       Errors_Message_StartError(ctx, StartError_Closed{}),
		"scheduler: invalid input":            Errors_Message_StartError(ctx, StartError_InvalidInput{}),
	} {
		if got != want {
			t.Errorf("got %q want %q", got, want)
		}
	}
}

func TestSynchronizedLockSetWait(t *testing.T) {
	ctx := RootExecution()
	cell := NewSynchronized(int64(0))
	g := Synchronized_Lock(ctx, cell)
	SynchronizedGuard_Set(ctx, g, 5)
	if SynchronizedGuard_Value(ctx, g) != 5 {
		t.Fatal("value")
	}
	mustFault(t, "held by this operation", func() { Synchronized_Lock(ctx, cell) })
	SynchronizedGuard_Close(ctx, g)
	SynchronizedGuard_Close(ctx, g)
	mustFault(t, "Synchronized guard is closed", func() { SynchronizedGuard_Value(ctx, g) })
	mustFault(t, "Synchronized guard is closed", func() { SynchronizedGuard_Set(ctx, g, 1) })
}

func TestSynchronizedConcurrentCounter(t *testing.T) {
	ctx := RootExecution()
	cell := NewSynchronized(int64(0))
	group := NewTaskGroup(None[Duration]())
	for i := 0; i < 8; i++ {
		TaskGroup_Start(ctx, group, func(c *Execution) Unit {
			for j := 0; j < 100; j++ {
				g := Synchronized_Lock(c, cell)
				SynchronizedGuard_Set(c, g, SynchronizedGuard_Value(c, g)+1)
				SynchronizedGuard_Close(c, g)
			}
			return Unit{}
		})
	}
	if r := TaskGroup_Join(ctx, group); r.Failed {
		t.Fatal("join failed")
	}
	g := Synchronized_Lock(ctx, cell)
	defer SynchronizedGuard_Close(ctx, g)
	if v := SynchronizedGuard_Value(ctx, g); v != 800 {
		t.Fatalf("counter = %d", v)
	}
}

func TestSynchronizedWaitNotify(t *testing.T) {
	ctx := RootExecution()
	ready := NewSynchronized(false)
	group := NewTaskGroup(None[Duration]())
	woke := TaskGroup_Start(ctx, group, func(c *Execution) bool {
		g := Synchronized_Lock(c, ready)
		defer SynchronizedGuard_Close(c, g)
		for !SynchronizedGuard_Value(c, g) {
			SynchronizedGuard_Wait(c, g)
		}
		return true
	})
	time.Sleep(20 * time.Millisecond)
	g := Synchronized_Lock(ctx, ready)
	SynchronizedGuard_Set(ctx, g, true)
	SynchronizedGuard_NotifyAll(ctx, g)
	SynchronizedGuard_Close(ctx, g)
	if r := Task_Join(ctx, woke); r.Failed || !r.Val {
		t.Fatalf("waiter = %+v", r)
	}
	TaskGroup_Close(ctx, group)
}

func TestSynchronizedCancelledWaitLeavesGuardReleased(t *testing.T) {
	ctx := RootExecution()
	cell := NewSynchronized(0)
	group := NewTaskGroup(None[Duration]())
	started := make(chan struct{})
	TaskGroup_Start(ctx, group, func(c *Execution) Unit {
		g := Synchronized_Lock(c, cell)
		defer SynchronizedGuard_Close(c, g)
		close(started)
		SynchronizedGuard_Wait(c, g)
		return Unit{}
	})
	<-started
	TaskGroup_Close(ctx, group) // cancels the waiter; must not deadlock
	g := Synchronized_Lock(ctx, cell)
	SynchronizedGuard_Close(ctx, g)
}

func TestSynchronizedWaitRequiresOwner(t *testing.T) {
	ctx := RootExecution()
	cell := NewSynchronized(0)
	g := Synchronized_Lock(ctx, cell)
	defer SynchronizedGuard_Close(ctx, g)
	other := RootExecution()
	mustFault(t, "only the operation that acquired", func() { SynchronizedGuard_NotifyAll(other, g) })
}

func TestSynchronizedLockObservesCancellation(t *testing.T) {
	ctx := RootExecution()
	cell := NewSynchronized(0)
	g := Synchronized_Lock(ctx, cell)
	defer SynchronizedGuard_Close(ctx, g)
	waiter, cancel := cancelledExecution()
	go func() { time.Sleep(10 * time.Millisecond); cancel() }()
	defer func() {
		if _, ok := recover().(cancelled); !ok {
			t.Fatal("blocked lock must unwind on cancellation")
		}
	}()
	Synchronized_Lock(waiter, cell)
}

func TestQueue(t *testing.T) {
	ctx := RootExecution()
	q := NewQueue[int64](Some(int64(2)))
	if !Queue_Enqueue(ctx, q, 1) || !Queue_Enqueue(ctx, q, 2) || Queue_Enqueue(ctx, q, 3) {
		t.Fatal("capacity")
	}
	if p := Queue_Peek(ctx, q); !p.Some || p.Val != 1 || Queue_Length(ctx, q) != 2 || Queue_IsEmpty(ctx, q) {
		t.Fatal("peek")
	}
	if d := Queue_Dequeue(ctx, q); d.Val != 1 || !d.Some {
		t.Fatal("dequeue")
	}
	Queue_Dequeue(ctx, q)
	if Queue_Dequeue(ctx, q).Some || !Queue_IsEmpty(ctx, q) {
		t.Fatal("empty")
	}
	mustFault(t, "Queue: capacity must be between 1", func() { NewQueue[int64](Some(int64(0))) })
	unbounded := NewQueue[int64](None[int64]())
	for i := int64(0); i < 1000; i++ {
		Queue_Enqueue(ctx, unbounded, i)
	}
	if Queue_Length(ctx, unbounded) != 1000 {
		t.Fatal("unbounded")
	}
}

func TestBlockingQueueProducerConsumer(t *testing.T) {
	ctx := RootExecution()
	q := NewBlockingQueue[int64](Some(int64(2)))
	group := NewTaskGroup(None[Duration]())
	worker := TaskGroup_Start(ctx, group, func(c *Execution) int64 {
		var total int64
		for {
			v := BlockingQueue_Take(c, q)
			if !v.Some {
				return total
			}
			total += v.Val
		}
	})
	for i := int64(1); i <= 5; i++ {
		if !BlockingQueue_Put(ctx, q, i) {
			t.Fatal("put failed")
		}
	}
	BlockingQueue_Close(ctx, q)
	BlockingQueue_Close(ctx, q)
	if r := Task_Join(ctx, worker); r.Failed || r.Val != 15 {
		t.Fatalf("worker = %+v", r)
	}
	if BlockingQueue_Put(ctx, q, 9) || !BlockingQueue_IsClosed(ctx, q) {
		t.Fatal("closed queue accepted put")
	}
	TaskGroup_Close(ctx, group)
}

func TestBlockingQueueCancellationUnblocks(t *testing.T) {
	ctx := RootExecution()
	q := NewBlockingQueue[int64](None[int64]())
	group := NewTaskGroup(None[Duration]())
	TaskGroup_Start(ctx, group, func(c *Execution) Unit { BlockingQueue_Take(c, q); return Unit{} })
	time.Sleep(10 * time.Millisecond)
	TaskGroup_Close(ctx, group)
	if BlockingQueue_Length(ctx, q) != 0 {
		t.Fatal("length")
	}
}

func TestPriorityQueueOrderAndStability(t *testing.T) {
	ctx := RootExecution()
	type item struct{ priority, id int64 }
	q := NewPriorityQueue(func(_ *Execution, a, b item) int64 { return a.priority - b.priority }, None[int64]())
	for i, p := range []int64{3, 1, 2, 1, 3, 1} {
		PriorityQueue_Enqueue(ctx, q, item{p, int64(i)})
	}
	var got []string
	for !PriorityQueue_IsEmpty(ctx, q) {
		peek := PriorityQueue_Peek(ctx, q)
		v := PriorityQueue_Dequeue(ctx, q)
		if peek.Val != v.Val {
			t.Fatal("peek differs from dequeue")
		}
		got = append(got, fmt.Sprint(v.Val.priority, ":", v.Val.id))
	}
	if want := "1:1 1:3 1:5 2:2 3:0 3:4"; strings.Join(got, " ") != want {
		t.Fatalf("got %v", got)
	}
}

func TestPriorityQueueComparatorFaultLeavesHeapIntact(t *testing.T) {
	ctx := RootExecution()
	fail := false
	q := NewPriorityQueue(func(_ *Execution, a, b int64) int64 {
		if fail {
			Raise("cmp")
		}
		return a - b
	}, Some(int64(3)))
	PriorityQueue_Enqueue(ctx, q, 2)
	PriorityQueue_Enqueue(ctx, q, 1)
	fail = true
	mustFault(t, "cmp", func() { PriorityQueue_Enqueue(ctx, q, 0) })
	fail = false
	if PriorityQueue_Length(ctx, q) != 2 || PriorityQueue_Dequeue(ctx, q).Val != 1 {
		t.Fatal("heap changed by failed enqueue")
	}
	PriorityQueue_Enqueue(ctx, q, 5)
	PriorityQueue_Enqueue(ctx, q, 6)
	if PriorityQueue_Enqueue(ctx, q, 7) {
		t.Fatal("capacity")
	}
}

func TestCheckCancelledAndYield(t *testing.T) {
	ctx := RootExecution()
	CheckCancelled(ctx)
	Tasks_YieldNow(ctx)
	cancelledCtx, cancel := cancelledExecution()
	cancel()
	func() {
		defer func() {
			if _, ok := recover().(cancelled); !ok {
				t.Fatal("no cancellation")
			}
		}()
		Tasks_YieldNow(cancelledCtx)
	}()
	// Shield ignores cancellation.
	CheckCancelled(Shield(cancelledCtx))
}

type testError string

func (e testError) Message(*Execution) string { return string(e) }
