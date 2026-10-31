# Errors returned by Unicode scalar conversions and bounded string operations.
export type StringError:
    # Scalar values, normalization form or a supplied repeat/padding/output budget is invalid.
    case InvalidInput
    # A strict scalar slice bound lies outside the string or its range is inverted.
    case OutOfRange
    # UTF-8 output exceeds a supplied byte budget or the native string allocation limit.
    case LimitExceeded
    # A string-domain failure with an explicit diagnostic supplied by an implementation.
    case Failed(
        # Original diagnostic text, returned unchanged by message().
        message: String
    )

# The four Unicode normalization forms, selected without runtime string spelling errors.
export type NormalizationForm:
    # Canonical decomposition followed by canonical recomposition where Unicode permits it.
    case Nfc
    # Canonical decomposition with combining marks placed in canonical order.
    case Nfd
    # Compatibility decomposition followed by canonical recomposition where Unicode permits it.
    case Nfkc
    # Compatibility decomposition with combining marks placed in canonical order.
    case Nfkd

impl NormalizationForm:
    # Normalizes text with the existing String.normalize budgets and StringError cases.
    # Omission or none adds no output budget; a supplied budget counts UTF-8 bytes.
    fn normalize(text: String, max_bytes: Int?) Result[String, StringError]: ...

# Builds text from Unicode scalar values. Invalid scalars return `InvalidInput`.
export fn from_scalars(values: List[Int]) Result[String, StringError]: ...

impl Error for StringError:
    # Returns original Failed text, or a string-prefixed diagnostic for other cases.
    fn message() String: ...

# Mutable builder for constructing a string without repeated intermediate copies.
export type StringBuilder: ...

impl StringBuilder:
    # Appends the supplied text in order.
    var fn append(value: String) Unit: ...

    # Consumes the builder and returns its text; the builder cannot be used afterwards.
    fn build() String: ...

    # Returns the text appended so far and leaves the builder empty, for a builder held in a field.
    var fn drain() String: ...

# Errors returned for invalid patterns or configured result limits.
export type RegexError:
    # A supplied match-count or output-byte budget is negative.
    case InvalidInput
    # Pattern syntax is invalid for the native RE2-compatible regular-expression engine.
    case InvalidData
    # More matches exist than permitted, or replacement output exceeds its byte budget.
    case LimitExceeded

# A compiled regular expression that can be reused across input strings.
export type Regex: ...

impl Regex:
    # Tests whether any match occurs; anchor the pattern explicitly to require a whole-string match.
    fn matches(text: String) Bool: ...

    # Returns nonoverlapping full-match text in occurrence order, excluding capture groups.
    # A supplied cap is a strict budget, not truncation; zero-width matches follow native regexp rules.
    fn find_all(text: String, max_matches: Int?) Result[List[String], RegexError]: ...

    # Replaces every nonoverlapping match with literal replacement text; $ and capture names are not expanded.
    # max_bytes optionally bounds UTF-8 output; negatives return InvalidInput, exhaustion LimitExceeded.
    fn replace_all(
        text: String,
        replacement: String,
        max_bytes: Int?
    ) Result[String, RegexError]: ...

    # Returns the first match as [whole, group1, ...]; groups that did not participate are "". Empty list when nothing matches.
    fn captures(text: String) List[String]: ...

    # Like captures for every nonoverlapping match, under find_all's match-count budget.
    fn captures_all(
        text: String,
        max_matches: Int?
    ) Result[List[List[String]], RegexError]: ...

    # Returns the first match's named groups that participated; empty map when nothing matches.
    fn named_captures(text: String) Map[String, String]: ...

    # Returns [start, end] UTF-8 byte offsets of the first match, or none when nothing matches.
    fn find_span(text: String) List[Int]?: ...

    # Splits text around every match, always returning at least one piece. max_pieces is a strict budget like find_all's.
    fn split(text: String, max_pieces: Int?) Result[List[String], RegexError]: ...

    # Like replace_all but expands $1, ${name}, and $$ in template from each match (Rust regex syntax: use ${1}x, not $1x).
    fn replace_template(
        text: String,
        template: String,
        max_bytes: Int?
    ) Result[String, RegexError]: ...

# Compiles a regular expression. Invalid pattern syntax is returned as an error.
export fn compile(pattern: String) Result[Regex, RegexError]: ...

impl Error for RegexError:
    # Returns a regular-expression-prefixed diagnostic without echoing pattern or input text.
    fn message() String: ...
