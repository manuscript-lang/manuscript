# conform: tags=formatter,modules,parser,stdlib-bytes,stdlib-encoding,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/errors/results.md:97
from "@std/bytes.ms" import Bytes
from "@std/encoding.ms" import hex_decode

def decode(text: String) -> Result[Bytes, Error]:
    let bytes = try hex_decode(text)
    return ok(bytes)
