# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type PathError:
    case InvalidInput

export fn basename(path: String) -> String

export fn dirname(path: String) -> String

export fn extension(path: String) -> String

export fn is_absolute(path: String) -> Bool

export fn join(parts: List[String]) -> String

export fn normalize(path: String) -> String

export fn relative(base: String, target: String) -> Result[String, PathError]

impl Error for PathError:
    fn message() -> String
