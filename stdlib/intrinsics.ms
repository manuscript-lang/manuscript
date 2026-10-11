# Source locations for the fixed intrinsic receiver operations.
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import Optional from "@std/optional.ms"

type StringOperations:
    fn byte_length() -> Int
    fn to_bytes() -> Bytes
    fn parse_int() -> Optional[Int]

type IntOperations:
    fn to_float() -> Float
    fn to_decimal() -> Decimal

type FloatOperations:
    fn truncate_to_int() -> Optional[Int]
