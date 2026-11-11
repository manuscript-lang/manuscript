import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	Promise from "@std/concurrency/promise.ms",
	Data from "@std/core.ms",
	ReadStream, Sink, Transform, WriteStream, through from "@std/io/io.ms",
	parse_float from "@std/math/math.ms",

	JsonLimits, msstd_json_parse, msstd_json_stringify from "@std/internal/json.ms",
)

// Settings for `parse` and `json_reader`: optional bounds on input bytes, nesting depth
// and parsed values, and how object members that are not fields are treated.
export type JsonOptions:
	// Maximum UTF-8 input bytes before parsing; none adds no input-size budget.
	max_bytes: Int? = none
	// Maximum container nesting; a root scalar has depth zero, and a root container
	// depth one.
	max_depth: Int? = none
	// Maximum parsed containers and scalar values, excluding object keys; none adds no
	// count budget.
	max_values: Int? = none
	// True ignores object members that are not fields of `T`; false makes them return
	// `EBADMSG`.
	ignore_unknown_fields: Bool = true

// Settings for `stringify`: an output byte budget, pretty-print indentation, and strict
// rejection of values without a JSON form.
export type StringifyOptions:
	// Maximum encoded UTF-8 bytes; none adds no output budget.
	max_bytes: Int? = none
	// Spaces per indentation level; none writes compact JSON.
	indent: Int? = none
	// True makes any value without a JSON form, anywhere in the document, return
	// `EBADMSG`.
	strict: Bool = false

/*
A JSON value. Number text is retained to avoid losing precision during parsing.

`get` and `at` read one level and `as_*` read a scalar or container, each returning `none` on a
mismatch. `get` and `at` borrow the selected part; keep the document available and unchanged
while using it. `as_string`, `as_list` and `as_map` explicitly clone their payloads. Nested reads
bind each level with `if let`:

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
if user := doc.get("user"):
    if name := user.get("name"):
        return name.as_string().get("")
```

`get_in` reads a chain of object members in one call and lends the result: `doc.get_in(["user", "name"])`.
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
	// A JSON object retaining insertion order and rejecting duplicate keys during
	// parsing.
	ObjectValue(
		// String-keyed members in insertion order; stringify reads their current
		// values.
		values: Map[String, JsonValue]
	)

// A JSON document is Data, including its string-keyed object members.
impl Data for JsonValue:

impl JsonValue:
	// Returns the object member for `key`, or `none` for an absent key or a value that
	// is not an object. The result borrows from the receiver.
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

	// Returns the array element at `index`, counting a negative index from the end. An
	// index out of range, or a value that is not an array, returns `none`. The result
	// borrows from the receiver.
	fn at(index: Int) JsonValue?:
		match self:
			ArrayValue(values):
				if index >= values.length() or index < 0 - values.length(): return none
				return values.get(index)
			_: return none

	// Returns the text of a string value, or `none` for any other value. The result is
	// an owned copy.
	fn as_string() String?:
		match self:
			StringValue(value): return value.clone()
			_: return none

	// Returns a number value as an Int, or `none` when the value is not a number or its
	// text has a fraction, an exponent, or digits that do not fit in Int.
	fn as_int() Int?:
		match self:
			NumberValue(text): return text.parse_int()
			_: return none

	// Returns a number value as a Float, or `none` when the value is not a number or
	// its text is not finite.
	fn as_float() Float?:
		match self:
			NumberValue(text): return parse_float(text).to_optional()
			_: return none

	// Returns a boolean value, or `none` for any other value.
	fn as_bool() Bool?:
		match self:
			BoolValue(value): return value
			_: return none

	// Returns the elements of an array value, or `none` for any other value. The result
	// is an owned copy.
	fn as_list() List[JsonValue]?:
		match self:
			ArrayValue(values): return values.clone()
			_: return none

	// Returns the members of an object value, or `none` for any other value. The result
	// is an owned copy.
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
Parses one JSON value and applies the supplied input, depth, and value limits.

With the default `T = JsonValue` the result is the parsed tree. Any other `T` is read from the
document by the inverse of the `stringify` encoding, so `parse[Request](text)` and `result: Request! = parse(text)`
return a decoded `Request` in a `Result` (`try` passes no expected type, so write `try parse[Request](text)`). A value whose shape does not match `T` returns
`EBADMSG`; a type that is not `Data` is rejected at compile time. Input, depth and value limits
apply to the document before decoding.

- A record is an object. Members may appear in any order. An absent member takes the field's default,
  else `none` for an `Optional` field. An absent `Unit` field becomes `unit`; any other absent
  required field returns `EBADMSG`. A member that is not a field is ignored, unless
  `ignore_unknown_fields` is `false`, which makes it return `EBADMSG`.
- An alternative case without payload is its name as a string; one with payload is externally tagged,
  `{"Circle":{"radius":2}}`, with the same member rules for the labeled fields. Standard alternatives such
  as `Result` follow the same rule, so `{"ok":{"value":5}}` reads as `ok(5)`.
- `T?` reads `null` as `none`, so a present `none` (an `Int??` holding `none`), written as `null`, reads back as `none`. `List` reads an array.
- A sized integer accepts integer digits within its own range, and `Float32` any finite number that fits it.
- `Int` accepts integer digits that fit in the platform's Int, `Float` any finite number, `BigInt` and `Decimal`
  the exact number text. A `null` Float, which `stringify` writes for `NaN` and infinities, returns
  `EBADMSG`.
- `Timestamp` reads an RFC 3339 string, `Duration` integer nanoseconds, `Bytes` a standard base64
  string, and `Url`, `IpAddress` and `Cidr` their string forms.
- `Map[String, T]` reads an object when `T` is `Data`; `JsonValue` keeps its subtree as parsed.

The record-or-document choice comes from `T`, not from the text: `parse[Request]` reads an object as a
record and `parse[JsonValue]` keeps it as a document.
*/
export fn parse[T: Data = JsonValue](
	text: String,
	options: JsonOptions = JsonOptions()
) T!:
	limits := JsonLimits(
		max_bytes: options.max_bytes, max_depth: options.max_depth,
		max_values: options.max_values
	)
	return msstd_json_parse[T](text, limits, options.ignore_unknown_fields)

/*
Customizes how `stringify` encodes a type. It takes precedence over the
structural encoding for every record and alternative, so it is the way to choose a tagged or
discriminator encoding, or any other shape. A value whose type implements it is encoded as the
`JsonValue` its `to_json` returns, wherever it appears: at the root, in a field, in a list, or as a map
value. The returned `JsonValue` is written as stored and is not customized again. Implement it in the
module that defines the type. Custom typed decoding is not supported; parse a `JsonValue`
and handle its cases when the input needs a different shape.

The default encoding of an alternative is externally tagged, `{"Created":{"id":1}}`, so a structural
encoding round-trips. This implementation writes an internal `type` discriminator instead, a common
protocol shape:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import JsonEncode, JsonValue from "@std/data/json.ms"

enum Event:
    Created(id: Int)
    Deleted(id: Int)

impl JsonEncode for Event:
    fn to_json() JsonValue:
        match self:
            Created(id): return tagged("created", id)
            Deleted(id): return tagged("deleted", id)

fn tagged(kind: String, id: Int) JsonValue:
    var fields = Map[String, JsonValue]()
    fields.add("type", JsonValue.StringValue(kind))
    fields.add("id", JsonValue.NumberValue("{id}"))
    return JsonValue.ObjectValue(fields)
```
*/
export interface JsonEncode:
	// Returns the JSON form of this value.
	fn to_json() JsonValue

/*
Encodes a `Data` value as JSON text; a type that is not `Data` is rejected at compile time.

- Record fields appear in declaration order. A field holding `none` is omitted; so is a field
  holding a value with no JSON form (`Unit`).
- `none` elsewhere (a list element, the root) is `null`, as is a no-form list element.
  `T??` is allowed: a present `none` is `null` and an absent value is omitted.
- A root value with no JSON form returns `EBADMSG`.
- An alternative case without payload is its name as a string, `"Dot"`. A case with payload is
  externally tagged: `{"Circle":{"radius":2}}`, an object keyed by the case name whose value holds
  the labeled fields under the record rules. Payload labels never collide with a discriminator.
- `Map[String, T]` is an object when `T` is `Data`. Other map keys and `Set` fail the `Data` bound.
- The sized integers (`Int8` to `Int32`, `UInt8` to `UInt64`) are exact decimal digits, as `Int`.
  `Float32` is the shortest decimal that reads back as the same `Float32`; NaN and infinities are `null`.
- Int, BigInt and Decimal are exact decimal digits. Float uses the shortest decimal that parses
  back to the same value; NaN and infinities are `null`.
- `Timestamp` is an RFC 3339 string in UTC, `Duration` its integer nanoseconds, `Bytes` a standard
  base64 string, `Url` its string form, `IpAddress` and `Cidr` their text. `Result`, other standard records and
  alternatives follow the ordinary rules, so `ok(5)` is `{"ok":{"value":5}}`.
- A `JsonValue` is written as stored, so parsed documents mix with typed data.
- A type that implements `JsonEncode` is written as the `JsonValue` its `to_json` returns, instead of any rule above.
- Strings are UTF-8 JSON strings; only quotes, backslashes and control characters are escaped, so `<`, `>` and `&` stay as written.
- Values are read when `stringify` runs, so later mutation does not change the text. Ownership
  prevents cyclic values; each contained value is encoded where it appears.

`strict` makes any value without a JSON form, anywhere in the document, return `EBADMSG` instead
of being omitted or written as `null`. This covers `Unit`; functions, resources and interface values
fail the `Data` bound at compile time. A field holding `none` is still omitted.

`indent` pretty-prints with that many spaces per level, at most 10; none or 0 is compact. Empty
containers stay `{}` and `[]`, and a space follows each colon. `max_bytes` bounds the output,
indentation included; exceeding it returns `EOVERFLOW`. A negative bound or indent returns
`EINVAL`.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
type Request:
    model: String
    stream: Bool
    user: String?

text := try stringify(Request(model: "example", stream: true, user: none))
```
*/
export fn stringify[T: Data](
	value: T,
	options: StringifyOptions = StringifyOptions()
) String!:
	return msstd_json_stringify(
		value, options.max_bytes, options.indent, options.strict
	)

// The member of `value` at `keys[from:]`, read one object level at a time.
fn member_path(value: JsonValue, keys: List[String], from: Int) JsonValue?:
	if from >= keys.length(): return none
	if from == keys.length() - 1: return value.get(keys[from])
	if next := value.get(keys[from]): return member_path(next, keys, from + 1)

	return none

// Scanner modes: between values, inside a container, inside a top-level string, and
// inside a top-level scalar token.
type JsonReading[T: Data]:
	options: JsonOptions
	pending: BytesBuilder
	size: Int
	depth: Int
	mode: Int
	in_string: Bool
	escaped: Bool
	finished: Bool
	failure: Error?

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
		bytes := self.pending.drain()
		self.reset()
		if text := bytes.decode_utf8(): return parse[T](text, self.options)

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

		limit := self.options.max_bytes.get(-1)
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
			if self.depth > self.options.max_depth.get(self.depth): return error(
				Error("JSON: limit exceeded", kind: "EOVERFLOW")
			)

			return ok(false)

		if byte == 125 or byte == 93:
			self.depth -= 1
			return ok(self.depth == 0)

		return ok(false)

	// Consumes one byte and returns the value it completes, if any.
	var fn advance(byte: UInt8) T?!:
		done := try self.scan(byte)
		if not done: return ok(none)

		value := try self.complete()
		return ok(value)

impl Transform[Bytes, T] for JsonReading[T]:
	var fn step(value: Bytes, var out: List[T]) Unit!:
		if self.finished: return error(Error("JSON: invalid input", kind: "EINVAL"))
		if failure := self.failure: return error(failure.clone())

		for byte in value.values():
			stepped := self.advance(byte)
			if stepped.is_error(): return self.fail(stepped.err())

			if found := stepped.get(none): out.append(found)

	var fn finish(var out: List[T]) Unit!:
		if self.finished: return error(Error("JSON: invalid input", kind: "EINVAL"))
		if failure := self.failure: return error(failure.clone())

		self.finished = true
		if self.mode == 0: return ok(unit)
		if self.mode != 3: return self.fail(
			Error("JSON: invalid data", kind: "EBADMSG")
		)

		completed := self.complete()
		if completed.is_error(): return self.fail(completed.err())

		out.append(try completed)

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

// The error a negative limit reports on the first read, or none.
fn invalid_limits(options: JsonOptions) Error?:
	if (
		options.max_bytes.get(0) < 0
		or options.max_depth.get(0) < 0
		or options.max_values.get(0) < 0
	):
		return Error("JSON: invalid options", kind: "EINVAL")
	return none

/*
Reads a sequence of JSON values of type `T` from a byte stream, such as JSON Lines or concatenated JSON.

Values may be separated by JSON whitespace or directly adjacent when they are strings, arrays, or objects.
Top-level numbers, `true`, `false`, and `null` end at whitespace or at the end of the stream. Chunk
boundaries may fall anywhere, including inside a token, an escape, or a UTF-8 scalar, and only the value
being read is buffered. `T` decodes as in `parse`; the default `JsonValue` keeps each value as a document.
`options` applies to each value separately: `max_bytes` counts its UTF-8 bytes, `max_depth` its nesting, and
`max_values` its parsed values; an exceeded limit fails the read with `EOVERFLOW`. Leave the bounds unset only for
trusted input, because an unterminated value is otherwise buffered without bound. Malformed or truncated
input fails the read with `EBADMSG`, and negative limits with `EINVAL`. Closing the result closes
`input`.
*/
export fn json_reader[T: Data = JsonValue](
	input: ReadStream[Bytes],
	options: JsonOptions = JsonOptions()
) ReadStream[T]:
	failure := invalid_limits(options)
	return through[Bytes, T](
		input,
		JsonReading[T](
			options: options, pending: BytesBuilder(), size: 0, depth: 0, mode: 0,
			in_string: false, escaped: false, finished: false, failure: failure
		)
	)

// A sink that encodes each value as one line of JSON (JSON Lines) and puts the bytes
// into `output`.
type JsonLines[T: Data]:
	output: WriteStream[Bytes]
	max_bytes: Int?

impl Sink[T] for JsonLines[T]:
	var fn write(value: T) Unit!:
		text := try stringify[T](value, StringifyOptions(max_bytes: self.max_bytes))
		return self.output.write("{text}\n".to_bytes())

	var fn flush() Unit!:
		return self.output.flush()

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
	return WriteStream[T](JsonLines[T](output: output, max_bytes: max_bytes))
