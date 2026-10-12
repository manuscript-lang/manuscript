# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Optional from "@std/optional.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type StringError:
    case InvalidInput
    case OutOfRange
    case LimitExceeded
    case Failed(message: String)

export fn from_scalars(values: List[Int]) -> Result[String, StringError]:

impl Error for StringError:
    fn message() -> String:

export type StringBuilder:
    fn append(value: String) -> Unit:
    fn freeze() -> String:
