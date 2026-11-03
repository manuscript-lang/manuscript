import stdin, stdout from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

// Each `stdin()` call continues the one stream: bytes a first handle took are not seen again, and a
// later handle sees the rest, so the two reads together are the whole input in order.
export fn main() Int:
    var first = stdin()
    let chunk = first.read().wait().get(none)
    if chunk.is_none():
        return 1

    let rest = read_all(input: stdin()).get()
    let text = chunk.get().decode_utf8().get("") + rest.decode_utf8().get("")
    stdout().write(text).get()
    return 0
