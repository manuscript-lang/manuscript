# expect-debug: allocs=42 alloc_bytes=2604
# expect-release: allocs=22 alloc_bytes=1614
# Reading a field through a function that returns an owned clone; field_via_ref.ms lends it. The floor for elision.
type Box:
    name: String

fn name_of(b: Box) String:
    return b.name.clone()

export fn main() Int:
    var total = 0

    for i in 0..20:
        let b = Box("a name that is long enough to live on the heap {i}")
        total += name_of(b).length()

    return total - total
