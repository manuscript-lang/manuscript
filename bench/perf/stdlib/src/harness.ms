from "@std/collections.ms" import range
from "@std/io.ms" import stdout
from "@std/time.ms" import clock

# Shared helpers for the standard-library micro-benchmarks.
export type Point:
    x: Int
    y: Int

export def say(text: String) -> Unit:
    let _ignored = stdout().write(text)

# Runs `body` once and prints `name<TAB>ops<TAB>ns_per_op`; `body` returns a checksum that keeps its work observable.
export def bench(name: String, ops: Int, body: Callable[[], Int]) -> Unit:
    let started = clock().now()
    let checksum = body()
    let elapsed = clock().now().difference(started).to_nanoseconds()
    say(f"{name}\t{ops}\t{elapsed / ops}\n")
    say(f"# checksum {name} {checksum}\n")
    say(f"# elapsed {name} {elapsed}\n")

export def ints(count: Int) -> List[Int]:
    var out: List[Int] = []
    for i in range(0, count):
        out.append((i * 7919) % 10007)
    return out

export def words(count: Int) -> List[String]:
    var out: List[String] = []
    for i in range(0, count):
        out.append(f"word{i % 977}")
    return out
