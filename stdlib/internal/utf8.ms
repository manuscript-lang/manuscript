import Bytes from "@std/bytes.ms"

export extern fn msstd_utf8_is_valid(data: Bytes) Bool

# A decoded scalar, -1 for an incomplete sequence, or -2 for malformed UTF-8.
# Offsets are checked by the public source wrappers. The natives inspect at most four bytes.
export extern fn msstd_utf8_decode_first(data: Bytes, at: Int) Int

# Same result codes as decode_first, selecting a suffix ending at exclusive byte offset end.
export extern fn msstd_utf8_decode_last(data: Bytes, end: Int) Int
