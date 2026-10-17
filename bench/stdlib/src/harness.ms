import {stdout} from "@std/io.ms"
import {clock} from "@std/time.ms"

# Shared helpers for the standard-library micro-benchmarks.
export type Point:
    x: Int
    y: Int

export fn say(text: String) -> Unit:
    stdout().write(data: text.to_bytes())

# Runs `body` once and prints `name<TAB>ops<TAB>ns_per_op`; `body` returns a checksum that keeps its work observable.
export fn bench(name: String, ops: Int, body: fn() -> Int) -> Unit:
    let started = clock().now()
    body()
    let elapsed = clock().now().difference(other: started).to_nanoseconds()
    say("{name}\t{ops}\t{elapsed / ops}\n")

export fn ints(count: Int) -> List[Int]:
    let out: List[Int] = []
    var i = 0

    while i < count:
        out.append((i * 7919) % 10007)
        i = i + 1

    return out

export fn words(count: Int) -> List[String]:
    let out: List[String] = []
    var i = 0

    while i < count:
        out.append("word{i % 977}")
        i = i + 1

    return out
