# Source locations for the fixed intrinsic receiver operations.
import List from "@std/collections.ms"
import StringError from "@std/string.ms"
import NumberError from "@std/numbers.ms"
import Result from "@std/result.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import Optional from "@std/optional.ms"

interface StringOperations:
    fn normalize(form: String, max_bytes: Int) -> Result[String, StringError]
    fn concat(values: String) -> String
    fn contains(text: String) -> Bool
    fn ends_with(suffix: String) -> Bool
    fn lower() -> String
    fn repeat(count: Int, max_bytes: Int) -> Result[String, StringError]
    fn replace(old: String, new: String, max_replacements: Int) -> String
    fn scalar_length() -> Int
    fn scalar_values() -> List[Int]
    fn slice_scalars(start: Int, end: Int) -> Result[String, StringError]
    fn split(separator: String, max_parts: Int) -> List[String]
    fn starts_with(prefix: String) -> Bool
    fn trim() -> String
    fn upper() -> String
    fn at(index: Int) -> Optional[String]
    fn scalar_at(index: Int) -> Optional[Int]
    fn index_of(value: String) -> Optional[Int]
    fn last_index_of(value: String) -> Optional[Int]
    fn trim_start() -> String
    fn trim_end() -> String
    fn pad_start(target_length: Int, padding: String, max_bytes: Int) -> Result[String, StringError]
    fn pad_end(target_length: Int, padding: String, max_bytes: Int) -> Result[String, StringError]
    fn replace_all(old: String, new: String, max_bytes: Int) -> Result[String, StringError]
    fn slice(start: Int, end: Int) -> String
    fn substring(start: Int, end: Int) -> String
    fn byte_length() -> Int
    fn to_bytes() -> Bytes
    fn parse_int() -> Optional[Int]

interface IntOperations:
    fn to_string(radix: Int) -> String
    fn to_float() -> Float
    fn to_decimal() -> Decimal

interface FloatOperations:
    fn to_precision(precision: Int) -> Result[String, NumberError]
    fn to_exponential(digits: Int) -> Result[String, NumberError]
    fn to_fixed(digits: Int) -> Result[String, NumberError]
    fn to_string() -> String
    fn is_nan() -> Bool
    fn is_finite() -> Bool
    fn truncate_to_int() -> Optional[Int]
