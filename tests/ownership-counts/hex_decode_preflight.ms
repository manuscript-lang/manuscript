// expect-debug: allocs=2 alloc_bytes=8281
// expect-release: allocs=2 alloc_bytes=8281
// Rejected hexadecimal input must not materialize temporary byte and byte-list copies. The Error is one 88-byte block (allocs and bytes include it).
import hex_decode from "@std/data/encoding.ms"

export fn main() Int:
	text := "00".repeat(4096).get()
	decoded := hex_decode(text, 0)
	if decoded.is_ok(): return 1
	if decoded.err().kind != "EOVERFLOW": return 2

	return 0
