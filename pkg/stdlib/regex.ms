# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

# Errors returned for invalid patterns or configured result limits.
export type RegexError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

# A compiled regular expression that can be reused across input strings.
export type Regex:
    fn matches(text: String) -> Bool:
    fn find_all(
        text: String,
        max_matches: Optional[Int] = none
    ) -> Result[List[String], RegexError]:
    fn replace(
        text: String,
        replacement: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, RegexError]:

# Compiles a regular expression. Invalid pattern syntax is returned as an error.
export fn compile(pattern: String) -> Result[Regex, RegexError]:

impl Error for RegexError:
    fn message() -> String:
