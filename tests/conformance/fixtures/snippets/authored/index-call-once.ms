// conform: tags=lists,mutation,tier-stdlib
// conform: phase=run

type Counter:
    n: Int

fn var Counter.next() Int:
    self.n += 1
    return self.n

fn main() Unit:
    var c = Counter(0)
    var xs = ["a", "b", "c", "d", "e", "f", "g"]
    one := xs[c.next()].clone()
    two := xs[c.next()].clone()
    len := xs[c.next()].length()
    xs[c.next()] = "z"
    print("{one} {two} {len} {xs} {c.n}")
