# Incremental JSON decoder implemented in Manuscript.
import Bytes, BytesBuilder from "@std/bytes.ms"
import parse, JsonValue, JsonLimits, JsonError from "@std/json.ms"

# Decodes a sequence of JSON values from byte chunks of any size.
#
# The decoder buffers only the value being read, so tokens, escapes, and UTF-8 scalars
# may be split across chunks. Values may be separated by JSON whitespace or directly
# adjacent when they are strings, arrays, or objects, which covers JSON Lines and
# concatenated JSON. Top-level numbers, `true`, `false`, and `null` end at whitespace
# or at `finish()`. The decoder never reads, closes, or owns a stream.
export interface JsonDecoder:
    # Adds a chunk and returns every value it completes, in order; the list is empty when
    # the chunk ends inside a value. An error discards values completed earlier in the same
    # chunk, and the decoder stays failed and returns that error again. Returns `InvalidInput` after `finish()`.
    var fn feed(chunk: Bytes) List[JsonValue]!JsonError
    # Signals end of input and returns a final unterminated scalar, if any. Input that
    # ends inside a string, array, or object returns `InvalidData`. The decoder rejects
    # later calls with `InvalidInput`.
    var fn finish() List[JsonValue]!JsonError

# Creates a decoder. `limits` applies to each value separately: `max_bytes` counts the
# value's UTF-8 bytes, `max_depth` its nesting, and `max_values` its parsed values, and
# an exceeded limit returns `LimitExceeded`. Omit limits only for trusted input, because
# an unterminated value is otherwise buffered without bound. Negative limits return
# `InvalidInput`.
export fn decoder(limits: JsonLimits?) JsonDecoder!JsonError:
    let bounds = limits.get(JsonLimits())
    if (
        bounds.max_bytes.get(0) < 0
        or bounds.max_depth.get(0) < 0
        or bounds.max_values.get(0) < 0
    ): return error(JsonError.InvalidInput)

    return ok(
        Decoder(
            limits: bounds, pending: BytesBuilder(), size: 0, depth: 0, mode: 0,
            in_string: false, escaped: false, finished: false, failure: none
        )
    )

# Scanner modes: between values, inside a container, inside a top-level string, and
# inside a top-level scalar token.
type Decoder:
    limits: JsonLimits
    pending: BytesBuilder
    size: Int
    depth: Int
    mode: Int
    in_string: Bool
    escaped: Bool
    finished: Bool
    failure: JsonError?

fn is_space(byte: UInt8) Bool:
    return (byte == 32 or byte == 9 or byte == 10 or byte == 13)

fn starts_value(byte: UInt8) Bool:
    # Object, array, string, minus sign, digits, and the first letters of the literals.
    return (
        byte == 123
        or byte == 91
        or byte == 34
        or byte == 45
        or byte >= 48 and byte <= 57
        or byte == 116
        or byte == 102
        or byte == 110
    )

impl Decoder:
    var fn reset() Unit:
        self.pending = BytesBuilder()
        self.size = 0
        self.depth = 0
        self.mode = 0
        self.in_string = false
        self.escaped = false

    var fn fail(cause: JsonError) List[JsonValue]!JsonError:
        # Dropping the partial value releases its buffered bytes.
        self.reset()
        self.failure = cause
        return error(cause)

    # Parses the buffered value and clears the scanner for the next one.
    var fn complete() JsonValue!JsonError:
        let bytes = self.pending.drain()
        self.reset()
        if let text = bytes.decode_utf8():
            return parse(text, self.limits)

        return error(JsonError.InvalidData)

    # Consumes one byte and reports whether it finished a value.
    var fn scan(byte: UInt8) Bool!JsonError:
        if self.mode == 0:
            if is_space(byte): return ok(false)
            if not starts_value(byte): return error(JsonError.InvalidData)

            self.mode = 3

            if byte == 123 or byte == 91:
                self.mode = 1
            else if byte == 34:
                self.mode = 2

        let limit = self.limits.max_bytes.get(-1)
        if self.mode == 3 and is_space(byte): return ok(true)

        self.size += 1
        if limit >= 0 and self.size > limit: return error(JsonError.LimitExceeded)

        self.pending.append(byte)
        if self.mode == 3: return ok(false)

        if self.in_string:
            if self.escaped:
                self.escaped = false
            else if byte == 92:
                self.escaped = true
            else if byte == 34:
                self.in_string = false

            return ok(self.mode == 2 and not self.in_string)

        if byte == 34:
            self.in_string = true
            return ok(false)

        if byte == 123 or byte == 91:
            self.depth += 1
            if self.depth > self.limits.max_depth.get(self.depth): return error(
                JsonError.LimitExceeded
            )

            return ok(false)

        if byte == 125 or byte == 93:
            self.depth -= 1
            return ok(self.depth == 0)

        return ok(false)

    # Consumes one byte and returns the value it completes, if any.
    var fn step(byte: UInt8) JsonValue?!JsonError:
        let done = try self.scan(byte)
        if not done: return ok(none)

        let value = try self.complete()
        return ok(value)

impl JsonDecoder for Decoder:
    var fn feed(chunk: Bytes) List[JsonValue]!JsonError:
        if self.finished: return error(JsonError.InvalidInput)
        if let failure = self.failure: return error(failure)

        var values: List[JsonValue] = []

        for byte in chunk.values():
            let stepped = self.step(byte)
            if stepped.is_error(): return self.fail(stepped.err())

            if let found = stepped.get(): values.append(found.clone())

        return ok(values)

    var fn finish() List[JsonValue]!JsonError:
        if self.finished: return error(JsonError.InvalidInput)
        if let failure = self.failure: return error(failure)

        self.finished = true

        var values: List[JsonValue] = []
        if self.mode == 0: return ok(values)
        if self.mode != 3: return self.fail(JsonError.InvalidData)

        let completed = self.complete()
        if completed.is_error(): return self.fail(completed.err())

        values.append(completed.get().clone())
        return ok(values)
