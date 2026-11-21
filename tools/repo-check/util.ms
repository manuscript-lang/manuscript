// Helpers shared by the repository checks.
import read_file from "@std/os/fs.ms"

// The text of the file at `path`, or none when it cannot be read or is not UTF-8.
export fn read_text(path: String) String?:
	if data := read_file(path).wait(): return data.decode_utf8()
	return none

// Whether the file at `path` holds a carriage return.
export fn has_carriage_return(path: String) Bool:
	if data := read_file(path).wait(): return data.contains("\r".to_bytes())
	return false

// Vendored code and frozen conformance inputs are not ours to rewrite.
export fn skipped(path: String) Bool:
	return (
		path.starts_with("vendor/")
		or path.starts_with("runtime/third_party/")
		or path.starts_with("website/themes/")
		or path.starts_with("tests/conformance/fixtures/")
		or path.starts_with("compiler/tests/prelude/")
	)

export fn is_word_byte(byte: UInt8) Bool:
	return (
		(byte >= 48 and byte <= 57)
		or (byte >= 65 and byte <= 90)
		or (byte >= 97 and byte <= 122)
		or byte == 95
		or byte >= 128
	)

// Whether `word` occurs in `text` bounded by non-identifier characters.
export fn contains_word(text: String, word: String) Bool:
	data := text.as_bytes()
	var from = 0

	while from <= text.length() - word.length():
		rest := text.slice(from, text.length())
		found := rest.index_of(word).get_or(-1)
		if found < 0: return false

		start := from + found
		end := start + word.length()
		before_ok := start == 0 or not is_word_byte(data.get(start - 1))
		after_ok := end >= text.length() or not is_word_byte(data.get(end))
		if before_ok and after_ok: return true

		from = start + 1

	return false

// The identifier-bounded words of a line.
export fn words(text: String) List[String]:
	data := text.as_bytes()
	var out = List[String]()
	var start = -1

	for at in 0..text.length():
		if is_word_byte(data.get(at)):
			if start < 0: start = at
		else if start >= 0:
			out.append(text.slice(start, at))
			start = -1

	if start >= 0: out.append(text.slice(start, text.length()))
	return out

// The code part of a line: everything before the first `//`.
export fn code_of(line: String) String:
	if at := line.index_of("//"): return line.slice(0, at)
	return line.clone()

// Lines of a list file that are neither blank nor `//` comments, trimmed.
export fn list_lines(text: String) List[String]:
	var out = List[String]()

	for raw in text.lines():
		line := raw.trim()
		if line.is_empty() or line.starts_with("//"): continue

		out.append(line)

	return out

// Compares what a check found with its shrinking allow list: a finding outside the list
// is a violation (`violation(path, entry)`), a list line no check found is stale
// (`stale(line)`).
// `found` holds `path entry` strings split at the first space.
export fn check_shrinking(
	allowed: List[String],
	found: List[String],
	violation: fn(String, String) String,
	stale: fn(String) String
) List[String]:
	var seen = Set[String]()
	var issues = List[String]()

	for key in found:
		if allowed.contains(key):
			seen.add(key.clone())
		else if parts := key.split_once(" "):
			issues.append(violation(parts.before, parts.after))

	for line in allowed:
		if not seen.contains(line): issues.append(stale(line))
	return issues
