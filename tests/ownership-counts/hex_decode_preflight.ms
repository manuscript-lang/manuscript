// expect-debug: allocs=3 alloc_bytes=8833
// expect-release: allocs=3 alloc_bytes=8833
// Rejected hexadecimal input must not materialize temporary byte and byte-list copies.
import hex_decode from "@std/data/encoding.ms"

export fn main() Int:
    let text = "00".repeat(4096).get()
    let decoded = hex_decode(text, 0)
    if decoded.is_ok(): return 1
    if decoded.err().kind != "EOVERFLOW": return 2

    return 0
