# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"

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
    # Replaces every nonoverlapping match with literal replacement text (no capture expansion).
    # max_bytes optionally bounds UTF-8 output; negatives return InvalidInput, exhaustion LimitExceeded.
    fn replace_all(
        text: String,
        replacement: String,
        max_bytes: Optional[Int64] = none
    ) -> Result[String, RegexError]:
    # Compatibility spelling for replace_all; replaces every match, with identical limits and errors.
    fn replace(
        text: String,
        replacement: String,
        max_bytes: Optional[Int64] = none
    ) -> Result[String, RegexError]:

# Compiles a regular expression. Invalid pattern syntax is returned as an error.
export fn compile(pattern: String) -> Result[Regex, RegexError]:

impl Error for RegexError:
    fn message() -> String:
