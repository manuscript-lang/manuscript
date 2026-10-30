# expect-debug: allocs=22 alloc_bytes=1614
# expect-release: allocs=22 alloc_bytes=1614
# Reading a field through a `ref` result: no copy. The floor for field_via_clone.ms.
type Box:
    name: String

fn name_of(b: Box) ref String:
    return b.name

export fn main() Int:
    var total = 0

    for i in 0..20:
        let b = Box("a name that is long enough to live on the heap {i}")
        total += name_of(b).length()

    return total - total
