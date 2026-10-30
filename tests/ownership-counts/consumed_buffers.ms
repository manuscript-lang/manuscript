# expect-debug: allocs=19 alloc_bytes=73032 list_copies=1 list_copy_bytes=8000
# expect-release: allocs=5 alloc_bytes=32624 list_copies=0 list_copy_bytes=0
# Clones of dead lists and a map over a dead list: Release already moves them, Debug keeps one list copy. Reuse of consumed buffers must not raise either.
fn fill(n: Int) List[Int]:
    var xs = List[Int]()
    for i in 0..n:
        xs.append(i)
    return xs

fn doubled(xs: List[Int]) List[Int]:
    return xs.map(fn x: x * 2)

fn sorted_copy(xs: List[Int]) List[Int]:
    var out = xs.clone()
    out.sort()
    return out

fn rebuild(var xs: List[Int]) List[Int]:
    xs.append(1)
    return xs.clone()

export fn main() Int:
    let a = fill(1000)
    let b = doubled(a)
    let c = sorted_copy(b)
    var d = c.clone()
    let e = rebuild(var d)
    return e.length() - 1001
