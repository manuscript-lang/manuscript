package rt

import (
	"context"
	"fmt"
	"sync"
	"time"
)

// Scheduler runs immediate, delayed, and repeating operations under the
// lifetime of the execution that first uses it. All state transitions share mu;
// user callbacks, reporters and cleanup run outside it.
//
// The constructor receives only the declared fields (the lowerer's
// New<Type> calls carry no execution), so the scheduler adopts the execution
// of its first operation as its fixed parent.
type Scheduler struct {
	limit        Option[int64]
	historyLimit Option[int64]
	drain        Option[Duration]
	reporter     Option[func(*Execution, SchedulerFailure) Unit]

	mu              sync.Mutex
	parent          *Execution
	context         context.Context
	cancel          context.CancelFunc
	closing, closed bool
	active          map[*OperationId]*schedulerJob
	history         map[*OperationId]WorkStatus
	schedules       map[*OperationId]scheduledOperation
	order           []*OperationId
	changed         chan struct{}
	done            chan struct{}
	jobs            sync.WaitGroup
	reports         []SchedulerFailure
	reportReady     chan struct{}
	reportClosed    bool
	reporting       sync.WaitGroup
	pending         int
}

type schedulerJob struct {
	id      *OperationId
	stop    context.CancelFunc
	stopped bool
	done    chan struct{}
}

type scheduledOperation struct {
	delay     Duration
	repeating bool
	operation func(*Execution) Result[Unit, Error]
}

// NewScheduler constructs a Scheduler from its declared fields in order.
func NewScheduler(limit, historyLimit Option[int64], drain Option[Duration], reporter Option[func(*Execution, SchedulerFailure) Unit]) *Scheduler {
	if limit.Some && limit.Val < 1 {
		rangeFault("Scheduler", "limit", 1, limit.Val)
	}
	if historyLimit.Some && historyLimit.Val < 0 {
		rangeFault("Scheduler", "history_limit", 0, historyLimit.Val)
	}
	if drain.Some && drain.Val < 0 {
		durationFault("Scheduler", "drain", int64(drain.Val))
	}
	return &Scheduler{limit: limit, historyLimit: historyLimit, drain: drain, reporter: reporter}
}

// adopt fixes the scheduler's parent execution on first use and starts its
// reporter. Caller holds no lock.
func (s *Scheduler) adopt(ctx *Execution) {
	s.mu.Lock()
	if s.parent != nil {
		s.mu.Unlock()
		return
	}
	s.parent = ctx
	s.context, s.cancel = context.WithCancel(ctx.Context)
	s.active = map[*OperationId]*schedulerJob{}
	s.history = map[*OperationId]WorkStatus{}
	s.schedules = map[*OperationId]scheduledOperation{}
	s.changed = make(chan struct{}, 1)
	s.done = make(chan struct{})
	s.reportReady = make(chan struct{}, 1)
	s.reporting.Add(1)
	s.mu.Unlock()
	registerResource(ctx, s)
	go s.reportLoop()
}

func (s *Scheduler) limitN() int {
	if s.limit.Some {
		return int(s.limit.Val)
	}
	return 0
}

func startFailed(e StartError) Result[*OperationId, StartError] {
	return Fail[*OperationId, StartError](e)
}

// Scheduler_Start runs operation right away as a background task.
func Scheduler_Start(ctx *Execution, s *Scheduler, operation func(*Execution) Result[Unit, Error]) Result[*OperationId, StartError] {
	return s.startScheduled(ctx, operation, nil)
}

// Scheduler_After runs operation once after duration.
func Scheduler_After(ctx *Execution, s *Scheduler, duration Duration, operation func(*Execution) Result[Unit, Error]) Result[*OperationId, StartError] {
	return s.schedule(ctx, duration, false, operation)
}

// Scheduler_Every runs operation repeatedly, sleeping interval between runs.
func Scheduler_Every(ctx *Execution, s *Scheduler, interval Duration, operation func(*Execution) Result[Unit, Error]) Result[*OperationId, StartError] {
	return s.schedule(ctx, interval, true, operation)
}

// Scheduler_Status reports the current or final status of an operation.
func Scheduler_Status(_ *Execution, s *Scheduler, id *OperationId) WorkStatus {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.parent == nil {
		return WorkStatus_Unknown{}
	}
	if s.active[id] != nil {
		return WorkStatus_Running{}
	}
	if status, ok := s.history[id]; ok {
		return status
	}
	return WorkStatus_Unknown{}
}

// Scheduler_Cancel requests cancellation without waiting.
func Scheduler_Cancel(_ *Execution, s *Scheduler, id *OperationId) Unit {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.parent == nil {
		return Unit{}
	}
	if job := s.active[id]; job != nil {
		job.stopped = true
		job.stop()
	}
	return Unit{}
}

// Scheduler_Close stops admission, drains, cancels the rest and joins.
func Scheduler_Close(ctx *Execution, s *Scheduler) Unit {
	s.adopt(ctx)
	s.close(ctx)
	return Unit{}
}

func (s *Scheduler) closeWork(ctx *Execution) { s.close(ctx) }

func (s *Scheduler) startScheduled(ctx *Execution, operation func(*Execution) Result[Unit, Error], schedule *scheduledOperation) Result[*OperationId, StartError] {
	CheckCancelled(ctx)
	s.adopt(ctx)
	s.mu.Lock()
	if s.closing || s.context.Err() != nil {
		s.mu.Unlock()
		return startFailed(StartError_Closed{})
	}
	if n := s.limitN(); n > 0 && len(s.active) >= n {
		s.mu.Unlock()
		return startFailed(StartError_Full{})
	}
	id := newOperationId()
	jobContext, cancel := context.WithCancel(s.context)
	job := &schedulerJob{id: id, stop: cancel, done: make(chan struct{})}
	if schedule != nil {
		s.schedules[id] = *schedule
	}
	s.active[id] = job
	s.jobs.Add(1)
	s.mu.Unlock()
	go func() {
		defer s.jobs.Done()
		defer close(job.done)
		var outcome Result[Unit, Error]
		var failed any
		func() {
			defer func() { failed = recover() }()
			child := s.parent.child(jobContext).ownedBy(s)
			defer FinishExecution(child)
			outcome = operation(child)
		}()
		s.commit(job, jobContext, outcome, failed)
		cancel()
	}()
	return Ok[*OperationId, StartError](id)
}

func (s *Scheduler) commit(job *schedulerJob, ctx context.Context, outcome Result[Unit, Error], fault any) {
	s.mu.Lock()
	var status WorkStatus = WorkStatus_Succeeded{}
	var report SchedulerFailure
	if fault != nil {
		if _, stopped := fault.(cancelled); stopped {
			status = WorkStatus_Cancelled{}
		} else {
			status = WorkStatus_Crashed{}
			report = SchedulerFailure_Crashed{Operation: job.id, Message: fmt.Sprint(fault)}
		}
	} else if job.stopped || ctx.Err() != nil {
		status = WorkStatus_Cancelled{}
	} else if outcome.Failed {
		status = WorkStatus_Failed{}
		report = SchedulerFailure_Failed{Operation: job.id, Cause: outcome.Err}
	}
	delete(s.active, job.id)
	history := int64(-1)
	if s.historyLimit.Some {
		history = s.historyLimit.Val
	}
	if history != 0 {
		s.history[job.id] = status
		s.order = append(s.order, job.id)
		if history > 0 && int64(len(s.order)) > history {
			delete(s.schedules, s.order[0])
			delete(s.history, s.order[0])
			s.order = s.order[1:]
		}
	} else {
		delete(s.schedules, job.id)
	}
	overflow := false
	if report != nil {
		if n := s.limitN(); n > 0 && s.pending >= n {
			overflow = true
		} else {
			s.pending++
			s.reports = append(s.reports, report)
		}
	}
	s.mu.Unlock()
	select {
	case s.changed <- struct{}{}:
	default:
	}
	if report != nil {
		if overflow {
			reportDiagnostic(fmt.Sprintf("scheduler %d: %s", job.id.number, failureText(report)))
			reportDiagnostic("Scheduler reporting capacity exceeded")
		} else {
			select {
			case s.reportReady <- struct{}{}:
			default:
			}
		}
	}
}

func failureOperation(f SchedulerFailure) *OperationId {
	switch f := f.(type) {
	case SchedulerFailure_Failed:
		return f.Operation
	case SchedulerFailure_Crashed:
		return f.Operation
	}
	return nil
}

// failureText renders a failure through its Error message. A faulting message
// implementation must not stop failure reporting.
func failureText(f SchedulerFailure) (text string) {
	switch f := f.(type) {
	case SchedulerFailure_Crashed:
		return f.Message
	case SchedulerFailure_Failed:
		defer func() {
			if recover() != nil {
				text = fmt.Sprint(f.Cause)
			}
		}()
		return f.Cause.Message(RootExecution())
	}
	return ""
}

func (s *Scheduler) reportLoop() {
	defer s.reporting.Done()
	for {
		s.mu.Lock()
		if len(s.reports) == 0 {
			closed := s.reportClosed
			s.mu.Unlock()
			if closed {
				return
			}
			<-s.reportReady
			continue
		}
		report := s.reports[0]
		s.reports[0] = nil
		s.reports = s.reports[1:]
		s.mu.Unlock()
		func() {
			defer func() {
				if r := recover(); r != nil {
					reportDiagnostic(fmt.Sprintf("scheduler %d: %s", failureOperation(report).number, failureText(report)))
					reportDiagnostic(fmt.Sprint("Scheduler reporter fault: ", r))
				}
			}()
			if !s.reporter.Some {
				reportDiagnostic("Scheduler failure: " + failureText(report))
				return
			}
			detached := context.WithoutCancel(s.context)
			child := s.parent.child(detached).ownedBy(s)
			defer FinishExecution(child)
			s.reporter.Val(child, report)
		}()
		s.mu.Lock()
		s.pending--
		s.mu.Unlock()
	}
}

func (s *Scheduler) close(ctx *Execution) {
	if ctx.isOwnedBy(s) {
		Raise("a Scheduler operation or reporter cannot close its own service")
	}
	s.mu.Lock()
	if s.closing {
		done := s.done
		s.mu.Unlock()
		<-done
		return
	}
	s.closing = true
	s.mu.Unlock()
	if s.drain.Some && s.drain.Val > 0 {
		timer := time.NewTimer(time.Duration(s.drain.Val))
		draining := true
		for draining {
			s.mu.Lock()
			empty := len(s.active) == 0
			s.mu.Unlock()
			if empty {
				break
			}
			select {
			case <-s.context.Done():
				draining = false
			case <-timer.C:
				draining = false
			case <-s.changed:
			}
		}
		timer.Stop()
	}
	s.mu.Lock()
	for _, job := range s.active {
		job.stopped = true
		job.stop()
	}
	s.mu.Unlock()
	s.cancel()
	s.jobs.Wait()
	s.mu.Lock()
	s.reportClosed = true
	s.mu.Unlock()
	select {
	case s.reportReady <- struct{}{}:
	default:
	}
	s.reporting.Wait()
	s.mu.Lock()
	s.closed = true
	close(s.done)
	s.mu.Unlock()
	unregisterResource(s.parent, s)
}

// schedule starts delayed (once) or repeating work through the same
// admission, reporting, cancellation, status and joining path as start.
func (s *Scheduler) schedule(ctx *Execution, delay Duration, repeating bool, operation func(*Execution) Result[Unit, Error]) Result[*OperationId, StartError] {
	if delay < 0 || repeating && delay == 0 {
		return startFailed(StartError_InvalidInput{})
	}
	return s.startScheduled(ctx, func(child *Execution) Result[Unit, Error] {
		for {
			sleepFor(child, time.Duration(delay))
			outcome := operation(child)
			if !repeating || outcome.Failed {
				return outcome
			}
		}
	}, &scheduledOperation{delay, repeating, operation})
}

// Scheduler_Restart cancels and joins an after/every operation, then starts
// its original schedule with a fresh id.
func Scheduler_Restart(ctx *Execution, s *Scheduler, id *OperationId) Result[*OperationId, StartError] {
	if ctx.isOwnedBy(s) {
		Raise("a Scheduler operation cannot restart work in its own service")
	}
	s.adopt(ctx)
	s.mu.Lock()
	schedule, exists := s.schedules[id]
	if s.closing {
		s.mu.Unlock()
		return startFailed(StartError_Closed{})
	}
	if !exists {
		s.mu.Unlock()
		return startFailed(StartError_InvalidInput{})
	}
	job := s.active[id]
	if job != nil {
		job.stopped = true
		job.stop()
	}
	s.mu.Unlock()
	if job != nil {
		select {
		case <-job.done:
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		}
	}
	return s.schedule(ctx, schedule.delay, schedule.repeating, schedule.operation)
}
