import (
	Bytes from "@std/bytes.ms",
	Writable from "@std/core.ms",
	StringBuilder from "@std/string_builder.ms",

	msrt_string_fields,
	msrt_string_from_scalars,
	msrt_string_index_any,
	msrt_string_trim_chars from "@std/internal/string.ms",
	msstd_unicode_display_width,
	msstd_unicode_is_alphanumeric from "@std/internal/unicode.ms",
)

// The UTF-8 encoding of the text.
fn String.as_bytes() Bytes:
	return self.to_bytes()

// Returns the text without `prefix`, or `null` when the text does not start with it.
// An empty prefix succeeds and returns the text unchanged.
fn String.cut_prefix(prefix: String) String?:
	if self.starts_with(prefix): return self.view(
		prefix.length(),
		self.length(),
	).clone()
	return null

// Returns the text without `suffix`, or `null` when the text does not end with it.
// An empty suffix succeeds and returns the text unchanged.
fn String.cut_suffix(suffix: String) String?:
	if self.ends_with(suffix): return self.view(
		0,
		self.length() - suffix.length(),
	).clone()
	return null

// The text before and after the first (or last) separator, as returned by
// `split_once` and `rsplit_once`.
export type SplitParts:
	// The text before the separator.
	before: String
	// The text after the separator.
	after: String

// Splits at the first exact separator. Returns `null` when the separator is empty or
// does not occur.
// Example: `"key=a=b".split_once("=")` is `before: "key"`, `after: "a=b"`.
fn String.split_once(separator: String) SplitParts?:
	if separator.is_empty(): return null

	at := self.index_of(separator)
	if at == null: return null

	cut := at or 0
	return SplitParts(
		before: self.view(0, cut).clone(),
		after: self.view(cut + separator.length(), self.length()).clone(),
	)

// Splits at the last exact separator. Returns `null` when the separator is empty or
// does not occur.
// Example: `"a/b/c".rsplit_once("/")` is `before: "a/b"`, `after: "c"`.
fn String.rsplit_once(separator: String) SplitParts?:
	if separator.is_empty(): return null

	at := self.last_index_of(separator)
	if at == null: return null

	cut := at or 0
	return SplitParts(
		before: self.view(0, cut).clone(),
		after: self.view(cut + separator.length(), self.length()).clone(),
	)

// The four Unicode normalization forms, as an enum so a misspelled form is a compile
// error rather than a runtime `EINVAL`.
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

// Normalizes `text` to this form, with the same budget and errors as
// `String.normalize`. When `max_bytes` is omitted or `null` the output is not
// bounded; a supplied bound counts UTF-8 bytes.
fn NormalizationForm.normalize(text: String, max_bytes: Int?) String!:
	name := match self:
		Nfc: "NFC"
		Nfd: "NFD"
		Nfkc: "NFKC"
		Nfkd: "NFKD"

	return text.normalize(name, max_bytes)

// Builds text from Unicode scalar values. Invalid scalars return `EINVAL`.
export fn from_scalars(values: List[Int]) String!:
	return msrt_string_from_scalars(values)

// Splits on runs of Unicode White_Space and omits empty fields, so empty or
// all-whitespace text gives an empty list. Field text is kept exactly, without
// normalization. The byte-order mark and zero-width space are not separators.
fn String.fields() List[String]:
	return msrt_string_fields(self)

// Returns the number of terminal columns the text occupies. Combining marks add
// nothing, ambiguous-width characters count as narrow, and wide characters and
// supported emoji sequences count two. This is an estimate, not a promise for every
// font or terminal. Controls (tabs, CR/LF, ESC, C1), U+2028 and U+2029 return
// `EBADMSG`.
fn String.display_width() Int!:
	return msstd_unicode_display_width(self)

// Bytes of the UTF-8 encoding of the scalar value `code`; zero for a negative value.
fn scalar_width(code: Int) Int:
	if code < 0: return 0
	if code < 0x80: return 1
	if code < 0x800: return 2
	if code < 0x10000: return 3

	return 4

// Splits around runs of characters (one-scalar strings) for which `is_separator`
// returns true. The result has no empty items.
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

// Compares text ignoring case. Both sides are uppercased and then lowercased with
// Unicode full case mapping, without locale or normalization, so "Straße" equals
// "STRASSE". This is not Unicode default case folding: the dotless "ı" (U+0131)
// uppercases to "I", so it compares equal to "i" and "I".
fn String.equal_fold(other: String) Bool:
	// While both texts are ASCII the keys match byte for byte after ASCII lowercasing,
	// so the first difference decides and no key is built. A non-ASCII byte on either
	// side hands the whole comparison to the full case mapping.
	left := self.view_bytes()
	right := other.view_bytes()
	var shared = left.length()
	if right.length() < shared: shared = right.length()

	var at = 0

	while at < shared:
		a := left.get(at)
		b := right.get(at)
		if a >= 128 or b >= 128: return fold_key(self) == fold_key(other)

		if a != b:
			low_a := if a >= 65 and a <= 90: a + 32 else: a
			low_b := if b >= 65 and b <= 90: b + 32 else: b
			if low_a != low_b: return false

		at += 1

	// A longer text keeps scalars the shorter one lacks, and no case mapping erases a
	// scalar, so the keys differ in length.
	return left.length() == right.length()

// Capital sharp s (U+1E9E) uppercases to itself but is the capital form of "ß", so it
// is written as "ß" before the comparison.
fn fold_key(text: String) String:
	return text.replace("ẞ", "ß").upper().lower()

// Removes every leading and trailing scalar that occurs in `set`.
fn String.trim_chars(set: String) String:
	return msrt_string_trim_chars(self, set, true, true)

// Removes every leading scalar that occurs in `set`.
fn String.trim_start_chars(set: String) String:
	return msrt_string_trim_chars(self, set, true, false)

// Removes every trailing scalar that occurs in `set`.
fn String.trim_end_chars(set: String) String:
	return msrt_string_trim_chars(self, set, false, true)

// Reports whether any scalar of `set` occurs in the text.
fn String.contains_any(set: String) Bool:
	return self.index_any(set) != null

// Returns the byte offset of the first scalar that occurs in `set`, or `null`.
fn String.index_any(set: String) Int?:
	return msrt_string_index_any(self, set)

// Splits after each separator and keeps the separator at the end of each piece. An
// empty separator splits into scalars.
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

// Converts the first scalar to its titlecase form (`ǆ` becomes `ǅ`, `ß` becomes
// `Ss`) and leaves the rest unchanged.
fn String.capitalize() String:
	first := self.scalar_at(0, -1)
	if first >= 0 and first < 128: return self.view(0, 1).upper().concat(
		self.view(1, self.length())
	)

	n := scalar_width(first)
	return title_scalar(self.view(0, n)).concat(self.view(n, self.length()))

// Titlecases the first letter of each word and lowercases the rest. A word is a run
// of letters, digits and apostrophes. Each word is lowercased as a whole, so a final
// sigma stays final (`ΑΣ` becomes `Ας`).
fn String.title() String:
	bytes := self.view_bytes()
	count := bytes.length()
	var at = 0
	while at < count and bytes.get(at) < 128: at += 1
	if at < count: return title_scalars(self)

	// ASCII text: lowercase it once and copy the lowercase runs between the first
	// letters of words, which come from the uppercase alphabet by index.
	lowered := self.lower()
	var out = StringBuilder()
	var copied = 0
	var in_word = false

	for i in 0..count:
		b := bytes.get(i)
		word := (
			(b >= 48 and b <= 57)
			or (b >= 65 and b <= 90)
			or (b >= 97 and b <= 122)
			or b == 39
		)

		if word and not in_word and ((b >= 97 and b <= 122) or (b >= 65 and b <= 90)):
			out.append(lowered.view(copied, i))

			var letter = b.to_int() - 97
			if b <= 90: letter = b.to_int() - 65
			out.append("ABCDEFGHIJKLMNOPQRSTUVWXYZ".view(letter, letter + 1))
			copied = i + 1

		in_word = word

	out.append(lowered.view(copied, count))
	return out.build()

// `title` for text with any non-ASCII scalar, one word at a time.
fn title_scalars(text: String) String:
	var out = StringBuilder()
	var word = StringBuilder()
	var in_word = false

	for c in text.chars():
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
	n := scalar_width(word.scalar_at(0, -1))
	first := word.view(0, n)
	lowered := word.lower()
	head := first.lower()
	if lowered.starts_with(head): return title_scalar(first).concat(
		lowered.view(head.length(), lowered.length())
	)

	return title_scalar(first).concat(word.view(n, word.length()).lower())

// Whether the scalar is one of the Greek titlecase letters (ᾈ to ᾏ, ᾘ to ᾟ, ᾨ to ᾯ, ᾼ,
// ῌ, ῼ).
fn greek_titlecase(code: Int) Bool:
	return (
		(code >= 0x1F88 and code <= 0x1F8F)
		or (code >= 0x1F98 and code <= 0x1F9F)
		or (code >= 0x1FA8 and code <= 0x1FAF)
		or code == 0x1FBC
		or code == 0x1FCC
		or code == 0x1FFC
	)

// Whether the scalar is a Greek letter whose uppercase ends in capital iota but whose
// titlecase ends in U+0345 (ᾲ ᾴ ᾷ ῂ ῄ ῇ ῲ ῴ ῷ).
fn greek_iota_tail(code: Int) Bool:
	return (
		code == 0x1FB2
		or code == 0x1FB4
		or code == 0x1FB7
		or code == 0x1FC2
		or code == 0x1FC4
		or code == 0x1FC7
		or code == 0x1FF2
		or code == 0x1FF4
		or code == 0x1FF7
	)

// The Greek titlecase letter of a lowercase letter with ypogegrammeni (ᾀ gives ᾈ), or
// 0.
fn greek_titlecase_of(code: Int) Int:
	if (
		(code >= 0x1F80 and code <= 0x1F87)
		or (code >= 0x1F90 and code <= 0x1F97)
		or (code >= 0x1FA0 and code <= 0x1FA7)
	): return code + 8
	if code == 0x1FB3: return 0x1FBC
	if code == 0x1FC3: return 0x1FCC
	if code == 0x1FF3: return 0x1FFC

	return 0

// The titlecase mapping of one scalar: the four digraph families map to their
// mixed-case letter, and any other scalar takes its full uppercase mapping with every
// cased scalar after the first lowercased (`ß` gives `Ss`, `ﬁ` gives `Fi`, `ŉ` gives
// `ʼN`).
fn title_scalar(c: String) String:
	code := c.scalar_at(0, -1)
	if code >= 0x01C4 and code <= 0x01CC:
		return "ǅǅǅǈǈǈǋǋǋ".chars()[code - 0x01C4].clone()
	if code >= 0x01F1 and code <= 0x01F3: return "ǲ"

	// The Greek letters with ypogegrammeni have their own titlecase letters (category
	// Lt).
	if greek_titlecase(code): return c.clone()

	mapped := greek_titlecase_of(code)
	if mapped > 0: return from_scalars([mapped]) or c.clone()

	upper := c.upper()

	// The titlecase of these Greek letters ends in the combining ypogegrammeni
	// (U+0345), where the uppercase ends in capital iota.
	if greek_iota_tail(code) and upper.ends_with("Ι"):
		return upper.view(0, upper.length() - 2).concat("\u{345}")

	var out = StringBuilder()
	var seen_cased = false

	for u in upper.chars():
		cased := u.lower() != u or u.upper() != u

		if cased and seen_cased: out.append(u.lower())
		else: out.append(u)

		if cased: seen_cased = true

	return out.build()

// Replaces each scalar (a one-scalar string) with the result of `transform`; an
// empty result deletes it.
fn String.map_chars(transform: fn(String) String) String:
	var out = StringBuilder()
	for c in self.chars():
		out.append(transform(c))
	return out.build()

// Returns the byte offset of the first scalar (passed as a one-scalar string) for
// which `predicate` returns true, or `null`.
fn String.find_char(predicate: fn(String) Bool) Int?:
	var at = 0
	n := self.length()

	while at < n:
		width := scalar_width(self.scalar_at(at))
		if predicate(self.view(at, at + width)): return at

		at += width

	return null

// Replaces many patterns in one pass. At each position the first pair, in map
// order, whose key matches wins, and its replacement is not rescanned. Empty keys
// are ignored.
fn String.replace_each(pairs: Map[String, String]) String:
	if pairs.is_empty(): return self.clone()

	keys := pairs.keys().map(fn key: key.as_bytes())
	news := pairs.values()
	bytes := self.as_bytes()
	n := bytes.length()
	var nexts = List[Int](reserve: keys.length())

	// -1 marks a key whose first byte is not located yet; an empty key never is.
	for key in keys:
		nexts.append(if key.is_empty(): n else: -1)

	var out = StringBuilder()
	var copied = 0
	var i = 0
	count := keys.length()

	while i < n:
		var at = n
		var first = 0

		for j in 0..count:
			if nexts[j] < i:
				nexts[j] = bytes.index_of_byte(keys[j].get(0), i) or n

			if nexts[j] < at:
				at = nexts[j]
				first = j

		if at >= n: break

		i = at

		// The earliest key in map order whose first byte is here goes first.
		var hit = -1

		for j in first..count:
			if nexts[j] != i: continue

			end := i + keys[j].length()

			if end <= n and bytes.view(i, end) == keys[j]:
				hit = j
				break

		if hit < 0:
			i += 1
			continue

		out.append(self.view(copied, i))
		out.append(news[hit])
		i += keys[hit].length()
		copied = i

	out.append(self.view(copied, n))
	return out.build()

fn is_word_scalar(c: String) Bool:
	return msstd_unicode_is_alphanumeric(c.scalar_at(0, -1)) or c == "'"
