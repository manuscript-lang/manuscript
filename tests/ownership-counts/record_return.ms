# expect-debug: allocs=14 alloc_bytes=4656
# expect-release: allocs=4 alloc_bytes=2224
# Records built and returned through wrappers: Release already constructs them directly in the caller (the floor is the name and list per record), so return-slot construction has no measured gain. Debug pays list growth the reserve pass removes.
type Big:
    name: String
    items: List[Int]

fn mk(n: Int) Big:
    var xs = List[Int]()
    for i in 0..n:
        xs.append(i)

    let b = Big(name: "a name that is long enough to live on the heap", items: xs)
    return b

fn wrap(n: Int) Big:
    let b = mk(n)
    return b

fn pick(n: Int, c: Bool) Big:
    if c:
        return mk(n)

    return wrap(n)

export fn main() Int:
    let b = pick(100, true)
    let d = pick(100, false)
    return b.items.length() - d.items.length()
