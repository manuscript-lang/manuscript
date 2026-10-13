package msruntime

import "sync"

// Nodes describe actual lock waits, joins and admitted work, not ancestry.
// Dependencies are protected by workWaits. Component locks may precede it;
// nothing under workWaits acquires a component lock or invokes user code.
// Keep the common single destination inline; distinct destinations spill
// into the counted map. Every admitted edge still exists eagerly.
type workWaitNode struct {
	first        *workWaitNode
	firstCount   int
	dependencies map[*workWaitNode]int
}

var workWaits = struct {
	sync.Mutex
	locks       map[*synchronizedWait]struct{}
	cancellable map[*cancellableWorkWait]struct{}
}{locks: make(map[*synchronizedWait]struct{}), cancellable: make(map[*cancellableWorkWait]struct{})}

// Unlike group joins/close, a cancelled restart caller stops waiting for the
// old job immediately. Its dependency ends at cancellation, not resumption.
type cancellableWorkWait struct {
	from, to  *workWaitNode
	cancelled <-chan struct{}
	active    bool
}

func addCancellableWorkDependency(from, to *workWaitNode, cancelled <-chan struct{}) func() {
	if cancelled == nil {
		return addWorkDependency(from, to).remove
	}
	if from == nil || to == nil {
		return func() {}
	}
	wait := &cancellableWorkWait{from: from, to: to, cancelled: cancelled}
	workWaits.Lock()
	select {
	case <-cancelled:
	default:
		wait.active = true
		workWaits.cancellable[wait] = struct{}{}
		addWorkDependencyLocked(from, to)
		detectAncestorLockCyclesLocked()
	}
	workWaits.Unlock()
	return func() {
		workWaits.Lock()
		removeCancellableWorkDependencyLocked(wait)
		workWaits.Unlock()
	}
}

func removeCancellableWorkDependencyLocked(wait *cancellableWorkWait) {
	if wait.active {
		removeWorkDependencyLocked(wait.from, wait.to)
		delete(workWaits.cancellable, wait)
		wait.active = false
	}
}

func lifetimeWaitNode(lifetime *workLifetime) *workWaitNode {
	if lifetime == nil {
		return nil
	}
	return &lifetime.waits
}

// One owner removes each value token once. Cancellation-aware tokens above
// retain shared active state so pruning and deferred removal stay idempotent.
type workDependency struct {
	from, to *workWaitNode
}

// Both admission edges precede the worker's start. Publish and retire them
// together without changing which work is included in a task/service join.
type workAdmission struct {
	first, second, child *workWaitNode
}

func addWorkAdmission(first, second, child *workWaitNode) workAdmission {
	workWaits.Lock()
	addWorkDependencyLocked(first, child)
	addWorkDependencyLocked(second, child)
	detectAncestorLockCyclesLocked()
	workWaits.Unlock()
	return workAdmission{first: first, second: second, child: child}
}

func (admission workAdmission) remove() {
	workWaits.Lock()
	removeWorkDependencyLocked(admission.first, admission.child)
	removeWorkDependencyLocked(admission.second, admission.child)
	workWaits.Unlock()
}

func addWorkDependency(from, to *workWaitNode) workDependency {
	if from == nil || to == nil {
		return workDependency{}
	}
	workWaits.Lock()
	addWorkDependencyLocked(from, to)
	detectAncestorLockCyclesLocked()
	workWaits.Unlock()
	return workDependency{from: from, to: to}
}

func (dependency workDependency) remove() {
	if dependency.from == nil {
		return
	}
	workWaits.Lock()
	removeWorkDependencyLocked(dependency.from, dependency.to)
	workWaits.Unlock()
}

func addWorkDependencyLocked(from, to *workWaitNode) {
	if from.first == to {
		from.firstCount++
		return
	}
	if from.dependencies[to] != 0 {
		from.dependencies[to]++
		return
	}
	if from.first == nil {
		from.first, from.firstCount = to, 1
		return
	}
	if from.dependencies == nil {
		from.dependencies = make(map[*workWaitNode]int)
	}
	from.dependencies[to]++
}

func removeWorkDependencyLocked(from, to *workWaitNode) {
	if from.first == to {
		from.firstCount--
		if from.firstCount == 0 {
			from.first = nil
		}
		return
	}
	if from.dependencies[to] == 1 {
		delete(from.dependencies, to)
	} else {
		from.dependencies[to]--
	}
	if len(from.dependencies) == 0 {
		from.dependencies = nil
	}
}

func workReachesLocked(from, to *workWaitNode) bool {
	seen := make(map[*workWaitNode]bool)
	pending := []*workWaitNode{from}
	for len(pending) > 0 {
		last := len(pending) - 1
		node := pending[last]
		pending = pending[:last]
		if node == to {
			return true
		}
		if seen[node] {
			continue
		}
		seen[node] = true
		if node.first != nil {
			pending = append(pending, node.first)
		}
		for dependency := range node.dependencies {
			pending = append(pending, dependency)
		}
	}
	return false
}

func strictExecutionAncestor(ancestor, lifetime *workLifetime) bool {
	if ancestor == nil || lifetime == nil {
		return false
	}
	for parent := lifetime.parent; parent != nil; parent = parent.parent {
		if parent == ancestor {
			return true
		}
	}
	return false
}

// Fault only an ancestral lock waiter. Independent lock/service cycles remain
// outside this guarantee. A later join wakes the waiter instead of faulting
// the joining ancestor, preserving the task's Crashed reporting boundary.
func detectAncestorLockCyclesLocked() {
	for wait := range workWaits.cancellable {
		select {
		case <-wait.cancelled:
			removeCancellableWorkDependencyLocked(wait)
		default:
		}
	}
	// Cancellation ends an ordinary lock dependency even if its goroutine has
	// not yet resumed to remove the token. Exclude it from transitive paths too.
	for wait := range workWaits.locks {
		select {
		case <-wait.cancelled:
			removeSynchronizedWaitLocked(wait)
		default:
		}
	}
	for wait := range workWaits.locks {
		if wait.faulted || !strictExecutionAncestor(wait.guard.lifetime, wait.lifetime) {
			continue
		}
		if workReachesLocked(wait.to, wait.from) {
			wait.faulted = true
			close(wait.fault)
		}
	}
}

type synchronizedWait struct {
	guard     *SynchronizedGuard
	lifetime  *workLifetime
	from, to  *workWaitNode
	cancelled <-chan struct{}
	fault     chan struct{}
	active    bool
	faulted   bool
}

// Called with the cell mutex held so observing the current acquisition and
// registering its dependency are atomic with release and reacquisition.
func registerSynchronizedWait(guard *SynchronizedGuard, lifetime *workLifetime, cancelled <-chan struct{}) *synchronizedWait {
	wait := &synchronizedWait{guard: guard, lifetime: lifetime, from: lifetimeWaitNode(lifetime), to: lifetimeWaitNode(guard.lifetime), cancelled: cancelled, fault: make(chan struct{})}
	if guard.waiters == nil {
		guard.waiters = make(map[*synchronizedWait]struct{})
	}
	guard.waiters[wait] = struct{}{}
	if wait.from != nil && wait.to != nil {
		workWaits.Lock()
		wait.active = true
		workWaits.locks[wait] = struct{}{}
		addWorkDependencyLocked(wait.from, wait.to)
		detectAncestorLockCyclesLocked()
		workWaits.Unlock()
	}
	return wait
}

func removeSynchronizedWaitLocked(wait *synchronizedWait) {
	if wait.active {
		removeWorkDependencyLocked(wait.from, wait.to)
		delete(workWaits.locks, wait)
		wait.active = false
	}
}

func (wait *synchronizedWait) remove() {
	wait.guard.cell.mu.Lock()
	defer wait.guard.cell.mu.Unlock()
	workWaits.Lock()
	removeSynchronizedWaitLocked(wait)
	workWaits.Unlock()
	delete(wait.guard.waiters, wait)
}

// Release removes dependencies before waking waiters. A join inserted after
// release cannot mistake an unscheduled waiter for a dependency on this guard.
func releaseSynchronizedWaitsLocked(guard *SynchronizedGuard) {
	if len(guard.waiters) == 0 {
		return
	}
	workWaits.Lock()
	for wait := range guard.waiters {
		removeSynchronizedWaitLocked(wait)
	}
	workWaits.Unlock()
	guard.waiters = nil
}
