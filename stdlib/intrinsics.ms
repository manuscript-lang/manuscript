# Source locations for the fixed intrinsic receiver operations.
from "@std/string.ms" import StringError
from "@std/math.ms" import NumberError
from "@std/bytes.ms" import Bytes
from "@std/decimal.ms" import Decimal

# Every value has this operation, including unconstrained type parameters.
interface ValueOperations:
    def to_string() -> String

# Data values have a deep clone returning the concrete receiver type.
interface CloneOperations[T]:
    def clone() -> T

# String receiver operations use UTF-8 text. Methods named `scalar_*` count Unicode
# scalar values; ordinary indices and lengths count Unicode scalar positions unless
# the method explicitly refers to bytes.
interface StringOperations:
    # Counts Unicode scalars, with the same unit as scalar_length.
    def length() -> Int
    # Reports whether the text contains no scalars.
    def is_empty() -> Bool
    # Returns a fresh list with one String for each Unicode scalar, in order.
    def chars() -> List[String]
    # Reverses Unicode scalar order; combining sequences/graphemes may change.
    def reverse() -> String
    # Returns -1, 0 or 1 in lexical scalar order, without locale or normalization.
    def compare(other: String) -> Int
    # Splits LF and CRLF lines, preserving interior empty lines and standalone CR.
    # Omits a final extra empty item; empty text returns a fresh empty list.
    def lines() -> List[String]
    # Normalizes using exactly NFC, NFD, NFKC, or NFKD (case-sensitive); max_bytes optionally bounds UTF-8 output.
    # Invalid forms or negative budgets return InvalidInput; exceeded budgets return LimitExceeded.
    def normalize(
        form: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Concatenates text without changing either operand.
    def concat(other: String) -> String
    # Tests whether the exact text occurs, without normalization.
    def contains(value: String) -> Bool
    # Tests whether the receiver ends with this exact suffix.
    def ends_with(suffix: String) -> Bool
    # Returns locale-independent full Unicode lowercase mapping; the scalar length can change.
    def lower() -> String
    # Repeats text count times; negative counts/budgets return InvalidInput, exceeded UTF-8 budgets return LimitExceeded.
    def repeat(
        count: Int,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Transitional compatibility name: omitted or none replaces the first occurrence; an explicit cap can replace more.
    # Use replace_n for a required finite cap; this retained signature has not become a strict first-only operation.
    # An empty old matches at scalar boundaries, and inserted text is not searched again.
    # Zero changes nothing; negative caps retain replace's programming fault.
    def replace_first(
        old: String,
        new: String,
        max_replacements: Optional[Int] = none
    ) -> String
    # Replaces at most the required number of nonoverlapping literal occurrences; zero leaves text unchanged.
    # Empty old matches at scalar boundaries, inserted text is not rescanned, and negative caps retain replace's programming fault.
    # The count limits replacements, not UTF-8 output bytes; there is no additional allocation budget.
    def replace_n(old: String, new: String, max_replacements: Int) -> String
    # Compatibility spelling for replace_first, including its explicit replacement cap.
    def replace(
        old: String,
        new: String,
        max_replacements: Optional[Int] = none
    ) -> String
    # Returns the number of Unicode scalar values in the string.
    def scalar_length() -> Int
    # Returns each Unicode scalar value as an integer.
    def scalar_values() -> List[Int]
    # Selects [start, end) in Unicode scalars; requires 0 <= start <= end <= scalar_length().
    # Negative, inverted, or out-of-range bounds return StringError.OutOfRange.
    def slice_scalars(start: Int, end: Int) -> Result[String, StringError]
    # Returns the first min(count, scalar_length()) Unicode scalars; a negative count is a programming fault.
    def take(count: Int) -> String
    # Returns the scalars after the first min(count, scalar_length()); a negative count is a programming fault.
    def drop(count: Int) -> String
    # Splits exact separators, truncating parts to a supplied nonnegative cap; zero returns [], negatives fault.
    # Empty text with a nonempty separator yields [""]; an empty separator splits into scalars.
    def split(separator: String, max_parts: Optional[Int] = none) -> List[String]
    # Tests whether the receiver begins with this exact prefix.
    def starts_with(prefix: String) -> Bool
    # Removes Unicode whitespace at both ends; see the exact whitespace set in the text guide.
    def trim() -> ref String
    # Returns locale-independent full Unicode uppercase mapping; the scalar length can change.
    def upper() -> String
    # Returns a one-scalar String; negative indexes are relative to the end. An invalid index returns `default`, and without one raises a fault.
    def get(index: Int, default: Optional[String] = none) -> String
    # Returns an integer scalar code point; negative indexes are relative to the end. An invalid index returns `default`, and without one raises a fault.
    def scalar_at(index: Int, default: Optional[Int] = none) -> Int
    # Returns the first matching Unicode scalar index or none; empty value matches at zero.
    def index_of(value: String) -> Optional[Int]
    # Returns the last matching Unicode scalar index or none; empty value matches at scalar_length().
    def last_index_of(value: String) -> Optional[Int]
    # Removes Unicode whitespace at the start.
    def trim_start() -> ref String
    # Removes Unicode whitespace at the end.
    def trim_end() -> ref String
    # Pads on the left until the scalar length reaches `target_length`.
    # Empty padding or a shorter target leaves text unchanged; max_bytes still bounds UTF-8 output.
    def pad_start(
        target_length: Int,
        padding: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Pads on the right until the scalar length reaches `target_length`.
    # Empty padding or a shorter target leaves text unchanged; negative targets/budgets return InvalidInput.
    def pad_end(
        target_length: Int,
        padding: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Replaces every nonoverlapping occurrence; empty old matches at each scalar boundary.
    # max_bytes bounds UTF-8 output; negatives return InvalidInput and exhaustion returns LimitExceeded.
    def replace_all(
        old: String,
        new: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Selects [start, end) in Unicode scalars; negative bounds are relative to the end.
    # Bounds outside 0 <= start <= end <= scalar_length() return StringError.OutOfRange; the receiver is unchanged.
    def slice(start: Int, end: Int) -> Result[String, StringError]
    # Returns the UTF-8 encoded byte length.
    def byte_length() -> Int
    # Encodes the string as UTF-8 bytes.
    def to_bytes() -> Bytes
    # Parses signed ASCII decimal digits; invalid text or Int overflow returns none.
    def parse_int() -> Optional[Int]

# Conversion operations for machine-sized integers.
interface IntOperations:
    # Formats the integer in a radix from 2 through 36 using lowercase digits and a leading `-` for negatives.
    # A radix outside 2 through 36 is a programming fault.
    def to_string_radix(radix: Int) -> String
    # Converts to the nearest Float; integers beyond 2^53 in magnitude can lose low-order digits.
    def to_float() -> Float
    # Converts to the exactly equal Decimal; no rounding occurs.
    def to_decimal() -> Decimal
    # Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`.
    def compare(other: Int) -> Int

# Formatting and classification operations for floating-point values.
interface FloatOperations:
    # Formats 1..100 significant digits, preserving trailing zeros; an invalid precision returns NumberError.InvalidInput.
    def to_precision(precision: Int) -> Result[String, NumberError]
    # Formats scientific notation with 0..100 fractional digits; an invalid count returns NumberError.InvalidInput.
    def to_exponential(digits: Int) -> Result[String, NumberError]
    # Formats 0..100 fractional digits; magnitude >= 1e21 uses ordinary round-trip notation.
    # Invalid digits return NumberError.InvalidInput; rounding uses binary64 ties to even.
    def to_fixed(digits: Int) -> Result[String, NumberError]
    # Returns the shortest round-trip representation, including NaN and signed infinities.
    def to_string() -> String
    # Tests whether the value is NaN.
    def is_nan() -> Bool
    # Tests whether the value is neither NaN nor an infinity.
    def is_finite() -> Bool
    # Returns -1, 0 or 1 in a total order: -0.0 equals 0.0, and NaN is equal to NaN and greater than every other value, including +Inf.
    def compare(other: Float) -> Int
    # Truncates toward zero, or returns none for nonfinite values or Int overflow.
    def truncate_to_int() -> Optional[Int]
