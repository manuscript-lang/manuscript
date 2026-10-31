# expect-debug: allocs=26 alloc_bytes=2574
# expect-release: allocs=23 alloc_bytes=1934
# Reading list elements through `get` and cloning each; get_via_ref.ms lends them. The floor for elision.
fn total(names: List[String]) Int:
    var n = 0

    for i in 0..names.length():
        let s = names.get(i).clone()
        n += s.length()

    return n

export fn main() Int:
    var names = List[String]()
    for i in 0..20:
        names.append("a name that is long enough to live on the heap {i}")
    return total(names) - total(names)
