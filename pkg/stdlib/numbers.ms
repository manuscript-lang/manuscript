# Canonical standard-library declarations. Implementations are native.


# Errors returned when numeric text is malformed or outside the target range.
export type NumberError:
    case InvalidInput
    case InvalidData
    case OutOfRange

# Parses a decimal floating-point number using Manuscript's numeric syntax.
export fn parse_float(text: String) -> Result[Float, NumberError]:

# Parses an integer in a radix from 2 through 36.
export fn parse_int(text: String, radix: Int) -> Result[Int, NumberError]:

impl Error for NumberError:
    fn message() -> String:
