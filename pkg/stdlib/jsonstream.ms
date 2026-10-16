# Incremental JSON decoder implemented in Manuscript.
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import {parse, JsonValue, JsonLimits, JsonError} from "@std/json.ms"
import check_cancelled from "@std/tasks.ms"

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
    fn feed(chunk: Bytes) -> Result[List[JsonValue], JsonError]
    # Signals end of input and returns a final unterminated scalar, if any. Input that
    # ends inside a string, array, or object returns `InvalidData`. The decoder rejects
    # later calls with `InvalidInput`.
    fn finish() -> Result[List[JsonValue], JsonError]

# Creates a decoder. `limits` applies to each value separately: `max_bytes` counts the
# value's UTF-8 bytes, `max_depth` its nesting, and `max_values` its parsed values, and
# an exceeded limit returns `LimitExceeded`. Omit limits only for trusted input, because
# an unterminated value is otherwise buffered without bound. Negative limits return
# `InvalidInput`.
export fn decoder(limits: Optional[JsonLimits] = none) -> Result[JsonDecoder, JsonError]:
    let bounds = limits.unwrap_or(JsonLimits())

    if (
        bounds.max_bytes.unwrap_or(0) < 0
        or bounds.max_depth.unwrap_or(0) < 0
        or bounds.max_values.unwrap_or(0) < 0
    ): return error(JsonError.InvalidInput)

    return ok(
        JsonDecoder(
            Decoder(
                limits: bounds,
                pending: BytesBuilder(),
                size: 0,
                depth: 0,
                mode: 0,
                in_string: false,
                escaped: false,
                finished: false,
                failure: none
            )
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
    failure: Optional[JsonError]

fn is_space(byte: Int) -> Bool:
    return (byte == 32 or byte == 9 or byte == 10 or byte == 13)

fn starts_value(byte: Int) -> Bool:
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

fn reset(state: Decoder) -> Unit:
    state.pending = BytesBuilder()
    state.size = 0
    state.depth = 0
    state.mode = 0
    state.in_string = false
    state.escaped = false

fn fail(state: Decoder, cause: JsonError) -> Result[List[JsonValue], JsonError]:
    # Dropping the partial value releases its buffered bytes.
    reset(state)
    state.failure = some(cause)
    return error(cause)

# Parses the buffered value and clears the scanner for the next one.
fn complete(state: Decoder) -> Result[JsonValue, JsonError]:
    let bytes = state.pending.freeze()
    reset(state)

    if let text = bytes.to_text():
        return parse(text, some(state.limits))

    return error(JsonError.InvalidData)

# Consumes one byte and reports whether it finished a value.
fn scan(state: Decoder, byte: Int) -> Result[Bool, JsonError]:
    if state.mode == 0:
        if is_space(byte): return ok(false)
        if not starts_value(byte): return error(JsonError.InvalidData)

        state.mode = 3

        if byte == 123 or byte == 91:
            state.mode = 1
        else if byte == 34:
            state.mode = 2

    let limit = state.limits.max_bytes.unwrap_or(-1)
    if state.mode == 3 and is_space(byte): return ok(true)

    state.size = state.size + 1
    if limit >= 0 and state.size > limit: return error(JsonError.LimitExceeded)

    state.pending.append(byte)

    if state.mode == 3: return ok(false)

    if state.in_string:
        if state.escaped:
            state.escaped = false
        else if byte == 92:
            state.escaped = true
        else if byte == 34:
            state.in_string = false

        return ok(state.mode == 2 and not state.in_string)

    if byte == 34:
        state.in_string = true
        return ok(false)

    if byte == 123 or byte == 91:
        state.depth = state.depth + 1

        if state.depth > state.limits.max_depth.unwrap_or(state.depth): return error(
            JsonError.LimitExceeded
        )

        return ok(false)

    if byte == 125 or byte == 93:
        state.depth = state.depth - 1
        return ok(state.depth == 0)

    return ok(false)

# Consumes one byte and returns the value it completes, if any.
fn step(state: Decoder, byte: Int) -> Result[Optional[JsonValue], JsonError]:
    let done = try scan(state, byte)

    if not done: return ok(none)

    let value = try complete(state)
    return ok(some(value))

impl JsonDecoder for Decoder:
    fn feed(chunk: Bytes) -> Result[List[JsonValue], JsonError]:
        check_cancelled()

        if self.finished: return error(JsonError.InvalidInput)
        if self.failure.is_some(): return error(self.failure.unwrap())

        let values: List[JsonValue] = []

        for byte in chunk.values():
            match step(self, byte):
                error(cause): return fail(self, cause)
                ok(found):
                    if found.is_some(): values.append(found.unwrap())

        return ok(values)

    fn finish() -> Result[List[JsonValue], JsonError]:
        if self.finished: return error(JsonError.InvalidInput)
        if self.failure.is_some(): return error(self.failure.unwrap())

        self.finished = true
        let values: List[JsonValue] = []

        if self.mode == 0: return ok(values)
        if self.mode != 3: return fail(self, JsonError.InvalidData)

        match complete(self):
            error(cause): return fail(self, cause)
            ok(item): values.append(item)

        return ok(values)
