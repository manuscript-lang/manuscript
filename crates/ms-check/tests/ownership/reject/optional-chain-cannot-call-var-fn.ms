type Counter:
    n: Int

impl Counter:
    var fn bump() Int:
        self.n += 1
        return self.n

fn bump_if_present(c: Counter?) Int?:
    return c?.bump() # error: cannot change through `?.`: it only reads its receiver; unwrap with `if let v = ...:` and change a copy, `var w = v.clone()`
