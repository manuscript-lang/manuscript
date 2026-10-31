# conform: tags=lists,mutation,tier-stdlib
# conform: phase=run
import stdout from "@std/io.ms"

type Counter:
    n: Int

impl Counter:
    var fn next() Int:
        self.n += 1
        return self.n

export fn main() Int:
    var c = Counter(0)
    var xs = ["a", "b", "c", "d", "e", "f", "g"]
    let one = xs[c.next()].clone()
    let two = xs[c.next()].clone()
    let len = xs[c.next()].length()
    xs[c.next()] = "z"
    stdout().write("{one} {two} {len} {xs} {c.n}\n").get()
    return 0
