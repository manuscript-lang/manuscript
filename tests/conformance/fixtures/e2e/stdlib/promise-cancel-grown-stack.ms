// conform: tags=scope-cleanup,stdlib-promise,tier-io
// conform: phase=run
import stdout from "@std/io/io.ms"
import promise from "@std/concurrency/promise.ms"
import milliseconds, seconds, sleep from "@std/os/time.ms"

// Parks at the bottom of a recursion deep enough to leave the task's first stack slot, with a
// heap value in every frame, so cancelling it unwinds across grown segments (`make leak-check`
// reports any block the unwind leaves behind).
fn descend(n: Int) Int!:
    let label = "frame {n}"
    let parts = [label.clone(), "x"]

    if n == 0:
        try sleep(seconds(600)).wait()

    let below = try descend(n - 1)
    return ok(below + parts.length())

export fn main() Int:
    let deep = promise(fn: descend(20000))
    let _ = sleep(milliseconds(200)).wait()
    deep.cancel()
    stdout().write("{deep.wait().is_error()}\n").get()
    return 0
