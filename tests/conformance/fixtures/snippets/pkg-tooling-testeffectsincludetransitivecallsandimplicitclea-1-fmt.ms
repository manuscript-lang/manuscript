# conform: tags=closures,control-flow,formatter,interfaces,modules,parser,records,stdlib-cleanup,stdlib-queues,tier-stdlib,with-cleanup
# conform: phase=parse
# conform: origin=pkg/tooling/effects_test.go:13 TestEffectsIncludeTransitiveCallsAndImplicitCleanup
import Closeable from "@std/core.ms"
import Queue from "@std/collections.ms"

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
    let callback = fn(item: Resource) Unit:
        with held = item:
            return
    callback(resource)

fn indirect(callback: fn() Unit) Unit:
    callback()
