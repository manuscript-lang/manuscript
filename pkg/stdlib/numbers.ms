# Canonical standard-library declarations. Implementations are native.

# Errors returned for invalid numeric requests, malformed text, or out-of-range values.
export type NumberError:
    # A radix or digit-count argument is outside its documented range.
    case InvalidInput
    # The text does not match the numeric syntax, such as an empty string, stray characters, or digits invalid for the radix.
    case InvalidData
    # The text is well formed but the value does not fit, such as an integer beyond the platform's Int range or a float beyond the finite range.
    case OutOfRange

# Parses a decimal floating-point number using Manuscript's numeric syntax.
export fn parse_float(text: String) -> Result[Float, NumberError]:

# Parses an integer in a radix from 2 through 36.
export fn parse_int(text: String, radix: Int) -> Result[Int, NumberError]:

impl Error for NumberError:
    # Returns the fixed diagnostic `number: <reason>`, such as `number: invalid data`, without echoing the input text.
    fn message() -> String:
