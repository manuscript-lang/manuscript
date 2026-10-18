import range from "@std/collections.ms"
import {stdout} from "@std/io.ms"
import {clock} from "@std/time.ms"

# Shared helpers for the standard-library micro-benchmarks.
export type Point:
    x: Int
    y: Int

export fn say(text: String) Unit:
    match stdout().write(data: text.to_bytes()):
        ok(_): unit
        error(_): unit

# Runs `body` once and prints `name<TAB>ops<TAB>ns_per_op`; `body` returns a checksum that keeps its work observable.
export fn bench(name: String, ops: Int, body: fn() Int) Unit:
    let started = clock().now()
    body()
    let elapsed = clock().now().difference(other: started).to_nanoseconds()
    say("{name}\t{ops}\t{elapsed / ops}\n")

export fn ints(count: Int) List[Int]:
    let out: List[Int] = []
    for i in range(0, count):
        out.append((i * 7919) % 10007)
    return out

export fn words(count: Int) List[String]:
    let out: List[String] = []
    for i in range(0, count):
        out.append("word{i % 977}")
    return out
