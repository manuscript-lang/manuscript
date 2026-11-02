import Bytes from "@std/bytes.ms"
import panic from "@std/core.ms"
import (
    msstd_utf8_decode_first,
    msstd_utf8_decode_last,
    msstd_utf8_is_valid
) from "@std/internal/utf8.ms"

# Decodes one UTF-8 scalar at a byte position without decoding or copying the entire input.
# Walk forward by adding the returned width: `let part = try decode_first(data, position)`.
# The scalar decoders examine at most four input bytes; is_valid checks the whole buffer.
# No normalization or replacement is applied.

# Tests the entire byte sequence for strict, shortest UTF-8 without allocating decoded text.
# Empty bytes are valid. Surrogates, overlong sequences, out-of-range scalars and incomplete sequences are invalid.
export fn is_valid(data: Bytes) Bool:
    return msstd_utf8_is_valid(data)

# A decoded Unicode scalar and the size of its original shortest UTF-8 encoding.
# Example: `decode_first("é".to_bytes())` returns `Utf8Scalar(scalar: 233, width: 2)`.
export type Utf8Scalar:
    # Unicode scalar value, excluding surrogates, from zero through U+10FFFF.
    scalar: Int
    # Number of consumed bytes, from one through four; not a scalar index or grapheme count.
    width: Int

# Distinguishes text that needs more bytes from text that cannot form a valid scalar.
# Example: `decode_first(Bytes([194]))` returns `Utf8Error.Incomplete`.
export type Utf8Error:
    # The requested sequence is malformed, overlong, a surrogate or outside Unicode.
    case InvalidData
    # No bytes are available, or the selected bytes are a proper prefix of one scalar.
    case Incomplete

fn decoded(value: Int) Utf8Scalar!Utf8Error:
    if value == -1: return error(Utf8Error.Incomplete)
    if value < 0: return error(Utf8Error.InvalidData)

    let width = if value < 128: 1 else: (
        if value < 2048: 2 else: (if value < 65536: 3 else: 4)
    )
    return ok(Utf8Scalar(value, width))

# Decodes only the scalar beginning at absolute byte offset at (zero by default).
# Later malformed bytes do not invalidate an earlier scalar. End of input returns Incomplete.
# Requires 0 <= at <= data.length(); invalid offsets fault, without negative-index wrapping.
export fn decode_first(data: Bytes, at: Int = 0) Utf8Scalar!Utf8Error:
    if at < 0 or at > data.length():
        panic("utf8.decode_first: at must be between zero and the byte length")
    return decoded(msstd_utf8_decode_first(data, at))

# Decodes only the scalar ending at exclusive absolute byte offset end, or at the byte length when omitted.
# Earlier malformed bytes do not invalidate a valid final scalar. An empty prefix returns Incomplete.
# Requires 0 <= end <= data.length(); invalid offsets fault. A trailing proper scalar prefix returns Incomplete.
export fn decode_last(data: Bytes, end: Int?) Utf8Scalar!Utf8Error:
    let stop = end.get(data.length())
    if stop < 0 or stop > data.length():
        panic("utf8.decode_last: end must be between zero and the byte length")
    return decoded(msstd_utf8_decode_last(data, stop))
