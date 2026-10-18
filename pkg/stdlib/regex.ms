# Errors returned for invalid patterns or configured result limits.
export type RegexError:
    # A supplied match-count or output-byte budget is negative.
    case InvalidInput
    # Pattern syntax is invalid for the native RE2-compatible regular-expression engine.
    case InvalidData
    # More matches exist than permitted, or replacement output exceeds its byte budget.
    case LimitExceeded

# A compiled regular expression that can be reused across input strings.
export type Regex:

impl Regex:
    # Tests whether any match occurs; anchor the pattern explicitly to require a whole-string match.
    fn matches(text: String) Bool:

    # Returns nonoverlapping full-match text in occurrence order, excluding capture groups.
    # A supplied cap is a strict budget, not truncation; zero-width matches follow native regexp rules.
    fn find_all(
        text: String,
        max_matches: Optional[Int] = none
    ) Result[List[String], RegexError]:

    # Replaces every nonoverlapping match with literal replacement text; $ and capture names are not expanded.
    # max_bytes optionally bounds UTF-8 output; negatives return InvalidInput, exhaustion LimitExceeded.
    fn replace_all(
        text: String,
        replacement: String,
        max_bytes: Optional[Int] = none
    ) Result[String, RegexError]:

# Compiles a regular expression. Invalid pattern syntax is returned as an error.
export fn compile(pattern: String) Result[Regex, RegexError]:

impl Error for RegexError:
    # Returns a regular-expression-prefixed diagnostic without echoing pattern or input text.
    fn message() String:
