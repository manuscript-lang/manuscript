// conform: tags=diagnostics
// conform: phase=check
import Queue from "@std/queues.ms"
fn read(state: Queue[Int]) Int:
    return state.length()
fn named(state: Queue[Int], value: Int = read(state)) Int:
    return value
fn nested(state: Queue[Int]) Unit:
    callback := fn(value: Int = read(state)) Int:
        return value
