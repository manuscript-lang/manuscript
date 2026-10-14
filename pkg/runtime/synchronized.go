package msruntime

import "sync"

// Synchronized protects replacement of a value. Its mutex is held only during
// admission, value reads, set, and release, never while user code executes or waits.
type Synchronized struct {
	mu      sync.Mutex
	typ     string
	value   Value
	holder  *SynchronizedGuard
	changed chan struct{}
	waiters []chan struct{}
}

// SynchronizedGuard is an ordinary aliasable resource. The cell mutex makes
// access versus close atomic, including calls through saved method values.
type SynchronizedGuard struct {
	cell     *Synchronized
	owner    *Execution
	lifetime *workLifetime
	waiting  bool
	closed   bool
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
		if g.waiting {
			g.closed = true
		}
		return
	}
	s.holder = nil
	close(s.changed)
	s.changed = make(chan struct{})
}

func (g *SynchronizedGuard) Operation(name string) Function {
	if name == "get" || name == "value" {
		Panic("read-only accessor is not a method")
	}
	if name == "close" {
		return NewFunction(nil, "Unit", func(_ *Execution, _ []Value) Value {
			g.close()
			return Unit{}
		})
	}
	switch name {
	case "wait":
		return NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
			g.wait(ctx)
			return Unit{}
		})
	case "notify_all":
		return NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
			g.notifyAll(ctx)
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
			return Panic(closedGuardMessage)
		}
		switch name {
		case "set":
			s.value = args[0]
			return Unit{}
		default:
			return Panic("unknown SynchronizedGuard operation")
		}
	})
}

const closedGuardMessage = "Synchronized guard is closed; use the guard only inside its with block, and acquire a new one to access the value again"

// requireOwnedHolder faults unless g is the open holder and ctx is the
// operation that acquired it (including shielded views). Another task sharing
// the alias must not release or signal on behalf of the holder. Caller holds s.mu.
func (g *SynchronizedGuard) requireOwnedHolder(ctx *Execution) {
	if g.cell.holder != g {
		Panic(closedGuardMessage)
	}
	if g.owner != ctx && (ctx.Lifetime == nil || g.lifetime != ctx.Lifetime) {
		Panic("only the operation that acquired a Synchronized guard may wait or notify through it")
	}
}

// wait releases the lock, sleeps until notify_all, then reacquires the lock for
// the same guard. Cancellation wakes the waiter without reacquiring: the guard
// stays released, so a parent holding the lock while closing its waiters
// cannot deadlock. The with-scope close is then an idempotent no-op.
func (g *SynchronizedGuard) wait(ctx *Execution) {
	s := g.cell
	wake := make(chan struct{})
	func() {
		s.mu.Lock()
		defer s.mu.Unlock()
		g.requireOwnedHolder(ctx)
		s.waiters = append(s.waiters, wake)
		g.waiting = true
		s.holder = nil
		close(s.changed)
		s.changed = make(chan struct{})
	}()
	select {
	case <-wake:
	case <-ctx.Context.Done():
		g.abandonWait(wake)
		CheckCancelled(ctx)
	}
	for {
		if ctx.Context.Err() != nil {
			g.finishWait()
			CheckCancelled(ctx)
		}
		s.mu.Lock()
		if g.closed {
			g.waiting, g.closed = false, false
			s.mu.Unlock()
			Panic(closedGuardMessage)
		}
		if s.holder == nil {
			s.holder = g
			g.waiting = false
			s.mu.Unlock()
			return
		}
		changed := s.changed
		s.mu.Unlock()
		select {
		case <-changed:
		case <-ctx.Context.Done():
		}
	}
}

func (g *SynchronizedGuard) finishWait() {
	g.cell.mu.Lock()
	g.waiting = false
	g.cell.mu.Unlock()
}

// abandonWait removes a cancelled waiter. The guard stays released.
func (g *SynchronizedGuard) abandonWait(wake chan struct{}) {
	s := g.cell
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, w := range s.waiters {
		if w == wake {
			s.waiters = append(s.waiters[:i], s.waiters[i+1:]...)
			break
		}
	}
	g.waiting = false
}

func (g *SynchronizedGuard) notifyAll(ctx *Execution) {
	s := g.cell
	s.mu.Lock()
	defer s.mu.Unlock()
	g.requireOwnedHolder(ctx)
	for _, waiter := range s.waiters {
		close(waiter)
	}
	s.waiters = nil
}
