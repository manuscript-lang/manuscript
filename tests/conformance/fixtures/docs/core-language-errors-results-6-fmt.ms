# conform: tags=formatter,modules,parser,stdlib-bytes,stdlib-encoding,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/errors/results.md:97
import Bytes from "@std/bytes.ms"
import hex_decode from "@std/data/encoding.ms"

fn decode(text: String) Result[Bytes, Error]:
    let bytes = try hex_decode(text)
    return ok(bytes)
