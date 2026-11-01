# conform: tags=control-flow,formatter,interpolation,modules,mutation,parser,stdlib-io,stdlib-time,tier-io
# conform: phase=parse
# conform: origin=bench/perf/results/2026-10-18-linux-amd64/dynamic-counter.ms
import Instant, monotonic from "@std/os/time.ms"
import stdout from "@std/io/io.ms"

fn measure(start: Int) Int:
    let t = monotonic()
    var i = start
    var hits = 0

    while i < 10000000:
        hits += i % 3
        i += 1

    let elapsed = monotonic().difference(t).to_nanoseconds()
    let line = "{start} {elapsed} {hits}\n"
    let ignored = stdout().write(line.to_bytes())
    return hits

export fn main() Int:
    measure(-137)
    measure(0)
    measure(5)
    return 0
