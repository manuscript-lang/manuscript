# conform: tags=numbers,types,tier-core
# conform: phase=run
# conform: origin=unsigned integer types UInt64 range analysis
import stdout from "@std/io.ms"

fn count(start: UInt64, stop: UInt64) UInt64:
    var i = start
    var steps: UInt64 = 0

    while i < stop:
        i = i + 1
        steps = steps + 1

    return steps

fn countdown(from: UInt64) UInt64:
    var i = from
    var steps: UInt64 = 0

    while i > 0:
        i = i - 1
        steps = steps + 1

    return steps

fn clamp_sub(a: UInt64, b: UInt64) UInt64:
    if a >= b:
        return a - b

    return 0

fn mix(seed: UInt64) UInt64:
    var h = seed
    var i = 0

    while i < 5:
        h = h * 3 + 1
        i += 1

    return h

export fn main() Int:
    let top: UInt64 = 18446744073709551615
    let near: UInt64 = 9223372036854775806
    let _ = stdout().write(
        "{count(near, near + 4)} {count(top - 3, top)} {countdown(5)}\n"
    )
    let _ = stdout().write(
        "{clamp_sub(3, 5)} {clamp_sub(top, 1)} {clamp_sub(top, top)}\n"
    )
    let _ = stdout().write("{mix(1)} {mix(0)}\n")
    let _ = stdout().write("{near + near} {near * 2 + 1} {top / 3 * 3}\n")
    let _ = stdout().write("{mix(top / 1000)}\n")
    return 0
