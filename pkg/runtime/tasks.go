package msruntime

import (
	"context"
	"fmt"
	goruntime "runtime"
	"sync/atomic"
	"time"
)

type Execution struct {
	EqualityScope TypeScope
	Context       context.Context
	Owners        map[*Scheduler]bool
	TaskGroups    map[*TaskGroup]bool
	HostServices  map[*httpService]bool
	Lifetime      *workLifetime
	Host          *hostRoots
	calls         *callState
}

// callState tracks one goroutine's nested source calls. Copies of an
// Execution made for equality scopes or cancellation share it.
type callState struct {
	depth     atomic.Int64
	traceFull atomic.Bool
}

type cancelled struct{}

func RootExecution() *Execution {
	return &Execution{Context: context.Background(), Lifetime: &workLifetime{}, Host: &hostRoots{}, calls: &callState{}}
}
func CheckCancelled(ctx *Execution) {
	if ctx != nil && ctx.Context.Err() != nil {
		panic(cancelled{})
	}
}
func Shield(ctx *Execution) *Execution { return inherit(ctx, context.WithoutCancel(ctx.Context)) }
func Cleanup(ctx *Execution, resource Value) {
	pending := recover()
	var cleanup any
	func() {
		defer func() { cleanup = recover() }()
		Invoke(Shield(ctx), CleanupOperation(resource, ""), nil)
	}()
	if cleanup != nil {
		if primary, ok := pending.(Fault); ok {
			primary.Secondary = append(primary.Secondary, fmt.Sprint(cleanup))
			panic(primary)
		}
		panic(Fault{Message: fmt.Sprint(cleanup)})
	}
	if pending != nil {
		panic(pending)
	}
}
func StandardFunction(name, result string) Value {
	if value, ok := libraryFunction(name, result); ok {
		return value
	}
	switch name {
	case "panic":
		return NewFunction([]string{"message"}, "Never", func(_ *Execution, args []Value) Value { return Panic(args[0].(string)) })
	case "check_cancelled":
		return NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value { CheckCancelled(ctx); return Unit{} })
	case "sleep":
		return NewFunction([]string{"duration"}, "Unit", func(ctx *Execution, args []Value) Value {
			delay := args[0].(Duration)
			if delay < 0 {
				return durationParameterFault("sleep", "duration", args[0])
			}
			timer := time.NewTimer(time.Duration(delay))
			defer timer.Stop()
			select {
			case <-timer.C:
				return Unit{}
			case <-ctx.Context.Done():
				CheckCancelled(ctx)
				return Unit{}
			}
		})

	}
	return Panic("unavailable standard function " + name)
}

type CleanupAction struct {
	contract  string
	scope     TypeScope
	execution *Execution
	resource  Value
	done      bool
	stack     *CleanupStack
}

func NewCleanup(ctx *Execution, resource Value) *CleanupAction {
	return &CleanupAction{execution: ctx, resource: resource}
}
func (action *CleanupAction) Run() {
	defer profileRegion(action.execution, "with.cleanup")()
	pending := recover()
	var cleanup any
	if !action.done {
		action.done = true
		if action.stack != nil {
			action.stack.remove(action)
		}
		func() {
			defer func() { cleanup = recover() }()
			resource := action.resource
			action.resource = nil
			Invoke(Shield(action.execution), CleanupOperation(resource, action.contract, action.scope), nil)
		}()
	}
	if cleanup != nil {
		if primary, ok := pending.(Fault); ok {
			primary.Secondary = append(primary.Secondary, fmt.Sprint(cleanup))
			panic(primary)
		}
		panic(Fault{Message: fmt.Sprint(cleanup)})
	}
	if pending != nil {
		panic(pending)
	}
}

type CleanupStack struct{ actions []*CleanupAction }

func NewCleanupStack() *CleanupStack { return &CleanupStack{} }
func (stack *CleanupStack) Push(ctx *Execution, resource Value) *CleanupAction {
	return stack.PushContract(ctx, resource, "")
}
func (stack *CleanupStack) PushContract(ctx *Execution, resource Value, contract string, scopes ...TypeScope) *CleanupAction {
	action := NewCleanup(ctx, resource)
	action.contract = contract
	if len(scopes) > 0 {
		action.scope = scopes[0]
	}
	action.stack = stack
	stack.actions = append(stack.actions, action)
	return action
}
func (stack *CleanupStack) remove(action *CleanupAction) {
	for i := len(stack.actions) - 1; i >= 0; i-- {
		if stack.actions[i] == action {
			stack.actions = append(stack.actions[:i], stack.actions[i+1:]...)
			return
		}
	}
}
func (stack *CleanupStack) Unwind() {
	// Without actions there is nothing to run, and recovering only to
	// re-raise makes unwinding a deep stack quadratic.
	if len(stack.actions) == 0 {
		return
	}
	pending := recover()
	for len(stack.actions) > 0 {
		action := stack.actions[len(stack.actions)-1]
		var failure any
		func() { defer func() { failure = recover() }(); action.Run() }()
		if failure != nil {
			if primary, ok := pending.(Fault); ok {
				primary.Secondary = append(primary.Secondary, fmt.Sprint(failure))
				pending = primary
			} else {
				pending = Fault{Message: fmt.Sprint(failure)}
			}
		}
	}
	if pending != nil {
		panic(pending)
	}
}

func CleanupOperation(resource Value, contract string, scopes ...TypeScope) Value {
	if contract == "" {
		switch resource.(type) {
		case Struct, Record, Alternative:
			contract = "@std/Closeable"
		}
	}
	return Bind(resource, contract, "close", scopes...)
}

func init() {
	libraryAdd("tasks", "yield_now", "Unit", nil, func(ctx *Execution, _ string, _ []Value) Value {
		CheckCancelled(ctx)
		goruntime.Gosched()
		CheckCancelled(ctx)
		return Unit{}
	})
}

// Duration limits are displayed as their original signed nanosecond count.
func durationParameterFault(operation, parameter string, value Value) Value {
	if option, ok := value.(Alternative); ok && option.Tag == "some" {
		value = option.Fields[0]
	}
	return libraryRangeFault(operation, parameter+" (nanoseconds)", int64(value.(Duration)), 0, nativeUnlimited)
}
