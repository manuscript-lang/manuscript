// conform: tags=closures,control-flow,diagnostics,interfaces,modules,records,stdlib-cleanup,stdlib-queues,tier-stdlib,scope-cleanup
// conform: phase=check
// conform: origin=pkg/tooling/effects_test.go:13 TestEffectsIncludeTransitiveCallsAndImplicitCleanup
import (
	Queue from "@std/collections/queue.ms",
	Closeable from "@std/core.ms",
)

type Resource {
	state Queue[Int]
}

fn move Resource.close() Void! {
	self.state.dequeue()
}

fn pure() Int {
	return 1
}

fn direct(move resource Resource) Void {
	_item := resource
	return
}

fn transitive(move resource Resource) Void {
	direct(resource: resource)
}

fn nested(move resource Resource) Void {
	callback := fn(move item Resource) Void {
		_held := item
		return
	}

	callback(resource)
}

fn indirect(callback fn() Void) Void {
	callback()
}
// expect-exit: 0
