package msruntime

import (
	"context"
	"fmt"
	"os"
	"sync"
	"sync/atomic"
	"time"
)

type OperationId struct{ number uint64 }

var nextOperation atomic.Uint64

func newOperationId() OperationId { return OperationId{nextOperation.Add(1)} }

type schedulerJob struct {
	id      OperationId
	stop    context.CancelFunc
	stopped bool
	done    chan struct{}
}
type completionReport struct{ failure Alternative }
type Scheduler struct {
	mu                  sync.Mutex
	parent              *Execution
	context             context.Context
	cancel              context.CancelFunc
	limit, historyLimit int
	drain               time.Duration
	reporter            Value
	closing, closed     bool
	active              map[OperationId]*schedulerJob
	history             map[OperationId]string
	schedules           map[OperationId]scheduledOperation
	order               []OperationId
	changed             chan struct{}
	done                chan struct{}
	jobs                sync.WaitGroup
	reports             []completionReport
	reportReady         chan struct{}
	reportClosed        bool
	reporting           sync.WaitGroup
	pending             int
}

func inherit(parent *Execution, ctx context.Context) *Execution {
	return &Execution{EqualityScope: parent.EqualityScope, Context: ctx, Owners: parent.Owners, TaskGroups: parent.TaskGroups, HostServices: parent.HostServices, Lifetime: parent.Lifetime, Host: parent.Host, calls: &callState{}}
}
func owned(parent *Execution, ctx context.Context, owner *Scheduler) *Execution {
	owners := map[*Scheduler]bool{}
	for key, value := range parent.Owners {
		owners[key] = value
	}
	owners[owner] = true
	return &Execution{EqualityScope: parent.EqualityScope, Context: ctx, Owners: owners, TaskGroups: parent.TaskGroups, HostServices: parent.HostServices, Lifetime: parent.Lifetime, Host: parent.Host, calls: &callState{}}
}
func NewScheduler(ctx *Execution, args []Argument) Value {
	limit, historyLimit := int64(0), int64(-1)
	drain := Duration(0)
	var reporter Value
	for _, a := range args {
		switch a.Name {
		case "limit":
			value, valid := nativeOption(a.Value, "Int", int64(0))
			if !valid {
				return libraryRangeFault("Scheduler", "limit", a.Value, 1, int64(^uint(0)>>1))
			}
			limit = value.(int64)
			if limit == 0 && a.Value != nil {
				if v, ok := a.Value.(Alternative); !ok || v.Tag != "none" {
					return libraryRangeFault("Scheduler", "limit", a.Value, 1, int64(^uint(0)>>1))
				}
			}
		case "history_limit":
			value, valid := nativeOption(a.Value, "Int", int64(-1))
			if !valid {
				return libraryRangeFault("Scheduler", "history_limit", a.Value, 0, int64(^uint(0)>>1))
			}
			historyLimit = value.(int64)
		case "drain":
			value, valid := nativeOption(a.Value, "Duration", Duration(0))
			if !valid {
				return durationParameterFault("Scheduler", "drain", a.Value)
			}
			drain = value.(Duration)
		case "reporter":
			reporter, _ = nativeOption(a.Value, "fn", nil)
		}
	}
	if limit < 0 || limit > int64(^uint(0)>>1) {
		return libraryRangeFault("Scheduler", "limit", limit, 1, int64(^uint(0)>>1))
	}
	if historyLimit < -1 || historyLimit > int64(^uint(0)>>1) {
		return libraryRangeFault("Scheduler", "history_limit", historyLimit, 0, int64(^uint(0)>>1))
	}
	if drain < 0 {
		return durationParameterFault("Scheduler", "drain", drain)
	}
	parent, cancel := context.WithCancel(ctx.Context)
	b := &Scheduler{parent: ctx, context: parent, cancel: cancel, limit: int(limit), historyLimit: int(historyLimit), drain: time.Duration(drain), reporter: reporter, active: map[OperationId]*schedulerJob{}, history: map[OperationId]string{}, schedules: map[OperationId]scheduledOperation{}, changed: make(chan struct{}, 1), done: make(chan struct{}), reportReady: make(chan struct{}, 1)}
	registerService(ctx, b)
	b.reporting.Add(1)
	markConcurrent()
	go b.reportLoop()
	return b
}
func (b *Scheduler) Operation(name string) Function {
	switch name {
	case "after", "every":
		label := "duration"
		if name == "every" {
			label = "interval"
		}
		return NewFunction([]string{label, "operation"}, "@std/Result[@std/OperationId][@std/StartError]", func(ctx *Execution, args []Value) Value {
			return b.schedule(ctx, args[0].(Duration), name == "every", args[1])
		})
	case "restart":
		return NewFunction([]string{"id"}, "@std/Result[@std/OperationId][@std/StartError]", func(ctx *Execution, args []Value) Value { return b.restart(ctx, args[0].(OperationId)) })
	case "start":
		return NewFunction([]string{"operation"}, "@std/Result[@std/OperationId][@std/StartError]", func(ctx *Execution, args []Value) Value { return b.start(ctx, args[0]) })
	case "status":
		return NewFunction([]string{"id"}, "@std/WorkStatus", func(_ *Execution, args []Value) Value {
			b.mu.Lock()
			defer b.mu.Unlock()
			id := args[0].(OperationId)
			status := "Unknown"
			if b.active[id] != nil {
				status = "Running"
			} else if s := b.history[id]; s != "" {
				status = s
			}
			return Alternative{Type: "@std/WorkStatus", Tag: status}
		})
	case "cancel":
		return NewFunction([]string{"id"}, "Unit", func(_ *Execution, args []Value) Value {
			b.mu.Lock()
			defer b.mu.Unlock()
			if job := b.active[args[0].(OperationId)]; job != nil {
				job.stopped = true
				job.stop()
			}
			return Unit{}
		})
	case "close":
		return NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value { b.close(ctx); return Unit{} })
	}
	return NewFunction(nil, "Never", func(_ *Execution, _ []Value) Value { return Panic("unavailable Scheduler operation") })
}
func (b *Scheduler) start(ctx *Execution, operation Value) Value {
	return b.startScheduled(ctx, operation, nil)
}
func (b *Scheduler) startScheduled(ctx *Execution, operation Value, schedule *scheduledOperation) Value {
	CheckCancelled(ctx)
	result := "@std/Result[@std/OperationId][@std/StartError]"
	b.mu.Lock()
	if b.closing || b.context.Err() != nil {
		b.mu.Unlock()
		return Alternative{result, "error", []Value{Alternative{Type: "@std/StartError", Tag: "Closed"}}}
	}
	if b.limit > 0 && len(b.active) >= b.limit {
		b.mu.Unlock()
		return Alternative{result, "error", []Value{Alternative{Type: "@std/StartError", Tag: "Full"}}}
	}
	id := newOperationId()
	jobContext, cancel := context.WithCancel(b.context)
	job := &schedulerJob{id: id, stop: cancel, done: make(chan struct{})}
	if schedule != nil {
		b.schedules[id] = *schedule
	}
	b.active[id] = job
	b.jobs.Add(1)
	b.mu.Unlock()
	markConcurrent()
	go func() {
		defer b.jobs.Done()
		defer close(job.done)
		var outcome Value
		var failed any
		func() {
			defer func() { failed = recover() }()
			child := newExecution(owned(b.parent, jobContext, b), jobContext)
			defer FinishExecution(child)
			outcome = profileWork(child, "scheduler.operation", fmt.Sprint(id), func(execution *Execution) Value { return Invoke(execution, operation, nil) })
		}()
		b.commit(job, jobContext, outcome, failed)
		cancel()
	}()
	return Alternative{result, "ok", []Value{id}}
}
func (b *Scheduler) commit(job *schedulerJob, ctx context.Context, outcome Value, fault any) {
	b.mu.Lock()
	status := "Succeeded"
	var report *completionReport
	if fault != nil {
		if _, stopped := fault.(cancelled); stopped {
			status = "Cancelled"
		} else {
			status = "Crashed"
			report = &completionReport{Alternative{"@std/SchedulerFailure", "Crashed", []Value{job.id, fmt.Sprint(fault)}}}
		}
	} else if job.stopped || ctx.Err() != nil {
		status = "Cancelled"
	} else if result, ok := outcome.(Alternative); ok && result.Tag == "error" {
		status = "Failed"
		report = &completionReport{Alternative{"@std/SchedulerFailure", "Failed", []Value{job.id, result.Fields[0]}}}
	}
	delete(b.active, job.id)
	if b.historyLimit != 0 {
		b.history[job.id] = status
		b.order = append(b.order, job.id)
		if b.historyLimit > 0 && len(b.order) > b.historyLimit {
			delete(b.schedules, b.order[0])
			delete(b.history, b.order[0])
			b.order = b.order[1:]
		}
	}
	if b.historyLimit == 0 {
		delete(b.schedules, job.id)
	}
	overflow := false
	if report != nil {
		if b.limit > 0 && b.pending >= b.limit {
			overflow = true
		} else {
			b.pending++
			b.reports = append(b.reports, *report)
		}
	}
	b.mu.Unlock()
	select {
	case b.changed <- struct{}{}:
	default:
	}
	if report != nil {
		if overflow {
			reportDiagnostic(fmt.Sprintf("scheduler %d: %v", job.id.number, report.failure.Fields[1]))
			reportDiagnostic("Scheduler reporting capacity exceeded")
		} else {
			select {
			case b.reportReady <- struct{}{}:
			default:
			}
		}
	}
}
func (b *Scheduler) reportLoop() {
	defer b.reporting.Done()
	for {
		b.mu.Lock()
		if len(b.reports) == 0 {
			closed := b.reportClosed
			b.mu.Unlock()
			if closed {
				return
			}
			<-b.reportReady
			continue
		}
		report := b.reports[0]
		b.reports[0] = completionReport{}
		b.reports = b.reports[1:]
		b.mu.Unlock()
		func() {
			defer func() {
				if r := recover(); r != nil {
					reportDiagnostic(fmt.Sprintf("scheduler %v: %v", report.failure.Fields[0], schedulerCauseText(report.failure.Fields[1])))
					reportDiagnostic(fmt.Sprint("Scheduler reporter fault: ", r))
				}
			}()
			if b.reporter == nil {
				reportDiagnostic(fmt.Sprint("Scheduler failure: ", schedulerCauseText(report.failure.Fields[1])))
			} else {
				child := newExecution(owned(b.parent, context.WithoutCancel(b.context), b), context.WithoutCancel(b.context))
				defer FinishExecution(child)
				Invoke(child, b.reporter, []Argument{{"failure", report.failure}})
			}
		}()
		b.mu.Lock()
		b.pending--
		b.mu.Unlock()
	}
}
func (b *Scheduler) close(ctx *Execution) {
	if ctx.Owners[b] {
		Panic("a Scheduler operation or reporter cannot close its own service")
	}
	b.mu.Lock()
	if b.closing {
		done := b.done
		b.mu.Unlock()
		<-done
		return
	}
	b.closing = true
	b.mu.Unlock()
	if b.drain > 0 {
		timer := time.NewTimer(b.drain)
		draining := true
		for draining {
			b.mu.Lock()
			empty := len(b.active) == 0
			b.mu.Unlock()
			if empty {
				break
			}
			select {
			case <-b.context.Done():
				draining = false
			case <-timer.C:
				draining = false
			case <-b.changed:
			}
		}
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
	}
	b.mu.Lock()
	for _, job := range b.active {
		job.stopped = true
		job.stop()
	}
	b.mu.Unlock()
	b.cancel()
	b.jobs.Wait()
	b.mu.Lock()
	b.reportClosed = true
	b.mu.Unlock()
	select {
	case b.reportReady <- struct{}{}:
	default:
	}
	b.reporting.Wait()
	b.mu.Lock()
	b.closed = true
	unregisterService(b.parent, b)
	close(b.done)
	b.mu.Unlock()
}

var diagnostics = struct {
	queue    chan string
	work     sync.WaitGroup
	overflow atomic.Uint64
}{queue: make(chan string, 128)}

func init() {
	// The writer touches only strings, never records, so it does not mark
	// concurrent work; every goroutine that runs user code marks it itself.
	go func() {
		for message := range diagnostics.queue {
			fmt.Fprintln(os.Stderr, message)
			diagnostics.work.Done()
		}
	}()
}
func reportDiagnostic(message string) {
	diagnostics.work.Add(1)
	select {
	case diagnostics.queue <- message:
	default:
		diagnostics.work.Done()
		diagnostics.overflow.Add(1)
		fmt.Fprintln(os.Stderr, "runtime diagnostic buffer overflow")
	}
}
func FlushDiagnostics() { diagnostics.work.Wait() }

// schedulerCauseText renders a Failed cause through its Error message. Crashed
// reports already carry text. A faulting message implementation must not stop
// failure reporting.
func schedulerCauseText(cause Value) (text string) {
	if text, ok := cause.(string); ok {
		return text
	}
	defer func() {
		if recover() != nil {
			text = fmt.Sprint(cause)
		}
	}()
	return fmt.Sprint(Invoke(RootExecution(), Bind(cause, "@std/Error", "message"), nil))
}
