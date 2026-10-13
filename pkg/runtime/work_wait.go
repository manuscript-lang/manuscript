package msruntime

import "sync"

// Nodes describe actual lock waits, joins and admitted work, not ancestry.
// Dependencies are protected by workWaits. Component locks may precede it;
// nothing under workWaits acquires a component lock or invokes user code.
type workWaitNode struct {
	dependencies map[*workWaitNode]int
}

var workWaits = struct {
	sync.Mutex
	locks map[*synchronizedWait]struct{}
}{locks: make(map[*synchronizedWait]struct{})}

func lifetimeWaitNode(lifetime *workLifetime) *workWaitNode {
	if lifetime == nil {
		return nil
	}
	return &lifetime.waits
}

func addWorkDependency(from, to *workWaitNode) func() {
	if from == nil || to == nil {
		return func() {}
	}
	workWaits.Lock()
	addWorkDependencyLocked(from, to)
	detectAncestorLockCyclesLocked()
	workWaits.Unlock()
	return func() {
		workWaits.Lock()
		removeWorkDependencyLocked(from, to)
		workWaits.Unlock()
	}
}

func addWorkDependencyLocked(from, to *workWaitNode) {
	if from.dependencies == nil {
		from.dependencies = make(map[*workWaitNode]int)
	}
	from.dependencies[to]++
}

func removeWorkDependencyLocked(from, to *workWaitNode) {
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
	for wait := range workWaits.locks {
		if wait.faulted || !strictExecutionAncestor(wait.guard.lifetime, wait.lifetime) {
			continue
		}
		select {
		case <-wait.cancelled:
			continue
		default:
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
