package msruntime

import (
	"context"
	"fmt"
	"reflect"
	"strings"
	"sync"
)

func ConstructWithContext(ctx *Execution, typ string, args []Argument) Value {
	name, _ := splitType(typ)
	switch name {
	case "@std/Queue":
		capacity := args[0].Value.(int64)
		if capacity <= 0 || capacity > int64(^uint(0)>>1) {
			return Panic("Queue capacity must be positive")
		}
		return &Queue{typ: typ, capacity: int(capacity), changed: make(chan struct{})}
	case "@std/Synchronized":
		return &Synchronized{typ: typ, value: args[0].Value, changed: make(chan struct{})}
	case "@std/Pool":
		return newPool(typ, args[0].Value.(List))
	case "@std/ListBuilder", "@std/MapBuilder", "@std/SetBuilder", "@std/BytesBuilder", "@std/StringBuilder":
		return newBuilder(typ)
	}
	return Construct(typ, args)
}

type Queue struct {
	mu       sync.Mutex
	typ      string
	capacity int
	items    []Value
	closed   bool
	changed  chan struct{}
}

func (q *Queue) notify() { close(q.changed); q.changed = make(chan struct{}) }
func (q *Queue) Operation(name string) Function {
	element := typeArguments(q.typ)[0]
	if name == "close" {
		return NewFunction(nil, "Unit", func(_ *Execution, _ []Value) Value {
			q.mu.Lock()
			defer q.mu.Unlock()
			if !q.closed {
				q.closed = true
				q.notify()
			}
			return Unit{}
		})
	}
	labels, result := []string{}, "@std/Optional["+element+"]"
	if name == "send" {
		labels = []string{"value"}
		result = "@std/Result[Unit][@std/QueueError]"
	}
	return NewFunction(labels, result, func(ctx *Execution, args []Value) Value {
		for {
			CheckCancelled(ctx)
			q.mu.Lock()
			if name == "send" {
				if q.closed {
					q.mu.Unlock()
					return Alternative{result, "error", []Value{Alternative{Type: "@std/QueueError", Tag: "Closed"}}}
				}
				if len(q.items) < q.capacity {
					q.items = append(q.items, args[0])
					q.notify()
					q.mu.Unlock()
					return Alternative{result, "ok", []Value{Unit{}}}
				}
			} else if name == "receive" {
				if len(q.items) > 0 {
					value := q.items[0]
					q.items[0] = nil
					q.items = q.items[1:]
					q.notify()
					q.mu.Unlock()
					return optional(element, value, true)
				}
				if q.closed {
					q.mu.Unlock()
					return optional(element, nil, false)
				}
			} else {
				q.mu.Unlock()
				return Panic("unknown Queue operation")
			}
			changed := q.changed
			q.mu.Unlock()
			select {
			case <-changed:
			case <-ctx.Context.Done():
				CheckCancelled(ctx)
			}
		}
	})
}

type Builder struct {
	mu     sync.Mutex
	typ    string
	value  Value
	sealed bool
}

func newBuilder(typ string) *Builder {
	name, args := splitType(typ)
	b := &Builder{typ: typ}
	switch name {
	case "@std/ListBuilder":
		b.value = List{"@std/List[" + args[0] + "]", nil}
	case "@std/MapBuilder":
		b.value = Map{"@std/Map[" + args[0] + "][" + args[1] + "]", nil}
	case "@std/SetBuilder":
		b.value = Set{"@std/Set[" + args[0] + "]", nil}
	case "@std/BytesBuilder":
		b.value = Bytes{}
	case "@std/StringBuilder":
		b.value = ""
	}
	return b
}
func (b *Builder) Operation(name string) Function {
	labels := []string{}
	if name == "append" || name == "with_value" {
		labels = []string{"value"}
	}
	if name == "with_entry" {
		labels = []string{"key", "value"}
	}
	if name == "concat" {
		labels = []string{"values"}
	}
	return NewFunction(labels, "", func(ctx *Execution, args []Value) Value {
		b.mu.Lock()
		defer b.mu.Unlock()
		if name == "freeze" {
			b.sealed = true
			return b.value
		}
		if b.sealed {
			return Panic("builder is sealed")
		}
		switch value := b.value.(type) {
		case List:
			value.Items = append(append([]Value{}, value.Items...), args[0])
			b.value = value
		case Map, Set:
			named := make([]Argument, len(args))
			for i, arg := range args {
				named[i] = Argument{labels[i], arg}
			}
			b.value = Invoke(ctx, NativeMember(value, name), named)
		case Bytes:
			if name == "concat" {
				value.Items = append(append([]byte{}, value.Items...), args[0].(Bytes).Items...)
			} else {
				n := args[0].(int64)
				if n < 0 || n > 255 {
					return Panic("byte value must be between 0 and 255")
				}
				value.Items = append(append([]byte{}, value.Items...), byte(n))
			}
			b.value = value
		case string:
			b.value = value + args[0].(string)
		}
		return Unit{}
	})
}

// A pool owns a fixed collection of shared closeable contract receivers.
type Pool struct {
	mu                   sync.Mutex
	typ                  string
	resources, available []Value
	leases               map[*Lease]bool
	closing              bool
	changed, done        chan struct{}
	fault                any
}

func newPool(typ string, resources List) *Pool {
	if len(resources.Items) == 0 {
		Panic("Pool requires at least one resource")
	}
	for i, resource := range resources.Items {
		view, ok := resource.(View)
		if !ok || view.Receiver == nil {
			Panic("Pool resources must be contract views")
		}
		for _, previous := range resources.Items[:i] {
			other := previous.(View)
			receiver := reflect.ValueOf(view.Receiver)
			if receiver.Type().Comparable() && reflect.TypeOf(other.Receiver) == receiver.Type() && view.Receiver == other.Receiver {
				Panic("Pool resources must be distinct")
			}
		}
	}
	return &Pool{typ: typ, resources: append([]Value{}, resources.Items...), available: append([]Value{}, resources.Items...), leases: map[*Lease]bool{}, changed: make(chan struct{}), done: make(chan struct{})}
}
func (p *Pool) notify() { close(p.changed); p.changed = make(chan struct{}) }
func (p *Pool) Operation(name string) Function {
	element := typeArguments(p.typ)[0]
	result := "@std/Result[@std/Lease[" + element + "]][@std/PoolError]"
	if name == "close" {
		return NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value { p.close(ctx); return Unit{} })
	}
	return NewAcquisition(nil, result, func(ctx *Execution, _ []Value) Value {
		for {
			CheckCancelled(ctx)
			p.mu.Lock()
			if p.closing {
				p.mu.Unlock()
				return Alternative{result, "error", []Value{Alternative{Type: "@std/PoolError", Tag: "Closed"}}}
			}
			if len(p.available) > 0 {
				value := p.available[0]
				p.available[0] = nil
				p.available = p.available[1:]
				lease := &Lease{pool: p, typ: "@std/Lease[" + element + "]", resource: value, changed: make(chan struct{}), done: make(chan struct{})}
				lease.context, lease.cancel = context.WithCancel(context.Background())
				p.leases[lease] = true
				p.mu.Unlock()
				return Alternative{result, "ok", []Value{lease}}
			}
			changed := p.changed
			p.mu.Unlock()
			select {
			case <-changed:
			case <-ctx.Context.Done():
				CheckCancelled(ctx)
			}
		}
	}, func(ctx *Execution, value Value) {
		result := value.(Alternative)
		if result.Tag == "ok" {
			result.Fields[0].(*Lease).close(ctx)
		}
	})
}
func (p *Pool) close(ctx *Execution) {
	for lease := range ctx.Leases {
		if lease.pool == p {
			Panic("pool cannot close from a leased operation")
		}
	}
	p.mu.Lock()
	if p.closing {
		done := p.done
		p.mu.Unlock()
		<-done
		if p.fault != nil {
			panic(p.fault)
		}
		return
	}
	p.closing = true
	p.notify()
	leases := make([]*Lease, 0, len(p.leases))
	for lease := range p.leases {
		leases = append(leases, lease)
	}
	p.mu.Unlock()
	var failure any
	for _, lease := range leases {
		lease.close(Shield(ctx))
	}
	for i := len(p.resources) - 1; i >= 0; i-- {
		func() {
			defer func() {
				if r := recover(); r != nil {
					if f, ok := failure.(Fault); ok {
						f.Secondary = append(f.Secondary, fmt.Sprint(r))
						failure = f
					} else {
						failure = Fault{Message: fmt.Sprint(r)}
					}
				}
			}()
			Invoke(Shield(ctx), Bind(p.resources[i], "", "close"), nil)
		}()
	}
	p.mu.Lock()
	p.resources = nil
	p.available = nil
	p.fault = failure
	close(p.done)
	p.mu.Unlock()
	if failure != nil {
		panic(failure)
	}
}

type Lease struct {
	mu       sync.Mutex
	pool     *Pool
	typ      string
	resource Value
	closed   bool
	active   int
	changed  chan struct{}
	done     chan struct{}
	context  context.Context
	cancel   context.CancelFunc
}

func (l *Lease) Operation(name string) Function {
	if name == "close" {
		return NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value { l.close(ctx); return Unit{} })
	}
	element := typeArguments(l.typ)[0]
	result := "@std/Result[" + element + "][@std/PoolError]"
	return NewFunction(nil, result, func(_ *Execution, _ []Value) Value {
		l.mu.Lock()
		defer l.mu.Unlock()
		if l.closed {
			return Alternative{result, "error", []Value{Alternative{Type: "@std/PoolError", Tag: "Closed"}}}
		}
		view := l.resource.(View)
		return Alternative{result, "ok", []Value{View{Type: view.Type, Receiver: &leaseReceiver{lease: l, value: view}, Scope: view.Scope}}}
	})
}
func (l *Lease) close(ctx *Execution) {
	if ctx.Leases[l] {
		Panic("lease cannot close its own operation")
	}
	l.mu.Lock()
	if l.closed {
		done := l.done
		l.mu.Unlock()
		<-done
		return
	}
	l.closed = true
	l.cancel()
	for l.active > 0 {
		changed := l.changed
		l.mu.Unlock()
		<-changed
		l.mu.Lock()
	}
	value := l.resource
	l.resource = nil
	l.mu.Unlock()
	l.pool.mu.Lock()
	delete(l.pool.leases, l)
	if !l.pool.closing {
		l.pool.available = append(l.pool.available, value)
	}
	l.pool.notify()
	l.pool.mu.Unlock()
	close(l.done)
}

type leaseReceiver struct {
	lease *Lease
	value Value
}

func (r *leaseReceiver) Operation(name string) Function {
	if name == "close" {
		return r.lease.Operation("close")
	}
	original := Bind(r.value, "", name).(Function)
	return NewFunction(original.Labels, original.Result, func(ctx *Execution, args []Value) Value {
		l := r.lease
		l.mu.Lock()
		if l.closed {
			l.mu.Unlock()
			if strings.Contains(original.Result, "@std/IoError") {
				return ioError(original.Result, "Closed", "")
			}
			return Panic("lease is closed")
		}
		l.active++
		l.mu.Unlock()
		defer func() { l.mu.Lock(); l.active--; close(l.changed); l.changed = make(chan struct{}); l.mu.Unlock() }()
		operation, cancel := context.WithCancel(ctx.Context)
		defer cancel()
		stop := context.AfterFunc(l.context, cancel)
		defer stop()

		execution := inherit(ctx, operation)
		execution.Leases = map[*Lease]bool{}
		for lease, owned := range ctx.Leases {
			execution.Leases[lease] = owned
		}
		execution.Leases[l] = true
		return func() (value Value) {
			defer func() {
				if failure := recover(); failure != nil {
					if _, cancelledHere := failure.(cancelled); cancelledHere && ctx.Context.Err() == nil && l.context.Err() != nil {
						if strings.Contains(original.Result, "@std/IoError") {
							value = ioError(original.Result, "Closed", "")
							return
						}
						Panic("lease closed during an operation")
					}
					panic(failure)
				}
			}()
			return original.Body(execution, args)
		}()
	})
}
