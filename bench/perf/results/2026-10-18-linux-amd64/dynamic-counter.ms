import (
    Instant, monotonic from "@std/time.ms",
    stdout from "@std/io/io.ms",
)

fn measure(start: Int) Int:
    t := monotonic()
    var i = start
    var hits = 0

    while i < 10000000:
        hits += i % 3
        i += 1

    elapsed := monotonic().difference(t).to_nanoseconds()
    line := "{start} {elapsed} {hits}\n"
    ignored := stdout().write(line.to_bytes())
    return hits

fn main() Unit:
    measure(-137)
    measure(0)
    measure(5)
