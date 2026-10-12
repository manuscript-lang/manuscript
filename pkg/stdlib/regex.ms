# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type RegexError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

export type Regex:
    fn matches(text: String) -> Bool
    fn find_all(text: String, max_matches: Optional[Int] = none) -> Result[List[String], RegexError]
    fn replace(text: String, replacement: String, max_bytes: Optional[Int] = none) -> Result[String, RegexError]

export fn compile(pattern: String) -> Result[Regex, RegexError]

impl Error for RegexError:
    fn message() -> String
