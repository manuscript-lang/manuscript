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

type backgroundJob struct {
	id      OperationId
	stop    context.CancelFunc
	stopped bool
}
type completionReport struct{ failure Alternative }
type Background struct {
	mu                  sync.Mutex
	parent              *Execution
	context             context.Context
	cancel              context.CancelFunc
	limit, historyLimit int
	drain               time.Duration
	reporter            Value
	closing, closed     bool
	active              map[OperationId]*backgroundJob
	history             map[OperationId]string
	order               []OperationId
	changed             chan struct{}
	done                chan struct{}
	jobs                sync.WaitGroup
	reports             chan completionReport
	reporting           sync.WaitGroup
	pending             int
}

func inherit(parent *Execution, ctx context.Context) *Execution {
	return &Execution{Context: ctx, Owners: parent.Owners, Leases: parent.Leases, HostServices: parent.HostServices, Lifetime: parent.Lifetime}
}
func owned(parent *Execution, ctx context.Context, owner *Background) *Execution {
	owners := map[*Background]bool{}
	for key, value := range parent.Owners {
		owners[key] = value
	}
	owners[owner] = true
	return &Execution{Context: ctx, Owners: owners, Leases: parent.Leases, HostServices: parent.HostServices, Lifetime: parent.Lifetime}
}
func NewBackground(ctx *Execution, args []Argument) Value {
	limit, historyLimit := int64(0), int64(128)
	drain := Duration(0)
	var reporter Value
	for _, a := range args {
		switch a.Name {
		case "limit":
			limit = a.Value.(int64)
		case "history_limit":
			historyLimit = a.Value.(int64)
		case "drain":
			drain = a.Value.(Duration)
		case "reporter":
			reporter = a.Value
		}
	}
	if limit <= 0 || historyLimit < 0 || drain < 0 || limit > int64(^uint(0)>>1) || historyLimit > int64(^uint(0)>>1) {
		return Panic("invalid Background limits")
	}
	parent, cancel := context.WithCancel(ctx.Context)
	b := &Background{parent: ctx, context: parent, cancel: cancel, limit: int(limit), historyLimit: int(historyLimit), drain: time.Duration(drain), reporter: reporter, active: map[OperationId]*backgroundJob{}, history: map[OperationId]string{}, changed: make(chan struct{}, 1), done: make(chan struct{}), reports: make(chan completionReport, int(limit))}
	registerService(ctx, b)
	b.reporting.Add(1)
	go b.reportLoop()
	return b
}
func (b *Background) Operation(name string) Function {
	switch name {
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
	return NewFunction(nil, "Never", func(_ *Execution, _ []Value) Value { return Panic("unavailable Background operation") })
}
func (b *Background) start(ctx *Execution, operation Value) Value {
	CheckCancelled(ctx)
	result := "@std/Result[@std/OperationId][@std/StartError]"
	b.mu.Lock()
	if b.closing || b.context.Err() != nil {
		b.mu.Unlock()
		return Alternative{result, "error", []Value{Alternative{Type: "@std/StartError", Tag: "Closed"}}}
	}
	if len(b.active) >= b.limit {
		b.mu.Unlock()
		return Alternative{result, "error", []Value{Alternative{Type: "@std/StartError", Tag: "Full"}}}
	}
	id := newOperationId()
	jobContext, cancel := context.WithCancel(b.context)
	job := &backgroundJob{id: id, stop: cancel}
	b.active[id] = job
	b.jobs.Add(1)
	b.mu.Unlock()
	go func() {
		defer b.jobs.Done()
		var outcome Value
		var failed any
		func() {
			defer func() { failed = recover() }()
			child := newExecution(owned(b.parent, jobContext, b), jobContext)
			defer FinishExecution(child)
			outcome = profileWork(child, "background.operation", fmt.Sprint(id), func(execution *Execution) Value { return Invoke(execution, operation, nil) })
		}()
		b.commit(job, jobContext, outcome, failed)
		cancel()
	}()
	return Alternative{result, "ok", []Value{id}}
}
func (b *Background) commit(job *backgroundJob, ctx context.Context, outcome Value, fault any) {
	b.mu.Lock()
	status := "Succeeded"
	var report *completionReport
	if fault != nil {
		if _, stopped := fault.(cancelled); stopped {
			status = "Cancelled"
		} else {
			status = "Crashed"
			report = &completionReport{Alternative{"@std/BackgroundFailure", "Crashed", []Value{job.id, fmt.Sprint(fault)}}}
		}
	} else if job.stopped || ctx.Err() != nil {
		status = "Cancelled"
	} else if result, ok := outcome.(Alternative); ok && result.Tag == "error" {
		status = "Failed"
		report = &completionReport{Alternative{"@std/BackgroundFailure", "Failed", []Value{job.id, result.Fields[0]}}}
	}
	delete(b.active, job.id)
	if b.historyLimit > 0 {
		b.history[job.id] = status
		b.order = append(b.order, job.id)
		if len(b.order) > b.historyLimit {
			delete(b.history, b.order[0])
			b.order = b.order[1:]
		}
	}
	overflow := false
	if report != nil {
		if b.pending >= b.limit {
			overflow = true
		} else {
			b.pending++
		}
	}
	b.mu.Unlock()
	select {
	case b.changed <- struct{}{}:
	default:
	}
	if report != nil {
		if overflow {
			reportDiagnostic(fmt.Sprintf("background %d: %v", job.id.number, report.failure.Fields[1]))
			reportDiagnostic("Background reporting capacity exceeded")
		} else {
			b.reports <- *report
		}
	}
}
func (b *Background) reportLoop() {
	defer b.reporting.Done()
	for report := range b.reports {
		func() {
			defer func() {
				if r := recover(); r != nil {
					reportDiagnostic(fmt.Sprintf("background %v: %v", report.failure.Fields[0], report.failure.Fields[1]))
					reportDiagnostic(fmt.Sprint("Background reporter fault: ", r))
				}
			}()
			if b.reporter == nil {
				reportDiagnostic(fmt.Sprint("Background failure: ", report.failure.Fields[1]))
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
func (b *Background) close(ctx *Execution) {
	if ctx.Owners[b] {
		Panic("a Background operation or reporter cannot close its own service")
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
	close(b.reports)
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
