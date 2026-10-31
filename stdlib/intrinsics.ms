# Source locations for the fixed intrinsic receiver operations.
import StringError from "@std/string.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"

# Every value has this operation, including unconstrained type parameters.
interface ValueOperations:
    fn to_string() String

# Data values have a deep clone returning the concrete receiver type.
interface CloneOperations[T]:
    fn clone() T

# String receiver operations use UTF-8 text. Methods named `scalar_*` count Unicode
# scalar values; ordinary indices and lengths count Unicode scalar positions unless
# the method explicitly refers to bytes.
interface StringOperations:
    # Counts Unicode scalars, with the same unit as scalar_length.
    fn length() Int
    # Reports whether the text contains no scalars.
    fn is_empty() Bool
    # Returns a fresh list with one String for each Unicode scalar, in order.
    fn chars() List[String]
    # Reverses Unicode scalar order; combining sequences/graphemes may change.
    fn reverse() String
    # Returns -1, 0 or 1 in lexical scalar order, without locale or normalization.
    fn compare(other: String) Int
    # Splits LF and CRLF lines, preserving interior empty lines and standalone CR.
    # Omits a final extra empty item; empty text returns a fresh empty list.
    fn lines() List[String]
    # Normalizes using exactly NFC, NFD, NFKC, or NFKD (case-sensitive); max_bytes optionally bounds UTF-8 output.
    # Invalid forms or negative budgets return InvalidInput; exceeded budgets return LimitExceeded.
    fn normalize(form: String, max_bytes: Int?) String!StringError
    # Concatenates text without changing either operand.
    fn concat(other: String) String
    # Tests whether the exact text occurs, without normalization.
    fn contains(value: String) Bool
    # Tests whether the receiver ends with this exact suffix.
    fn ends_with(suffix: String) Bool
    # Returns locale-independent full Unicode lowercase mapping; the scalar length can change.
    fn lower() String
    # Repeats text count times; negative counts/budgets return InvalidInput, exceeded UTF-8 budgets return LimitExceeded.
    fn repeat(count: Int, max_bytes: Int?) String!StringError
    # Replaces the first occurrence of old; text without a match is unchanged.
    # An empty old matches at the first scalar boundary, so new is inserted at the start.
    fn replace_first(old: String, new: String) String
    # Replaces every nonoverlapping occurrence of old, scanning left to right; inserted text is not rescanned.
    # An empty old matches at each scalar boundary, so "ab".replace("", "-") is "-a-b-".
    # Output beyond the string limit faults like concat; use Regex.replace_all for a bounded replacement.
    fn replace(old: String, new: String) String
    # Returns the number of Unicode scalar values in the string.
    fn scalar_length() Int
    # Returns each Unicode scalar value as an integer.
    fn scalar_values() List[Int]
    # Selects [start, end) in Unicode scalars; requires 0 <= start <= end <= scalar_length().
    # Negative, inverted, or out-of-range bounds return StringError.OutOfRange.
    fn slice_scalars(start: Int, end: Int) String!StringError
    # Returns the first min(count, scalar_length()) Unicode scalars; a negative count is a programming fault.
    fn take(count: Int) String
    # Returns the scalars after the first min(count, scalar_length()); a negative count is a programming fault.
    fn drop(count: Int) String
    # Splits exact separators, truncating parts to a supplied nonnegative cap; zero returns [], negatives fault.
    # Empty text with a nonempty separator yields [""]; an empty separator splits into scalars.
    fn split(separator: String, max_parts: Int?) List[String]
    # Tests whether the receiver begins with this exact prefix.
    fn starts_with(prefix: String) Bool
    # Removes Unicode whitespace at both ends; see the exact whitespace set in the text guide.
    fn trim() String
    # Returns locale-independent full Unicode uppercase mapping; the scalar length can change.
    fn upper() String
    # Returns a one-scalar String; negative indexes are relative to the end. An invalid index returns `default`, and without one raises a fault.
    fn get(index: Int, default: String?) String
    # Returns an integer scalar code point; negative indexes are relative to the end. An invalid index returns `default`, and without one raises a fault.
    fn scalar_at(index: Int, default: Int?) Int
    # Returns the first matching Unicode scalar index or none; empty value matches at zero.
    fn index_of(value: String) Int?
    # Returns the last matching Unicode scalar index or none; empty value matches at scalar_length().
    fn last_index_of(value: String) Int?
    # Removes Unicode whitespace at the start.
    fn trim_start() String
    # Removes Unicode whitespace at the end.
    fn trim_end() String
    # Pads on the left until the scalar length reaches `target_length`, repeating `padding` and cutting its last copy.
    # A shorter or negative target or empty padding returns the text unchanged; output beyond the string limit faults like `concat`.
    # Example: `"7".pad_start(3, "0")` is `"007"`.
    fn pad_start(target_length: Int, padding: String) String
    # Pads on the right like `pad_start`. Example: `"id".pad_end(5, ".")` is `"id..."`.
    fn pad_end(target_length: Int, padding: String) String
    # Selects [start, end) in Unicode scalars; negative bounds are relative to the end.
    # Bounds outside 0 <= start <= end <= scalar_length() return StringError.OutOfRange; the receiver is unchanged.
    fn slice(start: Int, end: Int) String!StringError
    # Returns the UTF-8 encoded byte length.
    fn byte_length() Int
    # Encodes the string as UTF-8 bytes.
    fn to_bytes() Bytes
    # Parses signed ASCII decimal digits; invalid text or Int overflow returns none.
    fn parse_int() Int?
    # Parses a decimal floating-point number with the syntax of `math.parse_float`; invalid or out-of-range text returns none.
    fn parse_float() Float?

# Conversion operations for machine-sized integers.
interface IntOperations:
    # Formats the integer in a radix from 2 through 36 using lowercase digits and a leading `-` for negatives.
    # A radix outside 2 through 36 is a programming fault.
    fn to_string_radix(radix: Int) String
    # Converts to the nearest Float; integers beyond 2^53 in magnitude can lose low-order digits.
    fn to_float() Float
    # Converts to the exactly equal Decimal; no rounding occurs.
    fn to_decimal() Decimal
    # Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`.
    fn compare(other: Int) Int
    # Returns the absolute value; the most negative Int has none and faults like any overflow.
    fn abs() Int
    # Returns -1, 0 or 1 as this value is negative, zero or positive.
    fn sign() Int
    # Returns the same value; Int64 is another name for Int while Int is 64 bits wide.
    fn to_int64() Int64
    # Converts to Int; every value fits, so no check is needed.
    fn to_int() Int
    # Converts to Int8, or returns none when the value is outside Int8's range.
    fn to_int8() Int8?
    # Converts to Int16, or returns none when the value is outside Int16's range.
    fn to_int16() Int16?
    # Converts to Int32, or returns none when the value is outside Int32's range.
    fn to_int32() Int32?
    # Converts to UInt8, or returns none when the value is outside UInt8's range.
    fn to_uint8() UInt8?
    # Converts to UInt16, or returns none when the value is outside UInt16's range.
    fn to_uint16() UInt16?
    # Converts to UInt32, or returns none when the value is outside UInt32's range.
    fn to_uint32() UInt32?
    # Converts to UInt64, or returns none when the value is negative.
    fn to_uint64() UInt64?
    # Converts to Float32, rounding to the nearest binary32 value.
    fn to_float32() Float32
    # Converts to Float64, rounding to the nearest binary64 value.
    fn to_float64() Float64

# Formatting and classification operations for floating-point values.
interface FloatOperations:
    # Formats 1..100 significant digits, preserving trailing zeros; a count outside 1..100 faults.
    fn to_precision(precision: Int) String
    # Formats scientific notation with 0..100 fractional digits; a count outside 0..100 faults.
    fn to_exponential(digits: Int) String
    # Formats 0..100 fractional digits; magnitude >= 1e21 uses ordinary round-trip notation.
    # A count outside 0..100 faults; rounding uses binary64 ties to even. Example: `3.14159.to_fixed(2)` is `"3.14"`.
    fn to_fixed(digits: Int) String
    # Returns the shortest round-trip representation, including NaN and signed infinities.
    fn to_string() String
    # Tests whether the value is NaN.
    fn is_nan() Bool
    # Tests whether the value is neither NaN nor an infinity.
    fn is_finite() Bool
    # Returns -1, 0 or 1 in a total order: -0.0 equals 0.0, and NaN is equal to NaN and greater than every other value, including +Inf.
    fn compare(other: Float) Int
    # Returns the absolute value; NaN stays NaN and -0.0 becomes 0.0.
    fn abs() Float
    # Returns -1.0 or 1.0 by sign; zeros and NaN are returned unchanged.
    fn sign() Float
    # Truncates toward zero, or returns none for nonfinite values or Int overflow.
    fn truncate_to_int() Int?
    # Converts to Float32, rounding to the nearest binary32 value. A finite value too large for Float32 returns none instead of becoming infinity; NaN and infinities convert unchanged.
    fn to_float32() Float32?

# Conversion operations for Int8, a signed 8-bit integer.
interface Int8Operations:
    # Formats the integer in a radix from 2 through 36 using lowercase digits and a leading `-` for negatives.
    # A radix outside 2 through 36 is a programming fault.
    fn to_string_radix(radix: Int) String
    # Converts to the nearest Float; every Int8 converts exactly.
    fn to_float() Float
    # Converts to the exactly equal Decimal; no rounding occurs.
    fn to_decimal() Decimal
    # Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`.
    fn compare(other: Int8) Int
    # Returns the absolute value; the most negative Int8 has none and faults like any overflow.
    fn abs() Int8
    # Returns -1, 0 or 1 as this value is negative, zero or positive.
    fn sign() Int
    # Converts to Int16; every value fits, so no check is needed.
    fn to_int16() Int16
    # Converts to Int32; every value fits, so no check is needed.
    fn to_int32() Int32
    # Converts to Int64; every value fits, so no check is needed.
    fn to_int64() Int64
    # Converts to Int; every value fits, so no check is needed.
    fn to_int() Int
    # Converts to UInt8, or returns none when the value is outside UInt8's range.
    fn to_uint8() UInt8?
    # Converts to UInt16, or returns none when the value is outside UInt16's range.
    fn to_uint16() UInt16?
    # Converts to UInt32, or returns none when the value is outside UInt32's range.
    fn to_uint32() UInt32?
    # Converts to UInt64, or returns none when the value is negative.
    fn to_uint64() UInt64?
    # Converts to Float32, rounding to the nearest binary32 value.
    fn to_float32() Float32
    # Converts to Float64, rounding to the nearest binary64 value.
    fn to_float64() Float64

# Conversion operations for Int16, a signed 16-bit integer.
interface Int16Operations:
    # Formats the integer in a radix from 2 through 36 using lowercase digits and a leading `-` for negatives.
    # A radix outside 2 through 36 is a programming fault.
    fn to_string_radix(radix: Int) String
    # Converts to the nearest Float; every Int16 converts exactly.
    fn to_float() Float
    # Converts to the exactly equal Decimal; no rounding occurs.
    fn to_decimal() Decimal
    # Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`.
    fn compare(other: Int16) Int
    # Returns the absolute value; the most negative Int16 has none and faults like any overflow.
    fn abs() Int16
    # Returns -1, 0 or 1 as this value is negative, zero or positive.
    fn sign() Int
    # Converts to Int8, or returns none when the value is outside Int8's range.
    fn to_int8() Int8?
    # Converts to Int32; every value fits, so no check is needed.
    fn to_int32() Int32
    # Converts to Int64; every value fits, so no check is needed.
    fn to_int64() Int64
    # Converts to Int; every value fits, so no check is needed.
    fn to_int() Int
    # Converts to UInt8, or returns none when the value is outside UInt8's range.
    fn to_uint8() UInt8?
    # Converts to UInt16, or returns none when the value is outside UInt16's range.
    fn to_uint16() UInt16?
    # Converts to UInt32, or returns none when the value is outside UInt32's range.
    fn to_uint32() UInt32?
    # Converts to UInt64, or returns none when the value is negative.
    fn to_uint64() UInt64?
    # Converts to Float32, rounding to the nearest binary32 value.
    fn to_float32() Float32
    # Converts to Float64, rounding to the nearest binary64 value.
    fn to_float64() Float64

# Conversion operations for Int32, a signed 32-bit integer.
interface Int32Operations:
    # Formats the integer in a radix from 2 through 36 using lowercase digits and a leading `-` for negatives.
    # A radix outside 2 through 36 is a programming fault.
    fn to_string_radix(radix: Int) String
    # Converts to the nearest Float; every Int32 converts exactly.
    fn to_float() Float
    # Converts to the exactly equal Decimal; no rounding occurs.
    fn to_decimal() Decimal
    # Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`.
    fn compare(other: Int32) Int
    # Returns the absolute value; the most negative Int32 has none and faults like any overflow.
    fn abs() Int32
    # Returns -1, 0 or 1 as this value is negative, zero or positive.
    fn sign() Int
    # Converts to Int8, or returns none when the value is outside Int8's range.
    fn to_int8() Int8?
    # Converts to Int16, or returns none when the value is outside Int16's range.
    fn to_int16() Int16?
    # Converts to Int64; every value fits, so no check is needed.
    fn to_int64() Int64
    # Converts to Int; every value fits, so no check is needed.
    fn to_int() Int
    # Converts to UInt8, or returns none when the value is outside UInt8's range.
    fn to_uint8() UInt8?
    # Converts to UInt16, or returns none when the value is outside UInt16's range.
    fn to_uint16() UInt16?
    # Converts to UInt32, or returns none when the value is outside UInt32's range.
    fn to_uint32() UInt32?
    # Converts to UInt64, or returns none when the value is negative.
    fn to_uint64() UInt64?
    # Converts to Float32, rounding to the nearest binary32 value.
    fn to_float32() Float32
    # Converts to Float64, rounding to the nearest binary64 value.
    fn to_float64() Float64

# Conversion operations for UInt8, an unsigned 8-bit integer.
interface UInt8Operations:
    # Formats the integer in a radix from 2 through 36 using lowercase digits.
    # A radix outside 2 through 36 is a programming fault.
    fn to_string_radix(radix: Int) String
    # Converts to the nearest Float; every UInt8 converts exactly.
    fn to_float() Float
    # Converts to the exactly equal Decimal; no rounding occurs.
    fn to_decimal() Decimal
    # Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`.
    fn compare(other: UInt8) Int
    # Converts to Int8, or returns none when the value is outside Int8's range.
    fn to_int8() Int8?
    # Converts to Int16; every value fits, so no check is needed.
    fn to_int16() Int16
    # Converts to Int32; every value fits, so no check is needed.
    fn to_int32() Int32
    # Converts to Int64; every value fits, so no check is needed.
    fn to_int64() Int64
    # Converts to Int; every value fits, so no check is needed.
    fn to_int() Int
    # Converts to UInt16; every value fits, so no check is needed.
    fn to_uint16() UInt16
    # Converts to UInt32; every value fits, so no check is needed.
    fn to_uint32() UInt32
    # Converts to UInt64; every value fits, so no check is needed.
    fn to_uint64() UInt64
    # Converts to Float32, rounding to the nearest binary32 value.
    fn to_float32() Float32
    # Converts to Float64, rounding to the nearest binary64 value.
    fn to_float64() Float64

# Conversion operations for UInt16, an unsigned 16-bit integer.
interface UInt16Operations:
    # Formats the integer in a radix from 2 through 36 using lowercase digits.
    # A radix outside 2 through 36 is a programming fault.
    fn to_string_radix(radix: Int) String
    # Converts to the nearest Float; every UInt16 converts exactly.
    fn to_float() Float
    # Converts to the exactly equal Decimal; no rounding occurs.
    fn to_decimal() Decimal
    # Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`.
    fn compare(other: UInt16) Int
    # Converts to Int8, or returns none when the value is outside Int8's range.
    fn to_int8() Int8?
    # Converts to Int16, or returns none when the value is outside Int16's range.
    fn to_int16() Int16?
    # Converts to Int32; every value fits, so no check is needed.
    fn to_int32() Int32
    # Converts to Int64; every value fits, so no check is needed.
    fn to_int64() Int64
    # Converts to Int; every value fits, so no check is needed.
    fn to_int() Int
    # Converts to UInt8, or returns none when the value is outside UInt8's range.
    fn to_uint8() UInt8?
    # Converts to UInt32; every value fits, so no check is needed.
    fn to_uint32() UInt32
    # Converts to UInt64; every value fits, so no check is needed.
    fn to_uint64() UInt64
    # Converts to Float32, rounding to the nearest binary32 value.
    fn to_float32() Float32
    # Converts to Float64, rounding to the nearest binary64 value.
    fn to_float64() Float64

# Conversion operations for UInt32, an unsigned 32-bit integer.
interface UInt32Operations:
    # Formats the integer in a radix from 2 through 36 using lowercase digits.
    # A radix outside 2 through 36 is a programming fault.
    fn to_string_radix(radix: Int) String
    # Converts to the nearest Float; every UInt32 converts exactly.
    fn to_float() Float
    # Converts to the exactly equal Decimal; no rounding occurs.
    fn to_decimal() Decimal
    # Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`.
    fn compare(other: UInt32) Int
    # Converts to Int8, or returns none when the value is outside Int8's range.
    fn to_int8() Int8?
    # Converts to Int16, or returns none when the value is outside Int16's range.
    fn to_int16() Int16?
    # Converts to Int32, or returns none when the value is outside Int32's range.
    fn to_int32() Int32?
    # Converts to Int64; every value fits, so no check is needed.
    fn to_int64() Int64
    # Converts to Int; every value fits, so no check is needed.
    fn to_int() Int
    # Converts to UInt8, or returns none when the value is outside UInt8's range.
    fn to_uint8() UInt8?
    # Converts to UInt16, or returns none when the value is outside UInt16's range.
    fn to_uint16() UInt16?
    # Converts to UInt64; every value fits, so no check is needed.
    fn to_uint64() UInt64
    # Converts to Float32, rounding to the nearest binary32 value.
    fn to_float32() Float32
    # Converts to Float64, rounding to the nearest binary64 value.
    fn to_float64() Float64

# Conversion operations for UInt64, an unsigned 32-bit integer.
interface UInt64Operations:
    # Formats the integer in a radix from 2 through 36 using lowercase digits.
    # A radix outside 2 through 36 is a programming fault.
    fn to_string_radix(radix: Int) String
    # Converts to the nearest Float; the nearest representable value is used above 2^53.
    fn to_float() Float
    # Converts to the exactly equal Decimal; no rounding occurs.
    fn to_decimal() Decimal
    # Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`.
    fn compare(other: UInt64) Int
    # Converts to Int8, or returns none when the value is outside Int8's range.
    fn to_int8() Int8?
    # Converts to Int16, or returns none when the value is outside Int16's range.
    fn to_int16() Int16?
    # Converts to Int32, or returns none when the value is outside Int32's range.
    fn to_int32() Int32?
    # Converts to Int64, or returns none when the value is above Int64's maximum.
    fn to_int64() Int64?
    # Converts to Int, or returns none when the value is above Int's maximum.
    fn to_int() Int?
    # Converts to UInt8, or returns none when the value is outside UInt8's range.
    fn to_uint8() UInt8?
    # Converts to UInt16, or returns none when the value is outside UInt16's range.
    fn to_uint16() UInt16?
    # Converts to UInt32, or returns none when the value is outside UInt32's range.
    fn to_uint32() UInt32?
    # Converts to Float32, rounding to the nearest binary32 value.
    fn to_float32() Float32
    # Converts to Float64, rounding to the nearest binary64 value.
    fn to_float64() Float64

# Classification and conversion operations for Float32, a binary32 floating-point value.
interface Float32Operations:
    # Tests whether the value is NaN.
    fn is_nan() Bool
    # Tests whether the value is neither NaN nor an infinity.
    fn is_finite() Bool
    # Returns -1, 0 or 1 in a total order: -0.0 equals 0.0, and NaN is equal to NaN and greater than every other value, including +Inf.
    fn compare(other: Float32) Int
    # Returns the absolute value; NaN stays NaN and -0.0 becomes 0.0.
    fn abs() Float32
    # Returns -1.0 or 1.0 by sign; zeros and NaN are returned unchanged.
    fn sign() Float32
    # Truncates toward zero, or returns none for nonfinite values or Int overflow.
    fn truncate_to_int() Int?
    # Converts to Float; every Float32 converts exactly.
    fn to_float() Float
    # Converts to Float64; every Float32 converts exactly.
    fn to_float64() Float64
