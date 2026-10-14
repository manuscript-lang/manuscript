# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"

# Errors returned for invalid patterns or configured result limits.
export type RegexError:
    # A supplied match-count or output-byte budget is negative.
    case InvalidInput
    # Pattern syntax is invalid for the native RE2-compatible regular-expression engine.
    case InvalidData
    # More matches exist than permitted, or replacement output exceeds its byte budget.
    case LimitExceeded

# The first full match, with half-open Unicode scalar positions in the input.
export type RegexMatch:
    # Full matched text; an empty match contains empty text.
    text: String
    # Zero-based Unicode scalar position where the full match begins.
    start: Int
    # Unicode scalar position immediately after the full match.
    end: Int
    # Capture groups only, in pattern order; unmatched groups are none, empty matches some("").
    groups: List[Optional[String]]

# A compiled regular expression that can be reused across input strings.
export type Regex:
    # Tests whether any match occurs; anchor the pattern explicitly to require a whole-string match.
    fn matches(text: String) -> Bool:
    # Returns the first full match, its scalar positions and optional capture groups, or none.
    fn find(text: String) -> Optional[RegexMatch]:
    # Splits at nonoverlapping full matches; capture groups are not returned.
    # Omitted/none max_parts is unlimited, zero returns no parts, negatives return InvalidInput.
    # A cap truncates parts rather than retaining the unsplit remainder; zero-width matches follow native regexp rules.
    fn split(
        text: String,
        max_parts: Optional[Int] = none
    ) -> Result[List[String], RegexError]:
    # Returns nonoverlapping full-match text in occurrence order, excluding capture groups.
    # A supplied cap is a strict budget, not truncation; zero-width matches follow native regexp rules.
    fn find_all(
        text: String,
        max_matches: Optional[Int] = none
    ) -> Result[List[String], RegexError]:
    # Replaces every nonoverlapping match with literal replacement text; $ and capture names are not expanded.
    # max_bytes optionally bounds UTF-8 output; negatives return InvalidInput, exhaustion LimitExceeded.
    fn replace_all(
        text: String,
        replacement: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, RegexError]:
    # Compatibility spelling for replace_all; replaces every match, with identical limits and errors.
    fn replace(
        text: String,
        replacement: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, RegexError]:

# Compiles a regular expression. Invalid pattern syntax is returned as an error.
export fn compile(pattern: String) -> Result[Regex, RegexError]:

impl Error for RegexError:
    # Returns a regular-expression-prefixed diagnostic without echoing pattern or input text.
    fn message() -> String:
