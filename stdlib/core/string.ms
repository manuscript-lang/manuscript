import (
	Bytes from "@std/bytes.ms",
	Writable from "@std/core.ms",
	StringBuilder from "@std/string_builder.ms",

	msrt_string_from_scalars from "@std/internal/string.ms",
	msstd_unicode_display_width,
	msstd_string_trim_chars,
	msstd_unicode_fields,
	msstd_unicode_is_alphanumeric from "@std/internal/unicode.ms",
)

// The UTF-8 encoding of the text.
fn String.as_bytes() Bytes:
	return self.to_bytes()

// Removes one exact prefix, or returns none when absent; an empty prefix succeeds
// unchanged.
fn String.cut_prefix(prefix: String) String?:
	if self.starts_with(prefix): return self.drop(prefix.length())
	return none

// Removes one exact suffix, or returns none when absent; an empty suffix succeeds
// unchanged.
fn String.cut_suffix(suffix: String) String?:
	if self.ends_with(suffix): return self.take(self.length() - suffix.length())
	return none

// The four Unicode normalization forms, selected without runtime string spelling
// errors.
export enum NormalizationForm:
	// Canonical decomposition followed by canonical recomposition where Unicode permits
	// it.
	Nfc
	// Canonical decomposition with combining marks placed in canonical order.
	Nfd
	// Compatibility decomposition followed by canonical recomposition where Unicode
	// permits it.
	Nfkc
	// Compatibility decomposition with combining marks placed in canonical order.
	Nfkd

// Normalizes text with the existing String.normalize budgets and error kinds.
// Omission or none adds no output budget; a supplied budget counts UTF-8 bytes.
fn NormalizationForm.normalize(text: String, max_bytes: Int?) String!: ...

// Builds text from Unicode scalar values. Invalid scalars return `EINVAL`.
export fn from_scalars(values: List[Int]) String!:
	return msrt_string_from_scalars(values)

// Splits on Unicode White_Space, omitting empty fields; empty or all-whitespace
// text gives an empty list. Exact field text is preserved without normalization;
// the byte-order mark and zero-width space are not separators.
fn String.fields() List[String]:
	return msstd_unicode_fields(self)

// Terminal columns the text occupies, measured by Unicode sequence width with
// ambiguous characters narrow: combining marks add nothing, wide characters and
// supported emoji sequences count two. An estimate, not a promise for every font or
// terminal. Controls (tabs, CR/LF, ESC, C1), U+2028 and U+2029 return EBADMSG.
fn String.display_width() Int!:
	return msstd_unicode_display_width(self)

// Scalars read per step by the prefix scans below; each step doubles, so a scan costs
// its distance.
SCAN_WINDOW := 32

// Splits around runs of characters (one-scalar strings) the predicate accepts; no
// empty items.
fn String.fields_by(is_separator: fn(String) Bool) List[String]:
	var out = List[String]()

	// ASCII text: a scalar index is a byte offset, so each field is one copy of its run
	// instead of a builder per field.
	if self.length() == self.scalar_length():
		var start = -1
		var i = 0

		for c in self.chars():
			if is_separator(c):
				if start >= 0:
					out.append(self.view(start, i).clone())
					start = -1
			else if start < 0:
				start = i

			i += 1

		if start >= 0:
			out.append(self.view(start, i).clone())
		return out

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

// Compares text ignoring case: both sides are uppercased and then lowercased with
// Unicode full case mapping (no locale, no normalization), so "Straße" equals
// "STRASSE". This is not Unicode default case folding: the dotless "ı" (U+0131)
// uppercases to "I" and so compares equal to "i" and "I".
fn String.equal_fold(other: String) Bool:
	return fold_key(self) == fold_key(other)

// Capital sharp s (U+1E9E) uppercases to itself but is the capital form of "ß", so it
// is written as "ß" before the comparison.
fn fold_key(text: String) String:
	return text.replace("ẞ", "ß").upper().lower()

// Removes every leading and trailing scalar that occurs in set.
fn String.trim_chars(set: String) String:
	return msstd_string_trim_chars(self, set, true, true)

// Removes every leading scalar that occurs in set.
fn String.trim_start_chars(set: String) String:
	return msstd_string_trim_chars(self, set, true, false)

// Removes every trailing scalar that occurs in set.
fn String.trim_end_chars(set: String) String:
	return msstd_string_trim_chars(self, set, false, true)

// Reports whether any scalar of set occurs in the text.
fn String.contains_any(set: String) Bool:
	return self.index_any(set).is_some()

// Scalar index of the first scalar that occurs in set, or none.
fn String.index_any(set: String) Int?:
	return self.find_char(fn c: set.contains(c))

// Splits after each separator, keeping it at the end of each piece; an empty
// separator splits into scalars.
fn String.split_after(separator: String) List[String]:
	if separator.is_empty(): return self.chars().clone()

	var out = List[String]()
	parts := self.split(separator)

	for i in 0..parts.length():
		if i + 1 < parts.length():
			out.append(parts[i].concat(separator))
		else if not parts[i].is_empty():
			out.append(parts[i].clone())

	return out

// Uppercases the first scalar to its titlecase form (`ǆ` becomes `ǅ`, `ß` becomes `Ss`)
// and leaves the rest unchanged.
fn String.capitalize() String:
	return title_scalar(self.take(1)).concat(self.drop(1))

// Capitalizes the first letter of each run of letters, digits and apostrophes with its
// titlecase form and lowercases the others; a word is lowercased whole, so a final
// sigma stays final (`ΑΣ` becomes `Ας`).
fn String.title() String:
	var out = StringBuilder()
	var word = StringBuilder()
	var in_word = false

	for c in self.chars():
		if is_word_scalar(c):
			word.append(c)
			in_word = true
		else:
			if in_word: out.append(title_word(word.build()))
			word = StringBuilder()
			in_word = false
			out.append(c)

	if in_word: out.append(title_word(word.build()))
	return out.build()

// The word with its first scalar titlecased and the rest lowercased in context.
fn title_word(word: String) String:
	first := word.take(1)
	lowered := word.lower()
	head := first.lower()
	if lowered.starts_with(head): return title_scalar(first).concat(
		lowered.drop(head.scalar_length())
	)

	return title_scalar(first).concat(word.drop(1).lower())

// The titlecase mapping of one scalar: the four digraph families map to their
// mixed-case letter, and any other scalar takes its full uppercase mapping with every
// cased scalar after the first lowercased (`ß` gives `Ss`, `ﬁ` gives `Fi`, `ŉ` gives
// `ʼN`).
fn title_scalar(c: String) String:
	code := c.scalar_at(0, -1)
	if code >= 0x01C4 and code <= 0x01CC:
		return "ǅǅǅǈǈǈǋǋǋ".chars()[code - 0x01C4].clone()
	if code >= 0x01F1 and code <= 0x01F3: return "ǲ"

	upper := c.upper()
	var out = StringBuilder()
	var seen_cased = false

	for u in upper.chars():
		cased := u.lower() != u or u.upper() != u

		if cased and seen_cased: out.append(u.lower())
		else: out.append(u)

		if cased: seen_cased = true

	return out.build()

// Replaces each scalar with the transform's result; an empty result deletes it.
fn String.map_chars(transform: fn(String) String) String:
	var out = StringBuilder()
	for c in self.chars():
		out.append(transform(c))
	return out.build()

// Scalar index of the first scalar the predicate accepts, or none.
fn String.find_char(predicate: fn(String) Bool) Int?:
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

// Replaces many patterns in one pass. At each position the first pair, in map
// order, whose key matches wins and its replacement is not rescanned; empty keys
// are ignored.
fn String.replace_each(pairs: Map[String, String]) String:
	if pairs.is_empty(): return self.clone()

	var out = StringBuilder()
	news := pairs.values()
	var needles = List[List[String]]()
	for key in pairs.keys():
		needles.append(key.chars().clone())

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
