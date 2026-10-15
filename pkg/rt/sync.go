package rt

import "sync"

// Synchronized protects replacement of a value shared across tasks. Its mutex
// is held only during admission, value reads, set, and release, never while
// user code executes or waits.
//
// This is the only synchronized mutation path of the typed runtime. The old
// runtime locked collections and record fields implicitly; here lists, maps,
// sets and records are plain data shared by aliases, and concurrent access to
// them must go through a Synchronized guard.
type Synchronized[T any] struct {
	mu      sync.Mutex
	value   T
	holder  *SynchronizedGuard[T]
	changed chan struct{}
	waiters []chan struct{}
}

// SynchronizedGuard is an ordinary aliasable resource. The cell mutex makes
// access versus close atomic, including calls through saved method values.
type SynchronizedGuard[T any] struct {
	cell     *Synchronized[T]
	owner    *Execution
	lifetime *workLifetime
	waiting  bool
	closed   bool
}

// NewSynchronized constructs a Synchronized holding value.
func NewSynchronized[T any](value T) *Synchronized[T] {
	return &Synchronized[T]{value: value, changed: make(chan struct{})}
}

const closedGuardMessage = "Synchronized guard is closed; use the guard only inside its with block, and acquire a new one to access the value again"

// Synchronized_Lock waits cancellably for exclusive admission. If cancellation
// wins before the guard is delivered, nothing is acquired.
func Synchronized_Lock[T any](ctx *Execution, s *Synchronized[T]) *SynchronizedGuard[T] {
	for {
		CheckCancelled(ctx)
		s.mu.Lock()
		if s.holder == nil {
			guard := &SynchronizedGuard[T]{cell: s, owner: ctx, lifetime: ctx.lifetime}
			s.holder = guard
			s.mu.Unlock()
			return guard
		}
		reentrant := s.holder.owner == ctx || ctx.lifetime != nil && s.holder.lifetime == ctx.lifetime
		changed := s.changed
		s.mu.Unlock()
		if reentrant {
			Raise("cannot acquire a Synchronized lock held by this operation")
		}
		select {
		case <-changed:
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		}
	}
}

func (g *SynchronizedGuard[T]) release() {
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

// SynchronizedGuard_Close releases the lock for every alias; repeated close
// does nothing.
func SynchronizedGuard_Close[T any](_ *Execution, g *SynchronizedGuard[T]) Unit {
	g.release()
	return Unit{}
}

// SynchronizedGuard_Value returns the guarded payload without cloning.
func SynchronizedGuard_Value[T any](_ *Execution, g *SynchronizedGuard[T]) T {
	s := g.cell
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.holder != g {
		Raise(closedGuardMessage)
	}
	return s.value
}

// SynchronizedGuard_Set replaces the guarded payload without copying it.
func SynchronizedGuard_Set[T any](_ *Execution, g *SynchronizedGuard[T], value T) Unit {
	s := g.cell
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.holder != g {
		Raise(closedGuardMessage)
	}
	s.value = value
	return Unit{}
}

// requireOwnedHolder faults unless g is the open holder and ctx is the
// operation that acquired it (including shielded views). Another task sharing
// the alias must not release or signal on behalf of the holder. Caller holds s.mu.
func (g *SynchronizedGuard[T]) requireOwnedHolder(ctx *Execution) {
	if g.cell.holder != g {
		Raise(closedGuardMessage)
	}
	if g.owner != ctx && (ctx.lifetime == nil || g.lifetime != ctx.lifetime) {
		Raise("only the operation that acquired a Synchronized guard may wait or notify through it")
	}
}

// SynchronizedGuard_Wait releases the lock, sleeps until notify_all, then
// reacquires the lock for the same guard. Cancellation wakes the waiter
// without reacquiring: the guard stays released, so a parent holding the lock
// while closing its waiters cannot deadlock. The with-scope close is then an
// idempotent no-op.
func SynchronizedGuard_Wait[T any](ctx *Execution, g *SynchronizedGuard[T]) Unit {
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
			Raise(closedGuardMessage)
		}
		if s.holder == nil {
			s.holder = g
			g.waiting = false
			s.mu.Unlock()
			return Unit{}
		}
		changed := s.changed
		s.mu.Unlock()
		select {
		case <-changed:
		case <-ctx.Context.Done():
		}
	}
}

func (g *SynchronizedGuard[T]) finishWait() {
	g.cell.mu.Lock()
	g.waiting = false
	g.cell.mu.Unlock()
}

// abandonWait removes a cancelled waiter. The guard stays released.
func (g *SynchronizedGuard[T]) abandonWait(wake chan struct{}) {
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

// SynchronizedGuard_NotifyAll wakes every task waiting on this Synchronized.
func SynchronizedGuard_NotifyAll[T any](ctx *Execution, g *SynchronizedGuard[T]) Unit {
	s := g.cell
	s.mu.Lock()
	defer s.mu.Unlock()
	g.requireOwnedHolder(ctx)
	for _, waiter := range s.waiters {
		close(waiter)
	}
	s.waiters = nil
	return Unit{}
}
