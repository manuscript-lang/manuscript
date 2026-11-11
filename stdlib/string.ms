import (
	Bytes from "@std/bytes.ms",
	Writable from "@std/core.ms",

	msrt_string_from_scalars,
	msstd_regex_capture_all_spans,
	msstd_regex_capture_spans,
	msstd_regex_compile,
	msstd_regex_find_all_spans from "@std/internal/string.ms",
	msstd_unicode_display_width,
	msstd_unicode_fields,
	msstd_unicode_is_alphanumeric from "@std/internal/unicode.ms",
)

impl Writable for String:
	// The UTF-8 encoding of the text.
	fn as_bytes() Bytes:
		return self.to_bytes()

interface StringAffixCuts:
	fn cut_prefix(prefix: String) String?
	fn cut_suffix(suffix: String) String?

impl StringAffixCuts for String:
	// Removes one exact prefix, or returns none when absent; an empty prefix succeeds unchanged.
	fn cut_prefix(prefix: String) String?:
		if self.starts_with(prefix): return self.drop(prefix.length())
		return none

	// Removes one exact suffix, or returns none when absent; an empty suffix succeeds unchanged.
	fn cut_suffix(suffix: String) String?:
		if self.ends_with(suffix): return self.take(self.length() - suffix.length())
		return none

// The four Unicode normalization forms, selected without runtime string spelling errors.
export enum NormalizationForm:
	// Canonical decomposition followed by canonical recomposition where Unicode permits it.
	Nfc
	// Canonical decomposition with combining marks placed in canonical order.
	Nfd
	// Compatibility decomposition followed by canonical recomposition where Unicode permits it.
	Nfkc
	// Compatibility decomposition with combining marks placed in canonical order.
	Nfkd

impl NormalizationForm:
	// Normalizes text with the existing String.normalize budgets and error kinds.
	// Omission or none adds no output budget; a supplied budget counts UTF-8 bytes.
	fn normalize(text: String, max_bytes: Int?) String!: ...

// Builds text from Unicode scalar values. Invalid scalars return `EINVAL`.
export fn from_scalars(values: List[Int]) String!:
	return msrt_string_from_scalars(values)

// Mutable builder for constructing a string without repeated intermediate copies.
export extern type StringBuilder

impl StringBuilder:
	// Appends the supplied text in order.
	var fn append(value: String) Unit: ...

	// Consumes the builder and returns its text; the builder cannot be used afterwards.
	fn build() String: ...

	// Returns the text appended so far and leaves the builder empty, for a builder held in a field.
	var fn drain() String: ...

// A compiled regular expression that can be reused across input strings.
export extern type Regex

/*
A match or capture range in UTF-8 bytes, with an exclusive end; no normalization is applied.
Example: a match of `é` in `aé` spans bytes 1 through 3, not scalar positions 1 through 2.
Extract text with `data.decode_utf8_range(span.start, span.end)` on its original Bytes.
*/
export type RegexSpan:
	// Zero-based inclusive UTF-8 byte offset in the input string.
	start: Int
	// Exclusive UTF-8 byte offset; equal to start for a participating empty match.
	end: Int

impl Regex:
	// Tests whether any match occurs; anchor the pattern explicitly to require a whole-string match.
	fn matches(text: String) Bool: ...

	// Returns nonoverlapping full-match text in occurrence order, excluding capture groups.
	// A supplied cap is a strict budget, not truncation; zero-width matches follow the engine's rules.
	fn find_all(text: String, max_matches: Int?) List[String]!: ...

	// Replaces every nonoverlapping match with literal replacement text; $ and capture names are not expanded.
	// max_bytes optionally bounds UTF-8 output; negatives return EINVAL, exhaustion EOVERFLOW.
	fn replace_all(text: String, replacement: String, max_bytes: Int?) String!: ...

	// Returns the first match as [whole, group1, ...]; groups that did not participate are "". Empty list when nothing matches.
	fn captures(text: String) List[String]: ...

	// Like captures for every nonoverlapping match, under find_all's match-count budget.
	fn captures_all(text: String, max_matches: Int?) List[List[String]]!: ...

	// Returns the first match's named groups that participated; empty map when nothing matches.
	fn named_captures(text: String) Map[String, String]: ...

	// Returns [start, end] UTF-8 byte offsets of the first match, or none when nothing matches.
	fn find_span(text: String) List[Int]?: ...

	// Splits text around every match, always returning at least one piece. max_pieces is a strict budget like find_all's.
	fn split(text: String, max_pieces: Int?) List[String]!: ...

	// Like replace_all but expands $1, ${name}, and $$ in template from each match (Rust regex syntax: use ${1}x, not $1x).
	fn replace_template(text: String, template: String, max_bytes: Int?) String!: ...

// Compiles a regular expression. Invalid pattern syntax is returned as an error.
export fn compile(pattern: String) Regex!:
	return msstd_regex_compile(pattern)

impl String:
	// Splits on Unicode White_Space, omitting empty fields; empty or all-whitespace text gives an empty list.
	// Exact field text is preserved without normalization; the byte-order mark and zero-width space are not separators.
	fn fields() List[String]:
		return msstd_unicode_fields(self)

	// Terminal columns the text occupies, measured by Unicode sequence width with ambiguous characters narrow:
	// combining marks add nothing, wide characters and supported emoji sequences count two.
	// An estimate, not a promise for every font or terminal. Controls (tabs, CR/LF, ESC, C1), U+2028 and U+2029 return EBADMSG.
	fn display_width() Int!:
		return msstd_unicode_display_width(self)

interface StringTextOperations:
	fn fields_by(is_separator: fn(String) Bool) List[String]
	fn equal_fold(other: String) Bool
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

// Scalars read per step by the prefix scans below; each step doubles, so a scan costs its distance.
SCAN_WINDOW := 32

impl StringTextOperations for String:
	// Splits around runs of characters (one-scalar strings) the predicate accepts; no empty items.
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

	// Compares text ignoring case: both sides are uppercased and then lowercased with Unicode full case mapping
	// (no locale, no normalization), so "Straße" equals "STRASSE". This is not Unicode default case folding:
	// the dotless "ı" (U+0131) uppercases to "I" and so compares equal to "i" and "I".
	fn equal_fold(other: String) Bool:
		return self.upper().lower() == other.upper().lower()

	// Removes every leading and trailing scalar that occurs in set.
	fn trim_chars(set: String) String:
		return self.trim_start_chars(set).trim_end_chars(set)

	// Removes every leading scalar that occurs in set.
	fn trim_start_chars(set: String) String:
		var skipped = 0
		var window = SCAN_WINDOW

		while true:
			// Scalars are read in doubling windows, so the cost follows the trimmed run, not the text length.
			cs := self.take(skipped + window).drop(skipped).chars()
			var i = 0
			while i < cs.length() and set.contains(cs[i]):
				i += 1
			skipped += i
			if i < cs.length() or cs.length() < window: break

			window *= 2

		return self.drop(skipped)

	// Removes every trailing scalar that occurs in set.
	fn trim_end_chars(set: String) String:
		var kept = self.length()
		var window = SCAN_WINDOW

		while kept > 0:
			var low = kept - window
			if low < 0:
				low = 0

			cs := self.slice(low, kept).get("").chars()
			var i = cs.length()
			while i > 0 and set.contains(cs[i - 1]):
				i -= 1
			kept = low + i
			if i > 0: break

			window *= 2

		return self.take(kept)

	// Reports whether any scalar of set occurs in the text.
	fn contains_any(set: String) Bool:
		return self.index_any(set).is_some()

	// Scalar index of the first scalar that occurs in set, or none.
	fn index_any(set: String) Int?:
		return self.find_char(fn c: set.contains(c))

	// Splits after each separator, keeping it at the end of each piece; an empty separator splits into scalars.
	fn split_after(separator: String) List[String]:
		if separator.is_empty(): return self.chars()

		var out = List[String]()
		parts := self.split(separator)

		for i in 0..parts.length():
			if i + 1 < parts.length():
				out.append(parts[i].concat(separator))
			else if not parts[i].is_empty():
				out.append(parts[i].clone())

		return out

	// Uppercases the first scalar and leaves the rest unchanged.
	fn capitalize() String:
		return self.take(1).upper().concat(self.drop(1))

	// Capitalizes the first letter of each run of letters, digits and apostrophes and lowercases the others.
	fn title() String:
		var out = StringBuilder()
		var in_word = false

		for c in self.chars():
			word := is_word_scalar(c)

			if word and in_word:
				out.append(c.lower())
			else if word:
				out.append(c.upper())
			else:
				out.append(c)

			in_word = word

		return out.build()

	// Replaces each scalar with the transform's result; an empty result deletes it.
	fn map_chars(transform: fn(String) String) String:
		var out = StringBuilder()
		for c in self.chars():
			out.append(transform(c))
		return out.build()

	// Scalar index of the first scalar the predicate accepts, or none.
	fn find_char(predicate: fn(String) Bool) Int?:
		var from = 0
		var window = SCAN_WINDOW

		while true:
			cs := self.take(from + window).drop(from).chars()
			for i in 0..cs.length():
				if predicate(cs[i]): return from + i
			if cs.length() < window: return none

			from += window
			window *= 2

		return none

	// Replaces many patterns in one pass. At each position the first pair, in map order, whose key matches
	// wins and its replacement is not rescanned; empty keys are ignored.
	fn replace_each(pairs: Map[String, String]) String:
		if pairs.is_empty(): return self.clone()

		var out = StringBuilder()
		news := pairs.values()
		var needles = List[List[String]]()
		for key in pairs.keys():
			needles.append(key.chars())

		cs := self.chars()
		n := cs.length()
		var i = 0

		while i < n:
			var hit = -1

			for j in 0..needles.length():
				if chars_start_at(cs, i, needles[j]):
					hit = j
					break

			if hit < 0:
				out.append(cs[i])
				i += 1
				continue

			out.append(news[hit])
			i += needles[hit].length()

		return out.build()

// Tests whether the non-empty scalar list `needle` occurs in `cs` at index `at`.
fn chars_start_at(cs: List[String], at: Int, needle: List[String]) Bool:
	if needle.is_empty() or at + needle.length() > cs.length(): return false

	for t in 0..needle.length():
		if cs[at + t] != needle[t]: return false
	return true

fn is_word_scalar(c: String) Bool:
	return msstd_unicode_is_alphanumeric(c.scalar_at(0, -1)) or c == "'"

fn capture_slots(raw: List[Int], start: Int, count: Int) List[RegexSpan?]:
	var out = List[RegexSpan?](reserve: count)

	for index in 0..count:
		at := start + index * 2

		if raw[at] < 0:
			out.append(none)
		else:
			out.append(RegexSpan(raw[at], raw[at + 1]))

	return out

interface RegexSpanQueries:
	fn find_all_spans(text: String, max_matches: Int?) List[RegexSpan]!
	fn capture_spans(text: String, max_captures: Int?) List[RegexSpan?]?!
	fn capture_all_spans(
		text: String,
		max_matches: Int?,
		max_captures: Int?
	) List[List[RegexSpan?]]!

impl RegexSpanQueries for Regex:
	// Returns all full-match byte ranges in find_all order, without copying matched text.
	// max_matches is a strict output budget: negatives return EINVAL, excess returns EOVERFLOW.
	fn find_all_spans(text: String, max_matches: Int?) List[RegexSpan]!:
		raw := try msstd_regex_find_all_spans(self, text, max_matches)
		var out = List[RegexSpan](reserve: raw.length() / 2)
		for index in 0..(raw.length() / 2):
			out.append(RegexSpan(raw[index * 2], raw[index * 2 + 1]))
		return ok(out)

	/*
    Returns the first match's [whole, group1, ...] byte ranges, or outer none when no match exists.
    An unmatched group is inner none; a participating empty group has start == end.
    max_captures bounds slots including the whole match and unmatched groups. Negative budgets return EINVAL;
    excess returns EOVERFLOW. The budget bounds output, not input scanning or engine scratch space.
    */
	fn capture_spans(text: String, max_captures: Int?) List[RegexSpan?]?!:
		raw := try msstd_regex_capture_spans(self, text, max_captures)
		if raw.is_empty(): return ok(none)

		return ok(capture_slots(raw, 1, raw[0]))

	/*
    Like capture_spans for every match in captures_all order; no match gives an empty list.
    max_matches bounds rows; max_captures bounds total slots across rows, including whole and unmatched groups.
    Negative budgets return EINVAL, excess returns EOVERFLOW; these are output budgets, not search limits.
    */
	fn capture_all_spans(
		text: String,
		max_matches: Int?,
		max_captures: Int?
	) List[List[RegexSpan?]]!:
		raw := try msstd_regex_capture_all_spans(self, text, max_matches, max_captures)
		if raw.is_empty(): return ok(List[List[RegexSpan?]]())

		count := raw[0]
		var out = List[List[RegexSpan?]](reserve: (raw.length() - 1) / (count * 2))
		var at = 1

		while at < raw.length():
			out.append(capture_slots(raw, at, count))
			at += count * 2

		return ok(out)
