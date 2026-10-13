# Canonical standard-library declarations. Implementations are native.

# Errors returned for invalid numeric requests, malformed text, or out-of-range values.
export type NumberError:
    case InvalidInput
    case InvalidData
    case OutOfRange

# Parses a decimal floating-point number using Manuscript's numeric syntax.
export fn parse_float(text: String) -> Result[Float, NumberError]:

# Parses an integer in a radix from 2 through 36.
export fn parse_int(text: String, radix: Int) -> Result[Int, NumberError]:

# Parses a signed 64-bit integer without first passing through the default Int.
export fn parse_int64(text: String, radix: Int) -> Result[Int64, NumberError]:

# Parses an IEEE binary64 value without first rounding to the default Float.
export fn parse_float64(text: String) -> Result[Float64, NumberError]:

impl Error for NumberError:
    fn message() -> String:
