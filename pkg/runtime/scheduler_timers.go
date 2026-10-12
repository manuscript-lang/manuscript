package msruntime

// Delayed and repeating work uses the same admission, reporting, cancellation,
// status, and joining path as immediate work.
func (s *Scheduler) schedule(ctx *Execution, delay Duration, repeating bool, operation Value) Value {
	result := "@std/Result[@std/OperationId][@std/StartError]"
	if delay < 0 || repeating && delay == 0 {
		return libraryError(result, "InvalidInput", "")
	}
	return s.startScheduled(ctx, NewFunction(nil, "@std/Result[Unit][String]", func(child *Execution, _ []Value) Value {
		for {
			Invoke(child, StandardFunction("sleep", "Unit"), []Argument{{"duration", delay}})
			outcome := Invoke(child, operation, nil).(Alternative)
			if !repeating || outcome.Tag == "error" {
				return outcome
			}
		}
	}), &scheduledOperation{delay, repeating, operation})
}

type scheduledOperation struct {
	delay     Duration
	repeating bool
	operation Value
}

func (s *Scheduler) restart(ctx *Execution, id OperationId) Value {
	result := "@std/Result[@std/OperationId][@std/StartError]"
	if ctx.Owners[s] {
		return Panic("a Scheduler operation cannot restart work in its own service")
	}
	s.mu.Lock()
	schedule, exists := s.schedules[id]
	if s.closing {
		s.mu.Unlock()
		return libraryError(result, "Closed", "")
	}
	if !exists {
		s.mu.Unlock()
		return libraryError(result, "InvalidInput", "")
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
