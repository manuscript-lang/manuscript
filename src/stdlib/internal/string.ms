import Regex from "@std/regex.ms"

export extern fn msrt_string_from_scalars(values List[Int]) String!

export extern fn msrt_string_fields(hold text String) List[&String]

// The piece of `text` that starts at byte `at` when it is split at `separator`, a view
// of `text`.

// Byte offset of the first scalar of `text` that occurs in `set`, or null.
export extern fn msrt_string_index_any(text, set String) Int?

// Text without the scalars of `set` at the start and, as selected, the end.
export extern fn msrt_string_trim_chars(
	text,
	set String,
	from_start,
	from_end Bool,
) String

export extern fn msstd_unicode_in_category(value Int, category String) Bool

export extern fn msstd_regex_compile(pattern String) Regex!

export extern fn msstd_regex_find_span(re Regex, text String) List[Int]?

export extern fn msstd_regex_captures(re Regex, text String) List[String]

export extern fn msstd_regex_captures_all(
	re Regex,
	text String,
	max_matches Int?,
) List[List[String]]!

// The first match's named groups that took part: name, text, name, text, ... in group
// order.
export extern fn msstd_regex_named_capture_pairs(re Regex, text String) List[String]

// Flat byte-offset pairs; captures start with the number of slots per match and use -1
// for absent groups.
export extern fn msstd_regex_find_all_spans(
	re Regex,
	text String,
	max_matches Int?,
) List[Int]!

export extern fn msstd_regex_capture_spans(
	re Regex,
	text String,
	max_captures Int?,
) List[Int]!

export extern fn msstd_regex_capture_all_spans(
	re Regex,
	text String,
	max_matches,
	max_captures Int?,
) List[Int]!

// The byte offset where the piece that starts at `at` ends when `text` is split at
// `separator`.
export extern fn msrt_string_split_end(text, separator String, at Int) Int

// The bytes of `text` from `start` to `end` as a view, without checking that they cut
// between scalars: for the iterators, which cut at separators and scalar ends.
export extern fn msrt_string_piece(hold text String, start, end Int) &String

// The pieces of `text` from byte `at` on, as a list of views; none when `at` is past
// them.
export extern fn msrt_string_split_view(hold text, separator String, at Int) List[
	&String
]

// The lines of `text` as a list of views.
export extern fn msrt_string_lines(hold text String) List[&String]

// The scalar at byte offset `at`, an inline string.
export extern fn msrt_string_scalar_text(text String, at Int) String
