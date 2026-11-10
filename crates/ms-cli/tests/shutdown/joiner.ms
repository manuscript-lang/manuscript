import stdout from "@std/io/io.ms"
import nanoseconds, sleep from "@std/time.ms"
import promise from "@std/concurrency/promise.ms"

fn long() Int:
    for i in 0..600:
        _ := sleep(nanoseconds(100000000)).wait()
    return 0

fn main() Unit:
    w := promise(fn: ok(long()))
    print("joining")

    _flushed := stdout().flush()
    outcome := w.wait()
    print("joined {outcome.is_ok()}")
