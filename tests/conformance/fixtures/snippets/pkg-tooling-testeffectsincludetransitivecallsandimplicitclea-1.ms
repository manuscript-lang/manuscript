# conform: tags=closures,control-flow,diagnostics,interfaces,modules,records,stdlib-cleanup,stdlib-queues,tier-stdlib,with-cleanup
# conform: phase=check
# conform: origin=pkg/tooling/effects_test.go:13 TestEffectsIncludeTransitiveCallsAndImplicitCleanup
import Closeable from "@std/cleanup.ms"
import Queue from "@std/queues.ms"

type Resource:
    state: Queue[Int]

impl Closeable for Resource:
    fn close() Unit:
        self.state.dequeue()

fn pure() Int:
    return 1

fn direct(resource: Resource) Unit:
    with item = resource:
        return

fn transitive(resource: Resource) Unit:
    direct(resource: resource)

fn nested(resource: Resource) Unit:
    let callback = fn() Unit:
        with item = resource:
            return

fn indirect(callback: fn() Unit) Unit:
    callback()
