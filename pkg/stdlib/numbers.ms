# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Result from "@std/result.ms"

export type NumberError:
    case InvalidInput
    case InvalidData
    case OutOfRange

export fn parse_float(text: String) -> Result[Float, NumberError]

export fn parse_int(text: String, radix: Int) -> Result[Int, NumberError]

impl Error for NumberError:
    fn message() -> String
