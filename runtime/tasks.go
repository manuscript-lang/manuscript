package msruntime

import (
	"context"
	"fmt"
	"sync"
	"time"
)

type Execution struct {
	Context      context.Context
	Owners       map[*Background]bool
	Leases       map[*Lease]bool
	HostServices map[*httpService]bool
	Lifetime     *workLifetime
}
type cancelled struct{}

func RootExecution() *Execution {
	return &Execution{Context: context.Background(), Lifetime: &workLifetime{}}
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
				return Panic("sleep duration must be nonnegative")
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
	case "map_error":
		return NewFunction([]string{"result", "transform"}, result, func(ctx *Execution, args []Value) Value {
			outcome := args[0].(Alternative)
			if outcome.Tag == "ok" {
				return Alternative{result, "ok", outcome.Fields}
			}
			cause := Invoke(ctx, args[1], []Argument{{"cause", outcome.Fields[0]}})
			return Alternative{result, "error", []Value{cause}}
		})
	}
	return Panic("unavailable standard function " + name)
}
func Parallel(ctx *Execution, result string, tasks []Value, timeout *Duration) Value {
	operations := make([]func(*Execution) Value, len(tasks))
	for i, task := range tasks {
		f := task
		operations[i] = func(child *Execution) Value { return Invoke(child, f, nil) }
	}
	values, failure := joined(ctx, operations, len(tasks), timeout)
	if failure != nil {
		return Alternative{result, "error", []Value{failure}}
	}
	return Alternative{result, "ok", []Value{Pack{values}}}
}
func ParallelMap(ctx *Execution, result, listType string, args []Argument) Value {
	var items List
	var operation Value
	limit := int64(0)
	var timeout *Duration
	for _, a := range args {
		switch a.Name {
		case "items":
			items = a.Value.(List)
		case "operation":
			operation = a.Value
		case "limit":
			limit = a.Value.(int64)
		case "timeout":
			v := a.Value.(Duration)
			timeout = &v
		}
	}
	if limit <= 0 {
		return Panic("parallel_map limit must be positive")
	}
	operations := make([]func(*Execution) Value, len(items.Items))
	for i, item := range items.Items {
		value := item
		operations[i] = func(child *Execution) Value { return Invoke(child, operation, []Argument{{"item", value}}) }
	}
	if limit > int64(len(operations)) {
		limit = int64(len(operations))
	}
	values, failure := joined(ctx, operations, int(limit), timeout)
	if failure != nil {
		return Alternative{result, "error", []Value{failure}}
	}
	return Alternative{result, "ok", []Value{List{listType, values}}}
}
func joined(parent *Execution, operations []func(*Execution) Value, limit int, timeout *Duration) ([]Value, Value) {
	CheckCancelled(parent)
	if timeout != nil && *timeout < 0 {
		Panic("timeout must be nonnegative")
	}
	if len(operations) == 0 {
		return []Value{}, nil
	}
	group, cancel := context.WithCancel(parent.Context)
	defer cancel()
	var timer *time.Timer
	var mu sync.Mutex
	stopped := false
	timedOut := false
	var primary Value
	committed := 0
	finished := false
	stop := func(expired bool, fault any) {
		mu.Lock()
		defer mu.Unlock()
		if expired && finished {
			return
		}
		if fault != nil && primary == nil {
			primary = Alternative{Type: "@std/ExecutionError", Tag: "Crashed", Fields: []Value{newOperationId(), fmt.Sprint(fault)}}
		}
		if !stopped {
			stopped = true
			timedOut = expired
			cancel()
		}
	}
	if timeout != nil {
		if *timeout == 0 {
			stop(true, nil)
		} else {
			timer = time.AfterFunc(time.Duration(*timeout), func() { stop(true, nil) })
			defer timer.Stop()
		}
	}
	values := make([]Value, len(operations))
	if len(operations) == 0 {
		return values, nil
	}
	next := 0
	var workers sync.WaitGroup
	for worker := 0; worker < limit; worker++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for {
				mu.Lock()
				if stopped || group.Err() != nil || next >= len(operations) {
					mu.Unlock()
					return
				}
				index := next
				next++
				mu.Unlock()
				func() {
					defer func() {
						if r := recover(); r != nil {
							if _, ok := r.(cancelled); !ok {
								stop(false, r)
							}
						}
					}()
					value := func() Value {
						child := newExecution(parent, group)
						defer FinishExecution(child)
						return operations[index](child)
					}()
					mu.Lock()
					if !stopped && group.Err() == nil {
						values[index] = value
						committed++
						if committed == len(operations) {
							finished = true
						}
					}
					mu.Unlock()
				}()
			}
		}()
	}
	workers.Wait()
	mu.Lock()
	defer mu.Unlock()
	CheckCancelled(parent)
	if primary != nil {
		return nil, primary
	}
	if timedOut {
		return nil, Alternative{Type: "@std/ExecutionError", Tag: "TimedOut"}
	}
	return values, nil
}

type CleanupAction struct {
	contract  string
	execution *Execution
	resource  Value
	done      bool
	stack     *CleanupStack
}

func NewCleanup(ctx *Execution, resource Value) *CleanupAction {
	return &CleanupAction{execution: ctx, resource: resource}
}
func (action *CleanupAction) Run() {
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
			Invoke(Shield(action.execution), CleanupOperation(resource, action.contract), nil)
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
func ParallelArguments(ctx *Execution, result string, args []Argument) Value {
	var tasks []Value
	var timeout *Duration
	for _, a := range args {
		if a.Name == "tasks" {
			tasks = a.Value.(Pack).Items
		} else if a.Name == "timeout" {
			value := a.Value.(Duration)
			timeout = &value
		}
	}
	return Parallel(ctx, result, tasks, timeout)
}

type CleanupStack struct{ actions []*CleanupAction }

func NewCleanupStack() *CleanupStack { return &CleanupStack{} }
func (stack *CleanupStack) Push(ctx *Execution, resource Value) *CleanupAction {
	return stack.PushContract(ctx, resource, "")
}
func (stack *CleanupStack) PushContract(ctx *Execution, resource Value, contract string) *CleanupAction {
	action := NewCleanup(ctx, resource)
	action.contract = contract
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

func CleanupOperation(resource Value, contract string) Value {
	if contract == "" {
		switch resource.(type) {
		case Record, Alternative:
			contract = "@std/Closeable"
		}
	}
	return Bind(resource, contract, "close")
}
