# Source locations for the fixed intrinsic receiver operations.
import List from "@std/collections.ms"
import StringError from "@std/string.ms"
import NumberError from "@std/numbers.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"

# Every value has this operation, including unconstrained type parameters.
interface ValueOperations:
    fn toString() -> String

# Data values have a shallow clone returning the concrete receiver type.
interface CloneOperations[T]:
    fn clone() -> T

# String receiver operations use UTF-8 text. Methods named `scalar_*` count Unicode
# scalar values; ordinary indices and lengths count Unicode scalar positions unless
# the method explicitly refers to bytes.
interface StringOperations:
    # Normalizes using NFC, NFD, NFKC, or NFKD; max_bytes optionally bounds UTF-8 output.
    # Invalid forms or negative budgets return InvalidInput; exceeded budgets return LimitExceeded.
    fn normalize(
        form: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Concatenates text without changing either operand.
    fn concat(values: String) -> String
    # Tests whether the exact text occurs, without normalization.
    fn contains(text: String) -> Bool
    # Tests whether the receiver ends with this exact suffix.
    fn ends_with(suffix: String) -> Bool
    # Returns lowercased text.
    fn lower() -> String
    # Repeats text count times; negative counts/budgets return InvalidInput, exceeded UTF-8 budgets return LimitExceeded.
    fn repeat(
        count: Int,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Replaces the first occurrence when the cap is omitted or none; zero changes nothing, negatives fault.
    # An empty old matches at scalar boundaries, and inserted text is not searched again.
    fn replace(
        old: String,
        new: String,
        max_replacements: Optional[Int] = none
    ) -> String
    # Returns the number of Unicode scalar values in the string.
    fn scalar_length() -> Int
    # Returns each Unicode scalar value as an integer.
    fn scalar_values() -> List[Int]
    # Selects [start, end) in Unicode scalars; requires 0 <= start <= end <= scalar_length().
    # Negative, inverted, or out-of-range bounds return StringError.OutOfRange.
    fn slice_scalars(start: Int, end: Int) -> Result[String, StringError]
    # Splits exact separators, truncating parts to a supplied nonnegative cap; zero returns [], negatives fault.
    # Empty text with a nonempty separator yields [""]; an empty separator splits into scalars.
    fn split(separator: String, max_parts: Optional[Int] = none) -> List[String]
    # Tests whether the receiver begins with this exact prefix.
    fn starts_with(prefix: String) -> Bool
    # Removes Unicode whitespace at both ends; see the exact whitespace set in the text guide.
    fn trim() -> String
    # Returns uppercased text.
    fn upper() -> String
    # Returns a one-scalar String; negative indexes are relative to the end, and invalid indexes return none.
    fn at(index: Int) -> Optional[String]
    # Returns an integer scalar code point; negative indexes are relative to the end, and invalid indexes return none.
    fn scalar_at(index: Int) -> Optional[Int]
    # Returns the first matching Unicode scalar index or none; empty value matches at zero.
    fn index_of(value: String) -> Optional[Int]
    # Returns the last matching Unicode scalar index or none; empty value matches at scalar_length().
    fn last_index_of(value: String) -> Optional[Int]
    # Removes Unicode whitespace at the start.
    fn trim_start() -> String
    # Removes Unicode whitespace at the end.
    fn trim_end() -> String
    # Pads on the left until the scalar length reaches `target_length`.
    # Empty padding or a shorter target leaves text unchanged; max_bytes still bounds UTF-8 output.
    fn pad_start(
        target_length: Int,
        padding: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Pads on the right until the scalar length reaches `target_length`.
    # Empty padding or a shorter target leaves text unchanged; negative targets/budgets return InvalidInput.
    fn pad_end(
        target_length: Int,
        padding: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Replaces every nonoverlapping occurrence; empty old matches at each scalar boundary.
    # max_bytes bounds UTF-8 output; negatives return InvalidInput and exhaustion returns LimitExceeded.
    fn replace_all(
        old: String,
        new: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Selects [start, end) in scalars: negative bounds are relative to the end, then clamp to 0..scalar_length().
    # An inverted adjusted range yields empty text; the receiver is unchanged.
    fn slice(start: Int, end: Int) -> String
    # Selects a scalar range after clamping each bound to 0..scalar_length() (negative becomes zero).
    # Swaps inverted adjusted bounds; the receiver is unchanged.
    fn substring(start: Int, end: Int) -> String
    # Returns the UTF-8 encoded byte length.
    fn byte_length() -> Int
    # Encodes the string as UTF-8 bytes.
    fn to_bytes() -> Bytes
    # Parses signed ASCII decimal digits; invalid text or Int overflow returns none.
    fn parse_int() -> Optional[Int]

# Conversion operations for machine-sized integers.
interface IntOperations:
    fn to_string(radix: Int) -> String
    fn to_float() -> Float
    fn to_decimal() -> Decimal

# Formatting and classification operations for floating-point values.
interface FloatOperations:
    # Formats 1..100 significant digits, preserving trailing zeros; an invalid precision returns NumberError.InvalidInput.
    fn to_precision(precision: Int) -> Result[String, NumberError]
    # Formats scientific notation with 0..100 fractional digits; an invalid count returns NumberError.InvalidInput.
    fn to_exponential(digits: Int) -> Result[String, NumberError]
    # Formats 0..100 fractional digits; magnitude >= 1e21 uses ordinary round-trip notation.
    # Invalid digits return NumberError.InvalidInput; rounding uses binary64 ties to even.
    fn to_fixed(digits: Int) -> Result[String, NumberError]
    # Returns the shortest round-trip representation, including NaN and signed infinities.
    fn to_string() -> String
    # Tests whether the value is NaN.
    fn is_nan() -> Bool
    # Tests whether the value is neither NaN nor an infinity.
    fn is_finite() -> Bool
    # Truncates toward zero, or returns none for nonfinite values or Int overflow.
    fn truncate_to_int() -> Optional[Int]
