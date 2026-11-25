// Source locations for the fixed intrinsic receiver operations.

import (
	Bytes from "@std/bytes.ms",
	Decimal from "@std/math/decimal.ms",
	Duration from "@std/time.ms",
)

// Every value has this operation, including unconstrained type parameters.
interface ValueOperations {
	fn to_string() String
}

// Data values have a deep `clone` that returns the receiver's own type.
interface CloneOperations[T] {
	fn clone() T
}

// The integer types that share the operations of `IntegerOperations` and
// `SignedIntegerOperations`; the checker adds an interface's operations to each type
// its type parameter's bound lists.
type IntegerTypes = Int | Int8 | Int16 | Int32 | UInt8 | UInt16 | UInt32 | UInt64
type SignedIntegerTypes = Int | Int8 | Int16 | Int32

/*
Operations shared by every integer type (`Int` and the sized signed and unsigned integers); `T` is the receiver type.
Each integer type's own `<Type>Operations` interface adds only its conversions to other integer types.
*/
interface IntegerOperations[T IntegerTypes] {
	// Formats the integer in a radix from 2 through 36 using lowercase digits and a
	// leading `-` for negatives, or null when the radix is outside 2 through 36.
	fn to_string_radix(radix Int) String?
	// Formats the integer in base 16 using lowercase digits and a leading `-` for
	// negatives, as `to_string_radix(16)` does; it cannot fail.
	fn to_hex() String
	// Formats the integer in base 2 with a leading `-` for negatives, as
	// `to_string_radix(2)` does; it cannot fail.
	fn to_binary() String
	// Converts to the nearest Float; integers beyond 2^53 in magnitude can lose
	// low-order digits.
	fn to_float() Float
	// Converts to the exactly equal Decimal; no rounding occurs.
	fn to_decimal() Decimal
	// Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`.
	fn compare(other T) Int
	// Converts to Float32, rounding to the nearest binary32 value.
	fn to_float32() Float32
}

// Operations shared by the signed integer types (`Int`, `Int8`, `Int16`, `Int32`).
interface SignedIntegerOperations[T SignedIntegerTypes] {
	// Returns the absolute value; the most negative value has null and faults like any
	// overflow.
	fn abs() T
	// Returns -1, 0 or 1 as this value is negative, zero or positive.
	fn sign() Int
}

/*
String receiver operations work on UTF-8 text. Lengths, offsets and slice bounds count bytes,
and every offset a method returns starts a scalar. Methods named `scalar_*` count Unicode scalar
values instead and scan the text. Walk characters with `chars()`.
*/
interface StringOperations {
	// The UTF-8 byte length, in constant time.
	fn length() Int
	// Reports whether the text contains no bytes.
	fn is_empty() Bool
	// Returns a list with one String for each Unicode scalar, in order. The result
	// borrows the receiver: use it in place, or `.clone()` it to keep it.
	hold fn chars() List[&String]
	// Reverses the order of Unicode scalars, so a combining sequence or grapheme
	// cluster can come out reordered.
	fn reverse() String
	// Returns -1, 0 or 1 in lexical scalar order, without locale or normalization.
	fn compare(other String) Int
	// Normalizes to the form named by `form`, which must be exactly `"NFC"`, `"NFD"`,
	// `"NFKC"` or `"NFKD"`. `max_bytes` optionally bounds the UTF-8 output. An invalid
	// form or negative bound returns `EINVAL`; exceeding the bound returns `EOVERFLOW`.
	fn normalize(form String, max_bytes Int?) String!
	// Concatenates text without changing either operand.
	fn concat(other String) String
	// Tests whether the exact text occurs, without normalization.
	fn contains(value String) Bool
	// Tests whether the receiver ends with this exact suffix.
	fn ends_with(suffix String) Bool
	// Returns the text in full Unicode lowercase, independent of locale. The scalar
	// length can change.
	fn lower() String
	// Repeats the text `count` times. A count of zero or below, or empty text, gives
	// empty text. Output beyond the string limit faults, as `concat` does.
	fn repeat(count Int) String
	// Replaces the first occurrence of `old`; text without a match is unchanged. An
	// empty `old` matches at the start, so `new` is inserted there.
	fn replace_first(old, new String) String
	/*
    Replaces every nonoverlapping occurrence of `old`, scanning left to right; inserted text is not rescanned.
    An empty `old` matches at each scalar boundary, so `"ab".replace("", "-")` is `"-a-b-"`.
    Output beyond the string limit faults, as `concat` does; use `Regex.replace_all` for a bounded replacement.
    */
	fn replace(old, new String) String
	// Counts the Unicode scalar values by scanning the text.
	fn scalar_length() Int
	// Returns each Unicode scalar value as an integer.
	fn scalar_values() List[Int]
	// Tests whether the receiver begins with this exact prefix.
	fn starts_with(prefix String) Bool
	// Removes Unicode whitespace at both ends. The exact set is listed in the text
	// guide. The result borrows the receiver, as `view` does: use it in place, or
	// `.clone()` it to keep the text.
	hold fn trim() &String
	// Returns the text in full Unicode uppercase, independent of locale. The scalar
	// length can change.
	fn upper() String
	// Returns the Unicode scalar value that starts at byte `offset`. An offset outside
	// the text or inside a scalar returns `default`, and without one raises a fault.
	fn scalar_at(offset Int, default Int?) Int
	// Counts non-overlapping occurrences; an empty part counts the scalars plus one.
	fn count(part String) Int
	// Returns the byte offset of the first match, or `null`. An empty `value` matches
	// at zero.
	fn index_of(value String) Int?
	// Returns the byte offset of the last match, or `null`. An empty `value` matches at
	// `length()`.
	fn last_index_of(value String) Int?
	hold fn trim_start() &String  // Removes Unicode whitespace at the start; borrows the receiver.
	hold fn trim_end() &String  // Removes Unicode whitespace at the end; borrows the receiver.
	/*
    Pads on the left until the scalar length reaches `target_length`, repeating `padding` and cutting its last copy.
    A target that is not longer than the text, a negative target, or empty padding returns the text unchanged.
    Output beyond the string limit faults, as `concat` does.
    Example: `"7".pad_start(3, "0")` is `"007"`.
    */
	fn pad_start(target_length Int, padding String) String
	// Pads on the right like `pad_start`. Example: `"id".pad_end(5, ".")` is `"id..."`.
	fn pad_end(target_length Int, padding String) String
	// Copies the bytes [start, end); negative bounds are relative to the end. Bounds
	// outside the text clamp to it, and a start at or past the end gives `""`. A bound
	// inside a scalar moves inward (start forward, end backward), so the result is
	// always whole characters. The call never fails and leaves the receiver unchanged.
	fn slice(start, end Int) String
	// Borrows the bytes [start, end) of the receiver without copying; negative bounds
	// are relative to the end. Bounds outside 0 <= start <= end <= length(), or inside
	// a scalar, raise a fault. Like `Bytes.view`, the result borrows the receiver,
	// which cannot change while the view is used; `.clone()` keeps the text. Use
	// `slice` for a copy.
	hold fn view(start, end Int) &String
	// Borrows the UTF-8 bytes of the text without copying. Like `view`, the result
	// borrows the receiver, which cannot change while the bytes are used; `.clone()`
	// keeps them. Use `to_bytes` for a copy.
	hold fn view_bytes() &Bytes
	// Encodes the string as UTF-8 bytes.
	fn to_bytes() Bytes
	// Parses signed ASCII decimal digits; invalid text or Int overflow returns null.
	fn parse_int() Int?
	// Parses a decimal floating-point number with the syntax of `math.parse_float`;
	// invalid or out-of-range text returns null.
	fn parse_float() Float?
}

// Conversion operations for machine-sized integers.
interface IntOperations {
	// A Duration of this many milliseconds, as in `500.milliseconds()`; faults when the
	// nanosecond count overflows Int.
	fn milliseconds() Duration
	// A Duration of this many seconds, as in `2.seconds()`; faults when the nanosecond
	// count overflows Int.
	fn seconds() Duration
	// A Duration of this many minutes, as in `2.minutes()`; faults when the nanosecond
	// count overflows Int.
	fn minutes() Duration
	// Returns the same value. `Int64` is another name for `Int` while `Int` is 64 bits
	// wide.
	fn to_int64() Int64
	// Converts to Int; every value fits, so no check is needed.
	fn to_int() Int
	// Converts to Int8, or returns null when the value is outside Int8's range.
	fn to_int8() Int8?
	// Converts to Int16, or returns null when the value is outside Int16's range.
	fn to_int16() Int16?
	// Converts to Int32, or returns null when the value is outside Int32's range.
	fn to_int32() Int32?
	// Converts to UInt8, or returns null when the value is outside UInt8's range.
	fn to_uint8() UInt8?
	// Converts to UInt16, or returns null when the value is outside UInt16's range.
	fn to_uint16() UInt16?
	// Converts to UInt32, or returns null when the value is outside UInt32's range.
	fn to_uint32() UInt32?
	// Converts to UInt64, or returns null when the value is negative.
	fn to_uint64() UInt64?
}

// Formatting and classification operations for floating-point values.
interface FloatOperations {
	// Formats with `precision` significant digits, from 1 to 100, keeping trailing
	// zeros; a count outside 1..100 faults.
	fn to_precision(precision Int) String
	// Formats in scientific notation with `digits` fractional digits, from 0 to 100; a
	// count outside 0..100 faults.
	fn to_exponential(digits Int) String
	// Formats with `digits` fractional digits, from 0 to 100; a magnitude of 1e21 or
	// more uses the ordinary round-trip notation. A count outside 0..100 faults.
	// Rounding is binary64 round half to even.
	// Example: `3.14159.to_fixed(2)` is `"3.14"`.
	fn to_fixed(digits Int) String
	// Returns the shortest round-trip representation, including NaN and signed
	// infinities.
	fn to_string() String
	// Tests whether the value is NaN.
	fn is_nan() Bool
	// Tests whether the value is neither NaN nor an infinity.
	fn is_finite() Bool
	// Returns -1, 0 or 1 in a total order: -0.0 equals 0.0, and NaN is equal to NaN and
	// greater than every other value, including +Inf.
	fn compare(other Float) Int
	// Returns the absolute value; NaN stays NaN and -0.0 becomes 0.0.
	fn abs() Float
	// Returns -1.0 or 1.0 by sign; zeros and NaN are returned unchanged.
	fn sign() Float
	// Truncates toward zero, or returns null for nonfinite values or Int overflow.
	fn truncate_to_int() Int?
	// Converts to Float32, rounding to the nearest binary32 value. A finite value too
	// large for Float32 returns null instead of becoming infinity; NaN and infinities
	// convert unchanged.
	fn to_float32() Float32?
}

// Conversion operations for Int8, a signed 8-bit integer.
interface Int8Operations {
	// Converts to Int16; every value fits, so no check is needed.
	fn to_int16() Int16
	// Converts to Int32; every value fits, so no check is needed.
	fn to_int32() Int32
	// Converts to Int64; every value fits, so no check is needed.
	fn to_int64() Int64
	// Converts to Int; every value fits, so no check is needed.
	fn to_int() Int
}

// Conversion operations for Int16, a signed 16-bit integer.
interface Int16Operations {
	// Converts to Int8, or returns null when the value is outside Int8's range.
	fn to_int8() Int8?
	// Converts to Int64; every value fits, so no check is needed.
	fn to_int64() Int64
	// Converts to Int; every value fits, so no check is needed.
	fn to_int() Int
}

// Conversion operations for Int32, a signed 32-bit integer.
interface Int32Operations {
	// Converts to Int8, or returns null when the value is outside Int8's range.
	fn to_int8() Int8?
	// Converts to Int16, or returns null when the value is outside Int16's range.
	fn to_int16() Int16?
	// Converts to Int64; every value fits, so no check is needed.
	fn to_int64() Int64
	// Converts to Int; every value fits, so no check is needed.
	fn to_int() Int
}

// Conversion operations for UInt8, an unsigned 8-bit integer.
interface UInt8Operations {
	// Converts to Int; every value fits, so no check is needed.
	fn to_int() Int
}

// Conversion operations for UInt16, an unsigned 16-bit integer.
interface UInt16Operations {
	// Converts to Int; every value fits, so no check is needed.
	fn to_int() Int
	// Converts to UInt8, or returns null when the value is outside UInt8's range.
	fn to_uint8() UInt8?
}

// Conversion operations for UInt32, an unsigned 32-bit integer.
interface UInt32Operations {
	// Converts to Int32, or returns null when the value is outside Int32's range.
	fn to_int32() Int32?
	// Converts to Int64; every value fits, so no check is needed.
	fn to_int64() Int64
	// Converts to Int; every value fits, so no check is needed.
	fn to_int() Int
}

// Conversion operations for UInt64, an unsigned 64-bit integer.
interface UInt64Operations {
	// Converts to Int, or returns null when the value is above Int's maximum.
	fn to_int() Int?
	// Converts to UInt8, or returns null when the value is outside UInt8's range.
	fn to_uint8() UInt8?
	// Converts to UInt32, or returns null when the value is outside UInt32's range.
	fn to_uint32() UInt32?
}

// Classification and conversion operations for Float32, a binary32 floating-point
// value.
interface Float32Operations {
	// Tests whether the value is NaN.
	fn is_nan() Bool
	// Tests whether the value is neither NaN nor an infinity.
	fn is_finite() Bool
	// Returns -1, 0 or 1 in a total order: -0.0 equals 0.0, and NaN is equal to NaN and
	// greater than every other value, including +Inf.
	fn compare(other Float32) Int
	// Returns the absolute value; NaN stays NaN and -0.0 becomes 0.0.
	fn abs() Float32
	// Returns -1.0 or 1.0 by sign; zeros and NaN are returned unchanged.
	fn sign() Float32
	// Truncates toward zero, or returns null for nonfinite values or Int overflow.
	fn truncate_to_int() Int?
	fn to_float() Float  // Converts to Float; every Float32 converts exactly.
	fn to_float64() Float64  // Converts to Float64; every Float32 converts exactly.
}
