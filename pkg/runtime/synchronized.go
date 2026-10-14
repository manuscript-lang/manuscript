package msruntime

import "sync"

// Synchronized protects replacement of a value. Its mutex is held only during
// admission, get/set, and release, never while user code executes or waits.
type Synchronized struct {
	mu      sync.Mutex
	typ     string
	value   Value
	holder  *SynchronizedGuard
	changed chan struct{}
}

// SynchronizedGuard is an ordinary aliasable resource. The cell mutex makes
// access versus close atomic, including calls through saved method values.
type SynchronizedGuard struct {
	cell     *Synchronized
	owner    *Execution
	lifetime *workLifetime
}

func (s *Synchronized) Operation(name string) Function {
	if name != "lock" {
		Panic("unknown Synchronized operation")
	}
	return NewAcquisition(nil, "@std/SynchronizedGuard["+typeArguments(s.typ)[0]+"]", func(ctx *Execution, _ []Value) Value {
		for {
			CheckCancelled(ctx)
			s.mu.Lock()
			if s.holder == nil {
				guard := &SynchronizedGuard{cell: s, owner: ctx, lifetime: ctx.Lifetime}
				s.holder = guard
				s.mu.Unlock()
				return guard
			}
			reentrant := s.holder.owner == ctx || ctx.Lifetime != nil && s.holder.lifetime == ctx.Lifetime
			changed := s.changed
			s.mu.Unlock()
			if reentrant {
				return Panic("cannot acquire a Synchronized lock held by this operation")
			}
			select {
			case <-changed:
			case <-ctx.Context.Done():
				CheckCancelled(ctx)
			}
		}
	}, func(_ *Execution, value Value) { value.(*SynchronizedGuard).close() })
}

func (g *SynchronizedGuard) close() {
	s := g.cell
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.holder != g {
		return
	}
	s.holder = nil
	close(s.changed)
	s.changed = make(chan struct{})
}

func (g *SynchronizedGuard) Operation(name string) Function {
	if name == "close" {
		return NewFunction(nil, "Unit", func(_ *Execution, _ []Value) Value {
			g.close()
			return Unit{}
		})
	}
	labels, result := []string{}, typeArguments(g.cell.typ)[0]
	if name == "set" {
		labels, result = []string{"value"}, "Unit"
	}
	return NewFunction(labels, result, func(_ *Execution, args []Value) Value {
		s := g.cell
		s.mu.Lock()
		defer s.mu.Unlock()
		if s.holder != g {
			return Panic("Synchronized guard is closed; use the guard only inside its with block, and acquire a new one to access the value again")
		}
		switch name {
		case "get":
			return s.value
		case "set":
			s.value = args[0]
			return Unit{}
		default:
			return Panic("unknown SynchronizedGuard operation")
		}
	})
}
