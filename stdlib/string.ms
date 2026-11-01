import msrt_string_from_scalars, msstd_regex_compile from "@std/internal/string.ms"
import (
    msstd_unicode_fields,
    msstd_unicode_is_alphanumeric
) from "@std/internal/unicode.ms"
import (
    msstd_regex_find_all_spans,
    msstd_regex_capture_spans,
    msstd_regex_capture_all_spans
) from "@std/internal/string.ms"

interface StringAffixCuts:
    fn cut_prefix(prefix: String) String?
    fn cut_suffix(suffix: String) String?

impl StringAffixCuts for String:
    # Removes one exact prefix, or returns none when absent; an empty prefix succeeds unchanged.
    fn cut_prefix(prefix: String) String?:
        if self.starts_with(prefix):
            return self.drop(prefix.length())

        return none

    # Removes one exact suffix, or returns none when absent; an empty suffix succeeds unchanged.
    fn cut_suffix(suffix: String) String?:
        if self.ends_with(suffix):
            return self.take(self.length() - suffix.length())

        return none

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
    fn normalize(text: String, max_bytes: Int?) String!StringError: ...

# Builds text from Unicode scalar values. Invalid scalars return `InvalidInput`.
export fn from_scalars(values: List[Int]) String!StringError:
    return msrt_string_from_scalars(values)

impl Error for StringError:
    # Returns original Failed text, or a string-prefixed diagnostic for other cases.
    fn message() String: ...

# Mutable builder for constructing a string without repeated intermediate copies.
export extern type StringBuilder

impl StringBuilder:
    # Appends the supplied text in order.
    var fn append(value: String) Unit: ...

    # Consumes the builder and returns its text; the builder cannot be used afterwards.
    fn build() String: ...

    # Returns the text appended so far and leaves the builder empty, for a builder held in a field.
    var fn drain() String: ...

# Errors returned for invalid patterns or configured result limits.
export type RegexError:
    # A supplied match-count, capture-slot or output-byte budget is negative.
    case InvalidInput
    # Pattern syntax is invalid for the native regular-expression engine (Rust `regex` syntax).
    case InvalidData
    # A match-count, capture-slot or replacement output-byte budget is exceeded.
    case LimitExceeded

# A compiled regular expression that can be reused across input strings.
export extern type Regex

# A match or capture range in UTF-8 bytes, with an exclusive end; no normalization is applied.
# Example: a match of `é` in `aé` spans bytes 1 through 3, not scalar positions 1 through 2.
# Extract text with `data.decode_utf8_range(span.start, span.end)` on its original Bytes.
export type RegexSpan:
    # Zero-based inclusive UTF-8 byte offset in the input string.
    start: Int
    # Exclusive UTF-8 byte offset; equal to start for a participating empty match.
    end: Int

impl Regex:
    # Tests whether any match occurs; anchor the pattern explicitly to require a whole-string match.
    fn matches(text: String) Bool: ...

    # Returns nonoverlapping full-match text in occurrence order, excluding capture groups.
    # A supplied cap is a strict budget, not truncation; zero-width matches follow the engine's rules.
    fn find_all(text: String, max_matches: Int?) List[String]!RegexError: ...

    # Replaces every nonoverlapping match with literal replacement text; $ and capture names are not expanded.
    # max_bytes optionally bounds UTF-8 output; negatives return InvalidInput, exhaustion LimitExceeded.
    fn replace_all(text: String, replacement: String, max_bytes: Int?) String!RegexError: ...

    # Returns the first match as [whole, group1, ...]; groups that did not participate are "". Empty list when nothing matches.
    fn captures(text: String) List[String]: ...

    # Like captures for every nonoverlapping match, under find_all's match-count budget.
    fn captures_all(text: String, max_matches: Int?) List[List[String]]!RegexError: ...

    # Returns the first match's named groups that participated; empty map when nothing matches.
    fn named_captures(text: String) Map[String, String]: ...

    # Returns [start, end] UTF-8 byte offsets of the first match, or none when nothing matches.
    fn find_span(text: String) List[Int]?: ...

    # Splits text around every match, always returning at least one piece. max_pieces is a strict budget like find_all's.
    fn split(text: String, max_pieces: Int?) List[String]!RegexError: ...

    # Like replace_all but expands $1, ${name}, and $$ in template from each match (Rust regex syntax: use ${1}x, not $1x).
    fn replace_template(
        text: String,
        template: String,
        max_bytes: Int?
    ) String!RegexError: ...

# Compiles a regular expression. Invalid pattern syntax is returned as an error.
export fn compile(pattern: String) Regex!RegexError:
    return msstd_regex_compile(pattern)

impl Error for RegexError:
    # Returns a regular-expression-prefixed diagnostic without echoing pattern or input text.
    fn message() String: ...

impl String:
    # Splits on Unicode White_Space, omitting empty fields; empty or all-whitespace text gives an empty list.
    # Exact field text is preserved without normalization; the byte-order mark and zero-width space are not separators.
    fn fields() List[String]:
        return msstd_unicode_fields(self)

interface StringTextOperations:
    fn fields_by(is_separator: fn(String) Bool) List[String]
    fn equal_fold(other: String) Bool
    fn count(part: String) Int
    fn trim_chars(set: String) String
    fn trim_start_chars(set: String) String
    fn trim_end_chars(set: String) String
    fn contains_any(set: String) Bool
    fn index_any(set: String) Int?
    fn split_after(separator: String) List[String]
    fn capitalize() String
    fn title() String
    fn map_chars(transform: fn(String) String) String
    fn find_char(predicate: fn(String) Bool) Int?
    fn replace_each(pairs: Map[String, String]) String

impl StringTextOperations for String:
    # Splits around runs of characters (one-scalar strings) the predicate accepts; no empty items.
    fn fields_by(is_separator: fn(String) Bool) List[String]:
        var out = List[String]()
        var current = StringBuilder()
        var open = false

        for c in self.chars():
            if is_separator(c):
                if open:
                    out.append(current.drain())
                    open = false
            else:
                current.append(c)
                open = true

        if open:
            out.append(current.drain())
        return out

    # Compares text ignoring case using Unicode full case mapping (no locale), so "Straße" equals "STRASSE".
    fn equal_fold(other: String) Bool:
        return self.upper().lower() == other.upper().lower()

    # Counts non-overlapping occurrences; an empty part counts the scalars plus one.
    fn count(part: String) Int:
        if part.is_empty():
            return self.length() + 1

        return self.split(part, none).length() - 1

    # Removes every leading and trailing scalar that occurs in set.
    fn trim_chars(set: String) String:
        return self.trim_start_chars(set).trim_end_chars(set)

    # Removes every leading scalar that occurs in set.
    fn trim_start_chars(set: String) String:
        let cs = self.chars()
        var i = 0
        while i < cs.length() and set.contains(cs[i]):
            i += 1
        return self.drop(i)

    # Removes every trailing scalar that occurs in set.
    fn trim_end_chars(set: String) String:
        let cs = self.chars()
        var n = cs.length()
        while n > 0 and set.contains(cs[n - 1]):
            n -= 1
        return self.take(n)

    # Reports whether any scalar of set occurs in the text.
    fn contains_any(set: String) Bool:
        return self.index_any(set).is_some()

    # Scalar index of the first scalar that occurs in set, or none.
    fn index_any(set: String) Int?:
        return self.find_char(fn c: set.contains(c))

    # Splits after each separator, keeping it at the end of each piece; an empty separator splits into scalars.
    fn split_after(separator: String) List[String]:
        if separator.is_empty():
            return self.chars()

        var out = List[String]()
        let parts = self.split(separator, none)

        for i in 0..parts.length():
            if i + 1 < parts.length():
                out.append(parts[i].concat(separator))
            else if not parts[i].is_empty():
                out.append(parts[i].clone())

        return out

    # Uppercases the first scalar and leaves the rest unchanged.
    fn capitalize() String:
        return self.take(1).upper().concat(self.drop(1))

    # Capitalizes the first letter of each run of letters, digits and apostrophes and lowercases the others.
    fn title() String:
        var out = StringBuilder()
        var in_word = false

        for c in self.chars():
            let word = is_word_scalar(c)

            if word and in_word:
                out.append(c.lower())
            else if word:
                out.append(c.upper())
            else:
                out.append(c)

            in_word = word

        return out.build()

    # Replaces each scalar with the transform's result; an empty result deletes it.
    fn map_chars(transform: fn(String) String) String:
        var out = StringBuilder()
        for c in self.chars():
            out.append(transform(c))
        return out.build()

    # Scalar index of the first scalar the predicate accepts, or none.
    fn find_char(predicate: fn(String) Bool) Int?:
        let cs = self.chars()
        for i in 0..cs.length():
            if predicate(cs[i]):
                return i
        return none

    # Replaces many patterns in one pass. At each position the first pair, in map order, whose key matches
    # wins and its replacement is not rescanned; empty keys are ignored.
    fn replace_each(pairs: Map[String, String]) String:
        var out = StringBuilder()
        let olds = pairs.keys()
        let news = pairs.values()
        let n = self.length()
        var i = 0

        while i < n:
            var hit = false

            for j in 0..olds.length():
                let key = olds[j]

                if not key.is_empty() and self.drop(i).starts_with(key):
                    out.append(news[j])
                    i += key.length()
                    hit = true
                    break

            if not hit:
                out.append(self.slice(i, i + 1).get(""))
                i += 1

        return out.build()

fn is_word_scalar(c: String) Bool:
    return msstd_unicode_is_alphanumeric(c.scalar_at(0, -1)) or c == "'"

fn capture_slots(raw: List[Int], start: Int, count: Int) List[RegexSpan?]:
    var out = List[RegexSpan?](reserve: count)

    for index in 0..count:
        let at = start + index * 2

        if raw[at] < 0:
            out.append(none)
        else:
            out.append(RegexSpan(raw[at], raw[at + 1]))

    return out

interface RegexSpanQueries:
    fn find_all_spans(text: String, max_matches: Int?) List[RegexSpan]!RegexError
    fn capture_spans(text: String, max_captures: Int?) List[RegexSpan?]?!RegexError
    fn capture_all_spans(
        text: String,
        max_matches: Int?,
        max_captures: Int?
    ) List[List[RegexSpan?]]!RegexError

impl RegexSpanQueries for Regex:
    # Returns all full-match byte ranges in find_all order, without copying matched text.
    # max_matches is a strict output budget: negatives return InvalidInput, excess returns LimitExceeded.
    fn find_all_spans(text: String, max_matches: Int?) List[RegexSpan]!RegexError:
        let raw = try msstd_regex_find_all_spans(self, text, max_matches)
        var out = List[RegexSpan](reserve: raw.length() / 2)
        for index in 0..(raw.length() / 2):
            out.append(RegexSpan(raw[index * 2], raw[index * 2 + 1]))
        return ok(out)

    # Returns the first match's [whole, group1, ...] byte ranges, or outer none when no match exists.
    # An unmatched group is inner none; a participating empty group has start == end.
    # max_captures bounds slots including the whole match and unmatched groups. Negative budgets return InvalidInput;
    # excess returns LimitExceeded. The budget bounds output, not input scanning or engine scratch space.
    fn capture_spans(text: String, max_captures: Int?) List[RegexSpan?]?!RegexError:
        let raw = try msstd_regex_capture_spans(self, text, max_captures)
        if raw.is_empty(): return ok(none)

        return ok(capture_slots(raw, 1, raw[0]))

    # Like capture_spans for every match in captures_all order; no match gives an empty list.
    # max_matches bounds rows; max_captures bounds total slots across rows, including whole and unmatched groups.
    # Negative budgets return InvalidInput, excess returns LimitExceeded; these are output budgets, not search limits.
    fn capture_all_spans(
        text: String,
        max_matches: Int?,
        max_captures: Int?
    ) List[List[RegexSpan?]]!RegexError:
        let raw = try msstd_regex_capture_all_spans(
            self, text, max_matches, max_captures
        )
        if raw.is_empty(): return ok(List[List[RegexSpan?]]())

        let count = raw[0]
        var out = List[List[RegexSpan?]](reserve: (raw.length() - 1) / (count * 2))
        var at = 1

        while at < raw.length():
            out.append(capture_slots(raw, at, count))
            at = at + count * 2

        return ok(out)
