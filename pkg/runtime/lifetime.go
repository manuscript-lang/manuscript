package msruntime

import (
	"fmt"
	"sync"
)

// workCloser is a service (scheduler, task group) a work lifetime joins when
// its operation finishes, even when no `with` binding closed it.
type workCloser interface{ closeWork(ctx *Execution) }

// workLifetime lists the services one operation opened, so FinishExecution can
// join them in reverse order of opening.
type workLifetime struct {
	mu       sync.Mutex
	parent   *workLifetime
	services []workCloser
}

func registerResource(ctx *Execution, service workCloser) {
	if ctx.lifetime == nil {
		return
	}
	ctx.lifetime.mu.Lock()
	ctx.lifetime.services = append(ctx.lifetime.services, service)
	ctx.lifetime.mu.Unlock()
}

func unregisterResource(ctx *Execution, service workCloser) {
	if ctx.lifetime == nil {
		return
	}
	l := ctx.lifetime
	l.mu.Lock()
	defer l.mu.Unlock()
	for i, s := range l.services {
		if s == service {
			copy(l.services[i:], l.services[i+1:])
			last := len(l.services) - 1
			l.services[last] = nil
			l.services = l.services[:last]
			return
		}
	}
}

// FinishExecution joins services under the fixed work lifetime, even without a
// with binding. It is deferred: it re-raises a pending fault with any
// cleanup faults recorded as secondary.
func FinishExecution(ctx *Execution) {
	pending := recover()
	if l := ctx.lifetime; l != nil {
		for {
			l.mu.Lock()
			services := l.services
			if len(services) == 0 {
				l.mu.Unlock()
				break
			}
			service := services[len(services)-1]
			services[len(services)-1] = nil
			l.services = services[:len(services)-1]
			l.mu.Unlock()
			var failure any
			func() {
				defer func() { failure = recover() }()
				service.closeWork(Shield(ctx))
			}()
			if failure != nil {
				pending = addSecondary(pending, failure)
			}
		}
	}
	if pending != nil {
		panic(pending)
	}
}

// addSecondary records failure as a secondary cleanup fault of pending, or
// makes it the primary fault when nothing is pending.
func addSecondary(pending, failure any) any {
	if primary, ok := pending.(Fault); ok {
		primary.Secondary = append(primary.Secondary, fmt.Sprint(failure))
		return primary
	}
	return Fault{Message: fmt.Sprint(failure)}
}
