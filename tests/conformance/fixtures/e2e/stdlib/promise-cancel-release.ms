// conform: tags=scope-cleanup,stdlib-promise,tier-io
// conform: phase=run
import promise, wait_first, PromiseOptions from "@std/concurrency/promise.ms"
import milliseconds, sleep from "@std/time.ms"

// Holds heap values across waits so a cancelled promise has something to release.
fn hold(label: String) Int:
    var parts: List[String] = []

    for i in 0..600:
        parts.append("{label} {i}")

        let _ = sleep(milliseconds(100)).wait()

    return parts.length()

fn main() Unit:
    let slow = promise(fn: ok(hold("timed out")))
    let timed_out = slow.with(options: PromiseOptions(timeout: milliseconds(20))).wait()
    let first = wait_first([promise(fn: ok(hold("loser"))), promise(fn: ok(4))])
    let pending = promise(fn: ok(hold("dropped")))
    let _ = pending
    print("{timed_out.is_error()} {first.get(0)}")
