import (
	msstd_regex_capture_all_spans,
	msstd_regex_capture_spans,
	msstd_regex_compile,
	msstd_regex_find_all_spans
) from "@std/internal/string.ms"

// A compiled regular expression that can be reused across input strings.
export extern type Regex

// Tests whether any match occurs; anchor the pattern explicitly to require a
// whole-string match.
fn Regex.matches(text: String) Bool: ...

// Returns nonoverlapping full-match text in occurrence order, excluding capture
// groups. A supplied cap is a strict budget, not truncation; zero-width matches
// follow the engine's rules.
fn Regex.find_all(text: String, max_matches: Int?) List[String]!: ...

// Replaces every nonoverlapping match with literal replacement text; $ and capture
// names are not expanded. max_bytes optionally bounds UTF-8 output; negatives
// return EINVAL, exhaustion EOVERFLOW.
fn Regex.replace_all(text: String, replacement: String, max_bytes: Int?) String!: ...

// Returns the first match as [whole, group1, ...]; groups that did not participate
// are "". Empty list when nothing matches.
fn Regex.captures(text: String) List[String]: ...

// Like captures for every nonoverlapping match, under find_all's match-count
// budget.
fn Regex.captures_all(text: String, max_matches: Int?) List[List[String]]!: ...

// Returns the first match's named groups that participated; empty map when nothing
// matches.
fn Regex.named_captures(text: String) Map[String, String]: ...

// Returns [start, end] UTF-8 byte offsets of the first match, or none when nothing
// matches.
fn Regex.find_span(text: String) List[Int]?: ...

// Splits text around every match, always returning at least one piece. max_pieces
// is a strict budget like find_all's.
fn Regex.split(text: String, max_pieces: Int?) List[String]!: ...

// Like replace_all but expands $1, ${name}, and $$ in template from each match
// (Rust regex syntax: use ${1}x, not $1x).
fn Regex.replace_template(text: String, template: String, max_bytes: Int?) String!: ...

// Returns all full-match byte ranges in find_all order, without copying matched
// text. max_matches is a strict output budget: negatives return EINVAL, excess
// returns EOVERFLOW.
fn Regex.find_all_spans(text: String, max_matches: Int?) List[RegexSpan]!:
	raw := msstd_regex_find_all_spans(self, text, max_matches)?
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
fn Regex.capture_spans(text: String, max_captures: Int?) List[RegexSpan?]?!:
	raw := msstd_regex_capture_spans(self, text, max_captures)?
	if raw.is_empty(): return ok(none)

	return ok(capture_slots(raw, 1, raw[0]))

/*
Like capture_spans for every match in captures_all order; no match gives an empty list.
max_matches bounds rows; max_captures bounds total slots across rows, including whole and unmatched groups.
Negative budgets return EINVAL, excess returns EOVERFLOW; these are output budgets, not search limits.
*/
fn Regex.capture_all_spans(
	text: String,
	max_matches: Int?,
	max_captures: Int?,
) List[List[RegexSpan?]]!:
	raw := msstd_regex_capture_all_spans(self, text, max_matches, max_captures)?
	if raw.is_empty(): return ok(List[List[RegexSpan?]]())

	count := raw[0]
	var out = List[List[RegexSpan?]](reserve: (raw.length() - 1) / (count * 2))
	var at = 1

	while at < raw.length():
		out.append(capture_slots(raw, at, count))
		at += count * 2

	return ok(out)

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

// Compiles a regular expression. Invalid pattern syntax is returned as an error.
export fn compile(pattern: String) Regex!:
	return msstd_regex_compile(pattern)

fn capture_slots(raw: List[Int], start: Int, count: Int) List[RegexSpan?]:
	var out = List[RegexSpan?](reserve: count)

	for index in 0..count:
		at := start + index * 2

		if raw[at] < 0:
			out.append(none)
		else:
			out.append(RegexSpan(raw[at], raw[at + 1]))

	return out
