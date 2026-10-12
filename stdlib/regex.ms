# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type RegexError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

export type Regex:
    fn matches(text: String) -> Bool
    fn find_all(text: String, max_matches: Int) -> Result[List[String], RegexError]
    fn replace(text: String, replacement: String, max_bytes: Int) -> Result[String, RegexError]

export fn compile(pattern: String) -> Result[Regex, RegexError]

export fn find_all(pattern: Regex, text: String, max_matches: Int) -> Result[List[String], RegexError]

export fn matches(pattern: Regex, text: String) -> Bool

export fn replace(pattern: Regex, text: String, replacement: String, max_bytes: Int) -> Result[String, RegexError]

impl Error for RegexError:
    fn message() -> String
