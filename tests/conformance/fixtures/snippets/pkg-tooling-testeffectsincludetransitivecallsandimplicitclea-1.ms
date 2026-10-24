# conform: tags=closures,control-flow,diagnostics,interfaces,modules,records,stdlib-cleanup,stdlib-queues,tier-stdlib,with-cleanup
# conform: phase=check
# conform: origin=pkg/tooling/effects_test.go:13 TestEffectsIncludeTransitiveCallsAndImplicitCleanup
from "@std/core.ms" import Closeable
from "@std/queue.ms" import Queue

type Resource:
    state: Queue[Int]

impl Closeable for Resource:
    def close() -> Unit:
        self.state.dequeue()

def pure() -> Int:
    return 1

def direct(resource: Resource) -> Unit:
    with resource as item:
        return

def transitive(resource: Resource) -> Unit:
    direct(resource: resource)

def nested(resource: Resource) -> Unit:
    let callback = lambda (item: Resource) -> Unit:
        with item as held:
            return
    callback(resource)

def indirect(callback: Callable[[], Unit]) -> Unit:
    callback()
