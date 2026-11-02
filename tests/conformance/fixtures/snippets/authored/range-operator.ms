# conform: tags=control-flow,lists,tier-core
# conform: phase=run
# conform: origin=range operator a..b
import stdout from "@std/io/io.ms"

fn total(n: Int) Int:
    var sum = 0
    for i in 0..n + 1:
        sum += i
    return sum

export fn main() Int:
    let xs = 1..4
    var empty = 0
    for i in 5..2:
        empty += 1

    let _ = stdout().write(
        "{total(4)} {xs.length()} {xs[0]} {empty} {(2..2).length()}\n"
    )
    return 0
