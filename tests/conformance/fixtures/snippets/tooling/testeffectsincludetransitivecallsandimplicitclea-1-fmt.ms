// conform: tags=closures,control-flow,formatter,interfaces,modules,parser,records,stdlib-cleanup,stdlib-queues,tier-stdlib,scope-cleanup
// conform: phase=parse
// conform: origin=pkg/tooling/effects_test.go:13 TestEffectsIncludeTransitiveCallsAndImplicitCleanup
import Closeable from "@std/core.ms"
import Queue from "@std/collections/queue.ms"

type Resource:
    state Queue[Int]

fn move Resource.close() Void!:
    self.state.dequeue()

fn pure() Int:
    return 1

fn direct(resource Resource) Void:
    _item := resource
    return

fn transitive(resource Resource) Void:
    direct(resource: resource)

fn nested(resource Resource) Void:
    callback := fn(item Resource) Void:
        _held := item
        return

    callback(resource)

fn indirect(callback fn() Void) Void:
    callback()
