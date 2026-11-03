import stdout from "@std/io/io.ms"
import nanoseconds, sleep from "@std/os/time.ms"
import promise from "@std/concurrency/promise.ms"

fn long() Int:
    for i in 0..600:
        sleep(nanoseconds(100000000))
    return 0

export fn main() Int:
    let w = promise(fn: ok(long()))
    stdout().write("joining\n").get()
    stdout().flush().get()

    let outcome = w.wait()
    stdout().write("joined {outcome.is_ok()}\n").get()
    return 0
