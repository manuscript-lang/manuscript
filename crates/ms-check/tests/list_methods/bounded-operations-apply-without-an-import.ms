type Plain:
    n: Int

export fn main() Int:
    let a = [3, 1].sum() + [3, 1].min().get() + [3, 1].max().get() + [3, 1].sorted() [0]
    let b = [Plain(2)].sorted(fn x, y: x.n - y.n)
    return a + b.length()
