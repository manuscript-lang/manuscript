# conform: tags=closures,formatter,modules,parser,stdlib-queues,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/defaults_test.go:14 TestDefaultExpressionsParticipateInTooling
import Queue from "@std/queue.ms"

fn read(state: Queue[Int]) Int:
    return state.length()

fn named(state: Queue[Int], value: Int = read(state)) Int:
    return value

fn nested(state: Queue[Int]) Unit:
    let callback = fn(value: Int = read(state)) Int:
        return value
