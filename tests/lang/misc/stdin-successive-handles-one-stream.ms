// conform: tags=testing,tier-stdlib
// conform: phase=run
import (
	stdin, stdout from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

// Each `stdin()` call continues the one stream: bytes a first handle took are not seen
// again, and a later handle sees the rest, so the two reads together are the whole
// input in order.
export fn main() Int {
	var first = stdin()
	chunk := first.next().get_or(null)
	if chunk == null { return 1 }

	rest := read_all(input: stdin()).get()
	text := (chunk.decode_utf8() or "") + (rest.decode_utf8() or "")
	stdout().write(text).get()
	return 0
}
