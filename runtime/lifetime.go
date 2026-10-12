package msruntime

import (
	"context"
	"fmt"
	"sync"
)

type workLifetime struct {
	mu       sync.Mutex
	parent   *workLifetime
	services []Value
}

func newExecution(parent *Execution, ctx context.Context) *Execution {
	execution := inherit(parent, ctx)
	execution.Lifetime = &workLifetime{parent: parent.Lifetime}
	return execution
}
func registerService(execution *Execution, service *Background) {
	registerResource(execution, service)
}
func registerResource(execution *Execution, service Value) {
	if execution.Lifetime == nil {
		return
	}
	execution.Lifetime.mu.Lock()
	execution.Lifetime.services = append(execution.Lifetime.services, service)
	execution.Lifetime.mu.Unlock()
}
func unregisterService(execution *Execution, service *Background) {
	unregisterResource(execution, service)
}
func unregisterResource(execution *Execution, service Value) {
	if execution.Lifetime == nil {
		return
	}
	execution.Lifetime.mu.Lock()
	defer execution.Lifetime.mu.Unlock()
	for i, s := range execution.Lifetime.services {
		if s == service {
			copy(execution.Lifetime.services[i:], execution.Lifetime.services[i+1:])
			last := len(execution.Lifetime.services) - 1
			execution.Lifetime.services[last] = nil
			execution.Lifetime.services = execution.Lifetime.services[:last]
			return
		}
	}
}

// FinishExecution joins services under the fixed work lifetime, even without a with binding.
func FinishExecution(execution *Execution) {
	pending := recover()
	if execution.Lifetime != nil {
		for {
			execution.Lifetime.mu.Lock()
			services := execution.Lifetime.services
			if len(services) == 0 {
				execution.Lifetime.mu.Unlock()
				break
			}
			service := services[len(services)-1]
			services[len(services)-1] = nil
			execution.Lifetime.services = services[:len(services)-1]
			execution.Lifetime.mu.Unlock()
			var failure any
			func() {
				defer func() { failure = recover() }()
				Invoke(Shield(execution), Bind(service, "", "close"), nil)
			}()
			if failure != nil {
				if primary, ok := pending.(Fault); ok {
					primary.Secondary = append(primary.Secondary, fmt.Sprint(failure))
					pending = primary
				} else {
					pending = Fault{Message: fmt.Sprint(failure)}
				}
			}
		}
	}
	if pending != nil {
		panic(pending)
	}
}
