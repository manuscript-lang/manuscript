# expect-debug: allocs=42 alloc_bytes=2964
# expect-release: allocs=42 alloc_bytes=3004
# Trimming through a function whose owned result is a trim of its parameter.
type Line:
    text: String

fn body(l: Line) String:
    return l.text.trim()

fn size(l: Line) Int:
    return body(l).length()

export fn main() Int:
    var total = 0

    for i in 0..20:
        let l = Line("  a line of text that is long enough to live on the heap {i}  ")
        total += size(l)

    return total - total
