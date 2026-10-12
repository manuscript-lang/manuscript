# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Result from "@std/result.ms"

export type NumberError:
    case InvalidInput
    case InvalidData
    case OutOfRange

export fn format_float(value: Float) -> String

export fn format_int(value: Int, radix: Int) -> String

export fn parse_float(text: String) -> Result[Float, NumberError]

export fn parse_int(text: String, radix: Int) -> Result[Int, NumberError]

export fn format_fixed(value: Float, digits: Int) -> Result[String, NumberError]

export fn format_exponential(value: Float, digits: Int) -> Result[String, NumberError]

export fn format_precision(value: Float, precision: Int) -> Result[String, NumberError]

impl Error for NumberError:
    fn message() -> String
