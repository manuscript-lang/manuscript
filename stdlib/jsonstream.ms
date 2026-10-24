# Incremental JSON decoder implemented in Manuscript.
from "@std/bytes.ms" import Bytes, BytesBuilder
from "@std/json.ms" import parse, JsonValue, JsonLimits, JsonError

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
    var def feed(chunk: Bytes) -> Result[List[JsonValue], JsonError]
    # Signals end of input and returns a final unterminated scalar, if any. Input that
    # ends inside a string, array, or object returns `InvalidData`. The decoder rejects
    # later calls with `InvalidInput`.
    var def finish() -> Result[List[JsonValue], JsonError]

# Creates a decoder. `limits` applies to each value separately: `max_bytes` counts the
# value's UTF-8 bytes, `max_depth` its nesting, and `max_values` its parsed values, and
# an exceeded limit returns `LimitExceeded`. Omit limits only for trusted input, because
# an unterminated value is otherwise buffered without bound. Negative limits return
# `InvalidInput`.
export def decoder(
    limits: Optional[JsonLimits] = none
) -> Result[JsonDecoder, JsonError]:
    let bounds = limits.get(JsonLimits())
    if (
        bounds.max_bytes.get(0) < 0
        or bounds.max_depth.get(0) < 0
        or bounds.max_values.get(0) < 0
    ): return error(JsonError.InvalidInput)

    return ok(
        Decoder(
            limits: bounds, pending: BytesBuilder(), size: 0, depth: 0, mode: 0,
            in_string: False, escaped: False, finished: False, failure: none
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

def is_space(byte: Int) -> Bool:
    return (byte == 32 or byte == 9 or byte == 10 or byte == 13)

def starts_value(byte: Int) -> Bool:
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

def reset(var state: Decoder) -> Unit:
    state.pending = BytesBuilder()
    state.size = 0
    state.depth = 0
    state.mode = 0
    state.in_string = False
    state.escaped = False

def fail(var state: Decoder, cause: JsonError) -> Result[List[JsonValue], JsonError]:
    # Dropping the partial value releases its buffered bytes.
    reset(var state)
    state.failure = some(cause)
    return error(cause)

# Parses the buffered value and clears the scanner for the next one.
def complete(var state: Decoder) -> Result[JsonValue, JsonError]:
    let bytes = state.pending.freeze()
    reset(var state)
    if let text = bytes.decode_utf8():
        return parse(text, some(state.limits))

    return error(JsonError.InvalidData)

# Consumes one byte and reports whether it finished a value.
def scan(var state: Decoder, byte: Int) -> Result[Bool, JsonError]:
    if state.mode == 0:
        if is_space(byte): return ok(False)
        if not starts_value(byte): return error(JsonError.InvalidData)

        state.mode = 3

        if byte == 123 or byte == 91:
            state.mode = 1
        elif byte == 34:
            state.mode = 2

    let limit = state.limits.max_bytes.get(-1)
    if state.mode == 3 and is_space(byte): return ok(True)

    state.size += 1
    if limit >= 0 and state.size > limit: return error(JsonError.LimitExceeded)

    state.pending.append(byte)
    if state.mode == 3: return ok(False)

    if state.in_string:
        if state.escaped:
            state.escaped = False
        elif byte == 92:
            state.escaped = True
        elif byte == 34:
            state.in_string = False

        return ok(state.mode == 2 and not state.in_string)

    if byte == 34:
        state.in_string = True
        return ok(False)

    if byte == 123 or byte == 91:
        state.depth += 1
        if state.depth > state.limits.max_depth.get(state.depth): return error(
            JsonError.LimitExceeded
        )

        return ok(False)

    if byte == 125 or byte == 93:
        state.depth -= 1
        return ok(state.depth == 0)

    return ok(False)

# Consumes one byte and returns the value it completes, if any.
def step(var state: Decoder, byte: Int) -> Result[Optional[JsonValue], JsonError]:
    let done = try scan(var state, byte)
    if not done: return ok(none)

    let value = try complete(var state)
    return ok(some(value))

impl JsonDecoder for Decoder:
    var def feed(chunk: Bytes) -> Result[List[JsonValue], JsonError]:
        if self.finished: return error(JsonError.InvalidInput)
        if let failure = self.failure: return error(failure)

        var values: List[JsonValue] = []

        for byte in chunk.values():
            let stepped = step(var self, byte)
            if stepped.is_error(): return fail(var self, stepped.err())

            if let found = stepped.get(): values.append(found.clone())

        return ok(values)

    var def finish() -> Result[List[JsonValue], JsonError]:
        if self.finished: return error(JsonError.InvalidInput)
        if let failure = self.failure: return error(failure)

        self.finished = True

        var values: List[JsonValue] = []
        if self.mode == 0: return ok(values)
        if self.mode != 3: return fail(var self, JsonError.InvalidData)

        let completed = complete(var self)
        if completed.is_error(): return fail(var self, completed.err())

        values.append(completed.get().clone())
        return ok(values)
