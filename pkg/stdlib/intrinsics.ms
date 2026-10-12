# Source locations for the fixed intrinsic receiver operations.
import List from "@std/collections.ms"
import StringError from "@std/string.ms"
import NumberError from "@std/numbers.ms"
import Result from "@std/result.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import Optional from "@std/optional.ms"

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
    # Normalizes text using a Unicode normalization form such as `NFC` or `NFKC`.
    fn normalize(
        form: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    fn concat(values: String) -> String
    fn contains(text: String) -> Bool
    fn ends_with(suffix: String) -> Bool
    fn lower() -> String
    fn repeat(
        count: Int,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    fn replace(
        old: String,
        new: String,
        max_replacements: Optional[Int] = none
    ) -> String
    # Returns the number of Unicode scalar values in the string.
    fn scalar_length() -> Int
    # Returns each Unicode scalar value as an integer.
    fn scalar_values() -> List[Int]
    # Returns a scalar-indexed half-open range or an error for invalid bounds.
    fn slice_scalars(start: Int, end: Int) -> Result[String, StringError]
    fn split(separator: String, max_parts: Optional[Int] = none) -> List[String]
    fn starts_with(prefix: String) -> Bool
    fn trim() -> String
    fn upper() -> String
    fn at(index: Int) -> Optional[String]
    # Returns a scalar at the zero-based index, or `none` when out of range.
    fn scalar_at(index: Int) -> Optional[Int]
    fn index_of(value: String) -> Optional[Int]
    fn last_index_of(value: String) -> Optional[Int]
    fn trim_start() -> String
    fn trim_end() -> String
    # Pads on the left until the scalar length reaches `target_length`.
    fn pad_start(
        target_length: Int,
        padding: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Pads on the right until the scalar length reaches `target_length`.
    fn pad_end(
        target_length: Int,
        padding: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    fn replace_all(
        old: String,
        new: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    fn slice(start: Int, end: Int) -> String
    fn substring(start: Int, end: Int) -> String
    # Returns the UTF-8 encoded byte length.
    fn byte_length() -> Int
    # Encodes the string as UTF-8 bytes.
    fn to_bytes() -> Bytes
    fn parse_int() -> Optional[Int]

# Conversion operations for machine-sized integers.
interface IntOperations:
    fn to_string(radix: Int) -> String
    fn to_float() -> Float
    fn to_decimal() -> Decimal

# Formatting and classification operations for floating-point values.
interface FloatOperations:
    fn to_precision(precision: Int) -> Result[String, NumberError]
    fn to_exponential(digits: Int) -> Result[String, NumberError]
    fn to_fixed(digits: Int) -> Result[String, NumberError]
    fn to_string() -> String
    fn is_nan() -> Bool
    fn is_finite() -> Bool
    fn truncate_to_int() -> Optional[Int]
