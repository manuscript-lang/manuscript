package rt

import (
	"fmt"
)

// CleanupAction is one registered `with` close operation.
type CleanupAction struct {
	ctx   *Execution
	close func(*Execution)
	stack *CleanupStack
	done  bool
}

// CleanupStack holds the close operations a function has registered, in
// registration order. A function that uses `with` creates one and defers
// Unwind, which closes whatever is still registered when the function exits
// by return, error, fault, or cancellation.
type CleanupStack struct{ actions []*CleanupAction }

// Push registers close to run, shielded from cancellation, at scope exit.
func (s *CleanupStack) Push(ctx *Execution, close func(*Execution)) *CleanupAction {
	action := &CleanupAction{ctx: ctx, close: close, stack: s}
	s.actions = append(s.actions, action)
	return action
}

func (s *CleanupStack) remove(action *CleanupAction) {
	for i := len(s.actions) - 1; i >= 0; i-- {
		if s.actions[i] == action {
			s.actions = append(s.actions[:i], s.actions[i+1:]...)
			return
		}
	}
}

// Run closes the resource once. A fault in the close becomes primary unless a
// fault is already pending, in which case it is recorded as secondary.
func (a *CleanupAction) Run() {
	pending := recover()
	var failure any
	if !a.done {
		a.done = true
		a.stack.remove(a)
		close := a.close
		a.close = nil
		func() {
			defer func() { failure = recover() }()
			close(Shield(a.ctx))
		}()
	}
	if failure != nil {
		if primary, ok := pending.(Fault); ok {
			primary.Secondary = append(primary.Secondary, fmt.Sprint(failure))
			panic(primary)
		}
		panic(Fault{Message: fmt.Sprint(failure)})
	}
	if pending != nil {
		panic(pending)
	}
}

// Unwind runs every registered action, innermost first.
func (s *CleanupStack) Unwind() {
	if len(s.actions) == 0 {
		return
	}
	var failures []any
	for len(s.actions) > 0 {
		action := s.actions[len(s.actions)-1]
		var failure any
		func() { defer func() { failure = recover() }(); action.Run() }()
		if failure != nil {
			failures = append(failures, failure)
		}
	}
	if len(failures) == 0 {
		return
	}
	pending := recover()
	for _, failure := range failures {
		if primary, ok := pending.(Fault); ok {
			primary.Secondary = append(primary.Secondary, fmt.Sprint(failure))
			pending = primary
		} else {
			pending = Fault{Message: fmt.Sprint(failure)}
		}
	}
	panic(pending)
}
