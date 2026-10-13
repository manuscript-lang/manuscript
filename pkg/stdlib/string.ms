# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"

# Errors returned by Unicode scalar conversions and bounded string operations.
export type StringError:
    case InvalidInput
    case OutOfRange
    case LimitExceeded
    case Failed(message: String)

# Builds text from Unicode scalar values. Invalid scalars return `InvalidInput`.
export fn from_scalars(values: List[Int]) -> Result[String, StringError]:

impl Error for StringError:
    fn message() -> String:

# Mutable builder for constructing a string without repeated intermediate copies.
# Mutable builder for constructing a string without repeated intermediate copies.
export type StringBuilder:
    fn append(value: String) -> Unit:
    fn freeze() -> String:
