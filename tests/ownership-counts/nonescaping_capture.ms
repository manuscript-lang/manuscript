# expect-debug: allocs=4 alloc_bytes=680
# expect-release: allocs=3 alloc_bytes=648
# A closure that captures a local and is only passed down to a call: Release specializes it away (no environment), Debug keeps one environment allocation. Stack environments must not raise either.
fn apply(xs: List[Int], f: fn(Int) Int) Int:
    var t = 0
    for x in xs:
        t = t + f(x)
    return t

export fn main() Int:
    let xs = [1, 2, 3]
    let k = 5
    let r = apply(xs, fn x: x + k)
    return r - 21
