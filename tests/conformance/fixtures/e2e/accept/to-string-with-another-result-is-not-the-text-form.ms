// conform: tags=strings,interpolation,records,tier-core
// conform: phase=run
type P:
    n: Int

fn P.to_string() Int:
    return self.n

fn main() Unit:
    p := P(n: 7)
    print(p.to_string())
    print("{p}")
    print(p)
    print([p.clone()])
