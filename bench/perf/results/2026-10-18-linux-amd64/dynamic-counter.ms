from "@std/time.ms" import clock, Instant
from "@std/io.ms" import stdout

def measure(start: Int) -> Int:
    let t = clock().now()
    var i = start
    var hits = 0

    while i < 10000000:
        hits += i % 3
        i += 1

    let elapsed = clock().now().difference(t).to_nanoseconds()
    let line = f"{start} {elapsed} {hits}\n"
    let ignored = stdout().write(line.to_bytes())
    return hits

export def main() -> Int:
    measure(-137)
    measure(0)
    measure(5)
    return 0
