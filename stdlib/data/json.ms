import Data from "@std/core.ms"
import parse_float from "@std/math/math.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import ReadStream, WriteStream, Sink, Transform, through, writer from "@std/io/io.ms"
import Promise from "@std/concurrency/promise.ms"
import msstd_json_parse, msstd_json_stringify from "@std/internal/json.ms"

// Optional bounds for JSON input bytes, nesting depth, and parsed values.
export type JsonLimits:
    // Maximum UTF-8 input bytes before parsing; none adds no input-size budget.
    max_bytes: Int?
    // Maximum container nesting; a root scalar has depth zero, and a root container depth one.
    max_depth: Int?
    // Maximum parsed containers and scalar values, excluding object keys; none adds no count budget.
    max_values: Int?

/*
Read unstructured JSON through checked optional member lookups.

<!-- manuscript-example: {"mode":"test","filename":"json-members.ms","stdout":"RUN json-members.ms::json-members\nPASS json-members.ms::json-members\n1 tests, 0 failed\n"} -->
```manuscript {filename="json-members.ms"}
import JsonValue, parse from "@std/data/json.ms"
import expect_equal from "@std/test/test.ms"

test "json-members":
    let doc = try parse[JsonValue]("\{\"user\":\{\"name\":\"Ada\"\}\}")
    let name = try doc.get_in(["user", "name"]).ok_or(Error("missing name"))
    try expect_equal(name.as_string(), "Ada")
```

```sh
ms test json-members.ms
```

```text
RUN json-members.ms::json-members
PASS json-members.ms::json-members
1 tests, 0 failed
```

- `get`, `at` and `get_in` borrow; keep the document unchanged while using their results.
- Number text preserves precision; `as_string`, `as_list` and `as_map` explicitly clone their payloads.
*/
export enum JsonValue:
    // JSON null, represented without a payload value.
    Null
    // A JSON true or false value.
    BoolValue(
        // The decoded boolean, without a textual representation requirement.
        value: Bool
    )
    // An exact JSON number token; parsing does not coerce it into Float.
    NumberValue(
        // Original numeric token text; stringify validates its JSON number syntax.
        text: String
    )
    // A decoded JSON string, with escapes resolved into Unicode text.
    StringValue(
        // Decoded UTF-8 text, preserving scalar contents without normalization.
        value: String
    )
    // An ordered JSON array whose mutable list can be updated before serialization.
    ArrayValue(
        // Element values in source order; the array owns its elements.
        values: List[JsonValue]
    )
    // A JSON object retaining insertion order and rejecting duplicate keys during parsing.
    ObjectValue(
        // String-keyed members in insertion order; stringify reads their current values.
        values: Map[String, JsonValue]
    )

// A JSON document is Data, including its string-keyed object members.
impl Data for JsonValue:

impl JsonValue:
    // Returns the object member for `key`, or `none` for an absent key or a value that is not an object. The result borrows from the receiver.
    fn get(key: String) JsonValue?:
        match self:
            ObjectValue(values): return values.get(key)
            _: return none

    /*
    Returns the value reached by reading each object member of `keys` in turn, or `none` when a
    member is absent, a value on the way is not an object, or `keys` is empty. The result borrows
    from the receiver.
    */
    fn get_in(keys: List[String]) JsonValue?:
        return member_path(self, keys, 0)

    // Returns the array element at `index`, counting a negative index from the end. An index out of
    // range, or a value that is not an array, returns `none`. The result borrows from the receiver.
    fn at(index: Int) JsonValue?:
        match self:
            ArrayValue(values):
                if index >= values.length() or index < 0 - values.length(): return none

                return values.get(index)
            _: return none

    // Returns the text of a string value, or `none` for any other value. The result is an owned copy.
    fn as_string() String?:
        match self:
            StringValue(value): return value.clone()
            _: return none

    // Returns a number value as an Int, or `none` when the value is not a number or its text has a
    // fraction, an exponent, or digits that do not fit in Int.
    fn as_int() Int?:
        match self:
            NumberValue(text): return text.parse_int()
            _: return none

    // Returns a number value as a Float, or `none` when the value is not a number or its text is not finite.
    fn as_float() Float?:
        match self:
            NumberValue(text): return parse_float(text).to_optional()
            _: return none

    // Returns a boolean value, or `none` for any other value.
    fn as_bool() Bool?:
        match self:
            BoolValue(value): return value
            _: return none

    // Returns the elements of an array value, or `none` for any other value. The result is an owned copy.
    fn as_list() List[JsonValue]?:
        match self:
            ArrayValue(values): return values.clone()
            _: return none

    // Returns the members of an object value, or `none` for any other value. The result is an owned copy.
    fn as_map() Map[String, JsonValue]?:
        match self:
            ObjectValue(values): return values.clone()
            _: return none

    // Returns true only for the Null case; any other value returns false.
    fn is_null() Bool:
        match self:
            Null: return true
            _: return false

/*
Decode JSON into a known record or keep a `JsonValue` tree for explicit inspection.

- Shape mismatches and missing required fields return `EBADMSG`; optional fields use `none`, declared defaults apply, and unknown fields follow `ignore_unknown_fields`.
- `T` must satisfy `Data`; input limits apply before decoding. See [typed JSON](../../../learn/common-tasks.md#read-and-write-typed-json) and [encoding](#stringify).

*/
export fn parse[T: Data = JsonValue](
    text: String,
    limits: JsonLimits?,
    ignore_unknown_fields: Bool = true
) T!:
    return msstd_json_parse[T](text, limits, ignore_unknown_fields)

/*
Choose a JSON representation by implementing `JsonEncode` in the type's defining module.

<!-- manuscript-example: {"mode":"test","filename":"custom-json.ms","stdout":"RUN custom-json.ms::custom-json\nPASS custom-json.ms::custom-json\n1 tests, 0 failed\n"} -->
```manuscript {filename="custom-json.ms"}
import JsonEncode, JsonValue, stringify from "@std/data/json.ms"

type Status:
    ready: Bool

impl JsonEncode for Status:
    fn to_json() JsonValue:
        return JsonValue.StringValue(if self.ready: "ready" else: "waiting")
import expect_equal from "@std/test/test.ms"

test "custom-json":
    let text = try stringify(Status(ready: true))
    try expect_equal(text, "\"ready\"")
```

```sh
ms test custom-json.ms
```

```text
RUN custom-json.ms::custom-json
PASS custom-json.ms::custom-json
1 tests, 0 failed
```

- Custom encoding applies at every nesting level; its returned `JsonValue` is written as stored.
- For custom decoding, parse `JsonValue` and handle its shape explicitly.

*/
export interface JsonEncode:
    // Returns the JSON form of this value.
    fn to_json() JsonValue

/*
Serialize a typed request so reviewers can see its exact wire fields.

<!-- manuscript-example: {"mode":"test","filename":"json-record.ms","stdout":"RUN json-record.ms::json-record\nPASS json-record.ms::json-record\n1 tests, 0 failed\n"} -->
```manuscript {filename="json-record.ms"}
import stringify from "@std/data/json.ms"

type Request:
    model: String
    stream: Bool
    user: String?
import expect_equal from "@std/test/test.ms"

test "json-record":
    let text = try stringify(Request(model: "example", stream: true, user: none))
    try expect_equal(text, "\{\"model\":\"example\",\"stream\":true\}")
```

```sh
ms test json-record.ms
```

```text
RUN json-record.ms::json-record
PASS json-record.ms::json-record
1 tests, 0 failed
```

- Records omit absent fields; string-keyed maps encode objects. Enum payloads are tagged by variant name; `JsonEncode` selects custom shapes.
- `strict` rejects values without a JSON form. See [typed JSON](../../../learn/common-tasks.md#read-and-write-typed-json) and [custom encoding](#jsonencode).

*/
export fn stringify[T: Data](
    value: T,
    // Maximum encoded bytes, including indentation; exceeding it returns EOVERFLOW. Negative limits return EINVAL.
    max_bytes: Int?,
    // Spaces per nesting level, capped at 10; none/0 is compact. A negative indent returns EINVAL.
    indent: Int?,
    // Reject Unit with EBADMSG instead of omitting a record field or emitting null in a list; absent fields remain omitted.
    strict: Bool = false
) String!:
    return msstd_json_stringify(value, max_bytes, indent, strict)

// The member of `value` at `keys[from:]`, read one object level at a time.
fn member_path(value: JsonValue, keys: List[String], from: Int) JsonValue?:
    if from >= keys.length(): return none
    if from == keys.length() - 1: return value.get(keys[from])
    if let next = value.get(keys[from]):
        return member_path(next, keys, from + 1)

    return none

// Scanner modes: between values, inside a container, inside a top-level string, and
// inside a top-level scalar token.
type JsonReading[T: Data]:
    limits: JsonLimits
    pending: BytesBuilder
    size: Int
    depth: Int
    mode: Int
    in_string: Bool
    escaped: Bool
    finished: Bool
    failure: Error?

fn is_space(byte: UInt8) Bool:
    return (byte == 32 or byte == 9 or byte == 10 or byte == 13)

fn starts_value(byte: UInt8) Bool:
    // Object, array, string, minus sign, digits, and the first letters of the literals.
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

impl JsonReading[T]:
    var fn reset() Unit:
        self.pending = BytesBuilder()
        self.size = 0
        self.depth = 0
        self.mode = 0
        self.in_string = false
        self.escaped = false

    var fn fail(cause: Error) Unit!:
        // Dropping the partial value releases its buffered bytes.
        self.reset()
        self.failure = cause.clone()
        return error(cause)

    // Parses the buffered value and clears the scanner for the next one.
    var fn complete() T!:
        let bytes = self.pending.drain()
        self.reset()
        if let text = bytes.decode_utf8():
            return parse[T](text, self.limits)

        return error(Error("JSON: invalid data", kind: "EBADMSG"))

    // Consumes one byte and reports whether it finished a value.
    var fn scan(byte: UInt8) Bool!:
        if self.mode == 0:
            if is_space(byte): return ok(false)
            if not starts_value(byte): return error(
                Error("JSON: invalid data", kind: "EBADMSG")
            )

            self.mode = 3

            if byte == 123 or byte == 91:
                self.mode = 1
            else if byte == 34:
                self.mode = 2

        let limit = self.limits.max_bytes.get(-1)
        if self.mode == 3 and is_space(byte): return ok(true)

        self.size += 1
        if limit >= 0 and self.size > limit: return error(
            Error("JSON: limit exceeded", kind: "EOVERFLOW")
        )

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
                Error("JSON: limit exceeded", kind: "EOVERFLOW")
            )

            return ok(false)

        if byte == 125 or byte == 93:
            self.depth -= 1
            return ok(self.depth == 0)

        return ok(false)

    // Consumes one byte and returns the value it completes, if any.
    var fn advance(byte: UInt8) T?!:
        let done = try self.scan(byte)
        if not done: return ok(none)

        let value = try self.complete()
        return ok(value)

impl Transform[Bytes, T] for JsonReading[T]:
    var fn step(value: Bytes, var out: WriteStream[T]) Unit!:
        if self.finished: return error(Error("JSON: invalid input", kind: "EINVAL"))
        if let failure = self.failure: return error(failure.clone())

        for byte in value.values():
            let stepped = self.advance(byte)
            if stepped.is_error(): return self.fail(stepped.err())

            if let found = stepped.get(): try out.write(found)

        return ok(unit)

    var fn finish(var out: WriteStream[T]) Unit!:
        if self.finished: return error(Error("JSON: invalid input", kind: "EINVAL"))
        if let failure = self.failure: return error(failure.clone())

        self.finished = true
        if self.mode == 0: return ok(unit)
        if self.mode != 3: return self.fail(
            Error("JSON: invalid data", kind: "EBADMSG")
        )

        let completed = self.complete()
        if completed.is_error(): return self.fail(completed.err())

        try out.write(try completed)
        return ok(unit)

/*
Reads a sequence of JSON values of type `T` from a byte stream, such as JSON Lines or concatenated JSON.

Values may be separated by JSON whitespace or directly adjacent when they are strings, arrays, or objects.
Top-level numbers, `true`, `false`, and `null` end at whitespace or at the end of the stream. Chunk
boundaries may fall anywhere, including inside a token, an escape, or a UTF-8 scalar, and only the value
being read is buffered. `T` decodes as in `parse`; the default `JsonValue` keeps each value as a document.
`limits` applies to each value separately: `max_bytes` counts its UTF-8 bytes, `max_depth` its nesting, and
`max_values` its parsed values; an exceeded limit fails the read with `EOVERFLOW`. Omit limits only for
trusted input, because an unterminated value is otherwise buffered without bound. Malformed or truncated
input fails the read with `EBADMSG`, and negative limits with `EINVAL`. Closing the result closes
`input`.
*/
export fn json_reader[T: Data = JsonValue](
    input: ReadStream[Bytes],
    limits: JsonLimits? = none
) ReadStream[T]:
    let bounds = limits.get(JsonLimits())
    return through[Bytes, T](
        input,
        JsonReading[T](
            limits: bounds, pending: BytesBuilder(), size: 0, depth: 0, mode: 0,
            in_string: false, escaped: false, finished: false, failure: none
        )
    )

// A sink that encodes each value as one line of JSON (JSON Lines) and puts the bytes into `output`.
type JsonLines[T: Data]:
    output: WriteStream[Bytes]
    max_bytes: Int?

impl Sink[T] for JsonLines[T]:
    var fn put(value: T) Unit!:
        let text = try stringify[T](value, self.max_bytes, none)
        return self.output.write("{text}\n".to_bytes())

    var fn drain() Promise[Unit]:
        return self.output.flush()

    fn buffered() Int:
        return self.output.buffered()

    var fn close() Unit!:
        return self.output.close()

/*
Writes values of type `T` to a byte stream as JSON Lines: each value is encoded as `stringify` does, on a
single line, and ends with a line feed. `max_bytes` bounds one encoded value and fails the write with
`EOVERFLOW`. Writes delegate to `output`'s sink, which may wait. `flush().wait()` uses its completion condition; a pipe may retain up to capacity unread values. Closing closes `output`.
*/
export fn json_writer[T: Data](
    output: WriteStream[Bytes],
    max_bytes: Int? = none
) WriteStream[T]:
    return writer[T](JsonLines[T](output: output, max_bytes: max_bytes))
