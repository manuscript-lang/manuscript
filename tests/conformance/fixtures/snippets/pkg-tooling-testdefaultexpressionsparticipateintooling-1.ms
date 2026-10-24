# conform: tags=closures,diagnostics,modules,stdlib-queues,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/defaults_test.go:14 TestDefaultExpressionsParticipateInTooling
from "@std/queue.ms" import Queue

def read(state: Queue[Int]) -> Int:
    return state.length()

def named(state: Queue[Int], value: Int = read(state)) -> Int:
    return value

def nested(state: Queue[Int]) -> Unit:
    let callback = lambda (value: Int = read(state)) -> Int:
        return value
