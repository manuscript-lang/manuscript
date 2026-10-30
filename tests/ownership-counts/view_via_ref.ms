# expect-debug: allocs=22 alloc_bytes=1814
# expect-release: allocs=22 alloc_bytes=1854
# Trimming through a `ref` result: no copy. The floor for view_via_clone.ms.
type Line:
    text: String

fn body(l: Line) ref String:
    return l.text.trim()

fn size(l: Line) Int:
    return body(l).length()

export fn main() Int:
    var total = 0

    for i in 0..20:
        let l = Line("  a line of text that is long enough to live on the heap {i}  ")
        total += size(l)

    return total - total
