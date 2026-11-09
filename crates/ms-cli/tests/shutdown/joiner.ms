import stdout from "@std/io/io.ms"
import nanoseconds, sleep from "@std/time.ms"
import promise from "@std/concurrency/promise.ms"

fn long() Int:
    for i in 0..600:
        let _ = sleep(nanoseconds(100000000)).wait()
    return 0

export fn main() Int:
    let w = promise(fn: ok(long()))
    print("joining")

    let _flushed = stdout().flush()
    let outcome = w.wait()
    print("joined {outcome.is_ok()}")
    return 0
