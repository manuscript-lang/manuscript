import Bytes from "@std/bytes.ms"
import panic from "@std/core.ms"
import min from "@std/math/math.ms"
import msstd_utf8_is_valid from "@std/internal/utf8.ms"

/*
Decodes one UTF-8 scalar at a byte position without decoding or copying the entire input.
Walk forward by adding the returned width: `let part = try decode_first(data, position)`.
The scalar decoders examine at most four input bytes; is_valid checks the whole buffer.
No normalization or replacement is applied.
*/

// Tests the entire byte sequence for strict, shortest UTF-8 without allocating decoded text.
// Empty bytes are valid. Surrogates, overlong sequences, out-of-range scalars and incomplete sequences are invalid.
export fn is_valid(data: Bytes) Bool:
    return msstd_utf8_is_valid(data)

// A decoded Unicode scalar and the size of its original shortest UTF-8 encoding.
// Example: `decode_first("é".to_bytes())` returns `Utf8Scalar(scalar: 233, width: 2)`.
export type Utf8Scalar:
    // Unicode scalar value, excluding surrogates, from zero through U+10FFFF.
    scalar: Int
    // Number of consumed bytes, from one through four; not a scalar index or grapheme count.
    width: Int

// Distinguishes text that needs more bytes from text that cannot form a valid scalar.
// Example: `decode_first(Bytes([194]))` returns `Utf8Error.Incomplete`.
export enum Utf8Error:
    // The requested sequence is malformed, overlong, a surrogate or outside Unicode.
    InvalidData
    // No bytes are available, or the selected bytes are a proper prefix of one scalar.
    Incomplete

// Internal result codes: a scalar is nonnegative, so these cannot collide with one.
let INCOMPLETE = -1
let INVALID = -2

// Lowest and highest allowed second byte for a lead byte; the other continuation bytes span 128 through 191.
fn second_low(lead: Int) Int:
    if lead == 224: return 160
    if lead == 240: return 144

    return 128

fn second_high(lead: Int) Int:
    if lead == 237: return 159
    if lead == 244: return 143

    return 191

// Decodes the scalar starting at start using only bytes before stop.
// Returns the scalar, INCOMPLETE when the bytes seen are a proper prefix, or INVALID.
fn decode_at(data: Bytes, start: Int, stop: Int) Int:
    if start >= stop: return INCOMPLETE

    let lead = data.get(start).to_int()
    if lead < 128: return lead
    if lead < 194 or lead > 244: return INVALID

    let size = if lead < 224: 2 else: (if lead < 240: 3 else: 4)
    var value = if size == 2: lead - 192 else: (
        if size == 3: lead - 224 else: lead - 240
    )

    for step in 1..size:
        if start + step >= stop: return INCOMPLETE

        let byte = data.get(start + step).to_int()
        let low = if step == 1: second_low(lead) else: 128
        let high = if step == 1: second_high(lead) else: 191
        if byte < low or byte > high: return INVALID

        value = value * 64 + byte - 128

    return value

fn scalar_width(value: Int) Int:
    if value < 128: return 1
    if value < 2048: return 2
    if value < 65536: return 3

    return 4

// Finds the scalar that ends at stop by trying each possible start, shortest suffix first.
fn decode_ending(data: Bytes, stop: Int) Int:
    var incomplete = stop == 0

    for width in 1..(min(stop, 4) + 1):
        let value = decode_at(data, stop - width, stop)
        if value == INCOMPLETE:
            incomplete = true
        if value >= 0 and scalar_width(value) == width: return value

    return if incomplete: INCOMPLETE else: INVALID

fn decoded(value: Int) Utf8Scalar!Utf8Error:
    if value == INCOMPLETE: return error(Utf8Error.Incomplete)
    if value < 0: return error(Utf8Error.InvalidData)

    return ok(Utf8Scalar(value, scalar_width(value)))

/*
Decodes only the scalar beginning at absolute byte offset at (zero by default).
Later malformed bytes do not invalidate an earlier scalar. End of input returns Incomplete.
Requires 0 <= at <= data.length(); invalid offsets fault, without negative-index wrapping.
*/
export fn decode_first(data: Bytes, at: Int = 0) Utf8Scalar!Utf8Error:
    if at < 0 or at > data.length():
        panic("utf8.decode_first: at must be between zero and the byte length")
    return decoded(decode_at(data, at, data.length()))

/*
Decodes only the scalar ending at exclusive absolute byte offset end, or at the byte length when omitted.
Earlier malformed bytes do not invalidate a valid final scalar. An empty prefix returns Incomplete.
Requires 0 <= end <= data.length(); invalid offsets fault. A trailing proper scalar prefix returns Incomplete.
*/
export fn decode_last(data: Bytes, end: Int?) Utf8Scalar!Utf8Error:
    let stop = end.get(data.length())
    if stop < 0 or stop > data.length():
        panic("utf8.decode_last: end must be between zero and the byte length")
    return decoded(decode_ending(data, stop))
