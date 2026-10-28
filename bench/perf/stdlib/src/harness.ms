# Shared helpers for the standard-library micro-benchmarks in the `*_bench.ms` files.
export type Point:
    x: Int
    y: Int

export def ints(count: Int) -> List[Int]:
    var out: List[Int] = []
    for i in 0..count:
        out.append((i * 7919) % 10007)
    return out

export def words(count: Int) -> List[String]:
    var out: List[String] = []
    for i in 0..count:
        out.append(f"word{i % 977}")
    return out
