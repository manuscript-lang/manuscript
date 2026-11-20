// Unified diff parsing and reverse application, for `ms review`. Port of
// crates/ms-tooling/src/diff.rs; never runs git.
import (
	BytesBuilder from "@std/bytes.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	files from "@data",
)

// One `@@` hunk. Lines keep their one-character prefix: ' ' context, '+' added, '-'
// removed.
export type DiffHunk:
	old_start: Int
	old_len: Int
	new_start: Int
	new_len: Int
	lines: List[String] = []
	// The final old-side or new-side line has no line terminator.
	old_no_newline: Bool = false
	new_no_newline: Bool = false

// The hunks for one file. An empty `old` marks an added file and an empty `new` a
// deleted one.
export type DiffFile:
	old: String = ""
	new: String = ""
	hunks: List[DiffHunk] = []

fn DiffFile.path() String: if self.new.is_empty(): self.old.clone() else: self.new.clone()

// Head-side line numbers the hunks changed. A removal is attributed to the head line
// that follows it.
fn DiffFile.touched_lines() List[Int]:
	var touched = List[Int]()

	for hunk in self.hunks:
		var line = hunk.new_start
		if hunk.new_len == 0: line += 1

		for text in hunk.lines:
			first := text.slice(0, 1)
			if first == "+" or first == "-": touched.append(line)
			if first != "-": line += 1

	return touched

RENAME_HINT := "renamed files are not supported; produce the diff with git diff --no-renames"
MAX_INT := 9223372036854775807

fn fail(message: String) Error: Error(message)

// The text without a trailing carriage-return normalization: lines of `text` split at
// '\n', with a final terminator ending its line instead of starting an empty one.
fn split_lines(text: String) List[String]:
	var lines = List[String]()
	for line in text.split("\n"): lines.append(line.clone())
	if text.is_empty() or text.ends_with("\n"): lines.pop()
	return lines

fn starts_git_extension(line: String) Bool: (
	line.starts_with("old mode ")
	or line.starts_with("new mode ")
	or line.starts_with("new file mode ")
	or line.starts_with("deleted file mode ")
	or line.starts_with("Binary files ")
	or line == "GIT binary patch"
)

// Reads a unified diff (git or plain `diff -u`).
export fn parse_diff(source: String) List[DiffFile]!:
	text := source.replace("\r\n", "\n")
	lines := split_lines(text)
	var files = List[DiffFile]()
	var have_current = false
	var git = false
	var git_header = ""
	var i = 0

	while i < lines.length():
		line := lines[i].clone()

		if fields := line.cut_prefix("diff --git "):
			git_header = fields.clone()
			files.append(DiffFile())
			have_current = true
			git = true
		else if line.starts_with("rename from ") or line.starts_with("rename to "): return error(
			fail(RENAME_HINT)
		)
		else if (
			line.starts_with("--- ")
			and i + 1 < lines.length()
			and lines[i + 1].starts_with("+++ ")
		):
			if not have_current or not git:
				files.append(DiffFile())
				have_current = true

			last := files.length() - 1
			if git and not files[last].hunks.is_empty(): return error(
				fail(
					f"diff line {i + 1}: multiple text headers in one Git file section"
				)
			)

			old := diff_path(line.slice(4, line.length()), "a/", git).map_error(
				line_error(i + 1)
			)?
			new := diff_path(lines[i + 1].slice(4, lines[i + 1].length()), "b/", git).map_error(
				line_error(i + 2)
			)?
			files[last].old = old.clone()
			files[last].new = new.clone()

			if (
				not git
				and old.starts_with("a/")
				and new.starts_with("b/")
				and old.slice(2, old.length()) == new.slice(
					2,
					new.length(),
				)
			):
				files[last].old = old.slice(2, old.length())
				files[last].new = new.slice(2, new.length())

			i += 1
		else if line.starts_with("@@ "):
			if not have_current: return error(
				fail(f"diff line {i + 1}: hunk before any file header")
			)

			parsed := parse_hunk(lines, i)?
			files[files.length() - 1].hunks.append(parsed.hunk.clone())
			i = parsed.next
			continue
		else if git and have_current and starts_git_extension(line):
			if line.starts_with("Binary files ") or line == "GIT binary patch": return error(
				fail(
					"binary diff cannot reconstruct the base; produce a text diff with git diff --text --no-renames"
				)
			)

			last := files.length() - 1

			if (
				files[last].old.is_empty()
				and files[last].new.is_empty()
				and not git_header.is_empty()
			):
				path := git_section_path(git_header)
				git_header = ""

				if p := path:
					files[last].old = p.clone()
					files[last].new = p.clone()

			if line.starts_with("new file mode "): files[last].old = ""
			else if line.starts_with("deleted file mode "): files[last].new = ""

		i += 1

	if files.is_empty() and not text.trim().is_empty(): return error(
		fail("input is not a unified diff; pipe in git diff --no-renames")
	)

	for file in files:
		if file.old.is_empty() and file.new.is_empty(): return error(
			fail("diff has a file header with no paths")
		)
		if not file.old.is_empty() and not file.new.is_empty() and file.old != file.new: return error(
			fail(
				f"renamed files are not supported ({file.old} -> {file.new}); produce the diff with git diff --no-renames"
			)
		)

	return ok(files)

fn line_error(line: Int) fn(Error) Error:
	return fn e: fail(f"diff line {line}: {e.message}")

// A non-renamed Git section repeats the same path with a/ and b/ prefixes. Those
// encoded fields have equal byte lengths, even when spaces are unquoted or unusual
// bytes are quoted.
fn git_section_path(fields: String) String?:
	half := fields.length() / 2
	old := fields.slice(0, half)
	rest := fields.slice(half, fields.length())
	if old.length() != half: return none

	new := rest.cut_prefix(" ")
	if new.is_none(): return none

	old_path := diff_path(old, "a/", true)
	new_path := diff_path(new.get(), "b/", true)
	if old_path.is_error() or new_path.is_error(): return none
	if old_path.get() == new_path.get(): return old_path.get()

	return none

fn diff_path(field: String, prefix: String, git: Bool) String!:
	var path = field.split("\t")[0].clone()
	if not git: path = path.trim()
	if path == "/dev/null": return ok("")
	if not git: return ok(path)

	if path.starts_with("\""): path = git_quoted_path(path)?

	// `git diff -R` swaps the prefixes: `--- b/x` then `+++ a/x`.
	other := if prefix == "a/": "b/" else: "a/"
	if stripped := path.cut_prefix(prefix): return ok(stripped.clone())
	if stripped := path.cut_prefix(other): return ok(stripped.clone())

	return ok(path)

fn octal(byte: UInt8) Int?:
	if byte >= 48 and byte <= 55: return byte.to_int() - 48
	return none

// Git quotes unusual path bytes, including UTF-8 bytes as three octal digits. Decode
// bytes first: decoding individual octal escapes as Unicode corrupts names.
fn git_quoted_path(path: String) String!:
	malformed := fail("malformed Git quoted path")
	body := path.cut_prefix("\"").get_or("")
	inner := body.cut_suffix("\"")
	if not path.starts_with("\"") or inner.is_none(): return error(malformed)

	input := inner.get().as_bytes()
	var out = BytesBuilder()
	var i = 0

	while i < input.length():
		byte := input[i]
		i += 1
		if byte == 34: return error(malformed)

		if byte != 92:
			out.append(byte)
			continue

		if i >= input.length(): return error(malformed)

		escaped := input[i]
		i += 1

		if escaped == 34 or escaped == 92: out.append(escaped)
		else if escaped == 97: out.append(7)
		else if escaped == 98: out.append(8)
		else if escaped == 116: out.append(9)
		else if escaped == 110: out.append(10)
		else if escaped == 118: out.append(11)
		else if escaped == 102: out.append(12)
		else if escaped == 114: out.append(13)
		else if escaped >= 48 and escaped <= 51:
			second := octal(input.get_or(i, 0))
			third := octal(input.get_or(i + 1, 0))
			if second.is_none() or third.is_none() or i + 1 >= input.length(): return error(
				malformed
			)

			value := (escaped.to_int() - 48) * 64 + second.get() * 8 + third.get()
			out.append(value.to_uint8().get_or(0))
			i += 2
		else: return error(malformed)

	bytes := out.build()
	for b in bytes.values():
		if b == 0: return error(fail("Git path contains a NUL byte"))
	if decoded := bytes.decode_utf8(): return ok(decoded.clone())

	return error(fail("Git path is not valid UTF-8"))

type ParsedHunk:
	hunk: DiffHunk
	next: Int

// Marks the no-newline note on the side the preceding line belongs to.
fn record_no_newline(var hunk: DiffHunk, old_left: Int, new_left: Int) Bool:
	if hunk.lines.is_empty(): return false

	line := hunk.lines[hunk.lines.length() - 1].clone()
	old := not line.starts_with("+")
	new := not line.starts_with("-")
	if (old and old_left != 0) or (new and new_left != 0): return false

	if old: hunk.old_no_newline = true
	if new: hunk.new_no_newline = true
	return true

fn all_digits(text: String) Bool:
	if text.is_empty(): return false

	for byte in text.as_bytes().values():
		if byte < 48 or byte > 57: return false
	return true

type Range:
	start: Int
	length: Int

fn parse_range(text: String) Range!:
	malformed := fail(f"malformed hunk range \"{text}\"")
	pieces := text.split(",")
	first := pieces[0].clone()
	has_second := pieces.length() > 1
	if pieces.length() > 2 or not all_digits(first): return error(malformed)
	if has_second and not all_digits(pieces[1]): return error(malformed)

	start := first.parse_int()
	var length: Int? = 1
	if has_second: length = pieces[1].parse_int()
	if start.is_none() or length.is_none(): return error(malformed)

	// Nonempty ranges start at one; traversal also needs the exclusive end.
	span := if length.get() > 1: length.get() else: 1
	if (start.get() == 0 and length.get() != 0) or start.get() > MAX_INT - span: return error(
		malformed
	)

	return ok(Range(start: start.get(), length: length.get()))

fn parse_hunk(lines: List[String], start: Int) ParsedHunk!:
	malformed := fail(f"diff line {start + 1}: malformed hunk header")
	rest := lines[start].slice(3, lines[start].length())
	end := rest.index_of(" @@")
	if end.is_none(): return error(malformed)

	parts := rest.slice(0, end.get()).split_once(" ")
	if parts.is_none(): return error(malformed)

	old := parts.get().before.clone()
	new := parts.get().after.clone()
	if not old.starts_with("-") or not new.starts_with("+"): return error(malformed)

	o := parse_range(old.slice(1, old.length())).map_error(line_error(start + 1))?
	n := parse_range(new.slice(1, new.length())).map_error(line_error(start + 1))?
	var h = DiffHunk(
		old_start: o.start,
		old_len: o.length,
		new_start: n.start,
		new_len: n.length,
	)
	var old_left = h.old_len
	var new_left = h.new_len
	var i = start + 1

	while i < lines.length() and (old_left > 0 or new_left > 0):
		var line = lines[i].clone()

		if line.starts_with("\\"):
			if not record_no_newline(h, old_left, new_left): return error(
				fail(
					f"diff line {i + 1}: no-newline marker is not after the final line of its side"
				)
			)

			i += 1
			continue

		if line.is_empty(): line = " "

		first := line.slice(0, 1)

		if first == " ":
			old_left -= 1
			new_left -= 1
		else if first == "-": old_left -= 1
		else if first == "+": new_left -= 1
		else: return error(
			fail(f"diff line {i + 1}: hunk ends before its declared length")
		)

		h.lines.append(line)
		i += 1

	if old_left != 0 or new_left != 0: return error(
		fail(f"diff line {start + 1}: hunk is shorter than its header declares")
	)

	while i < lines.length() and lines[i].starts_with("\\"):
		if not record_no_newline(h, 0, 0): return error(
			fail(
				f"diff line {i + 1}: no-newline marker is not after the final line of its side"
			)
		)

		i += 1

	// Empty separators do not turn later body lines into ignorable metadata.
	while i < lines.length() and lines[i].is_empty(): i += 1

	if i < lines.length():
		line := lines[i].clone()
		first := line.slice(0, 1)
		body := first == " " or first == "+" or first == "-"
		header := (
			line.starts_with("--- ")
			and i + 1 < lines.length()
			and lines[i + 1].starts_with("+++ ")
		)
		if line != "-- " and body and not header: return error(
			fail(
				f"diff line {i + 1}: hunk is longer than its header declares"
			)
		)

	return ok(ParsedHunk(hunk: h, next: i))

fn same_line(a: String, b: String) Bool: (
	a.trim_end_chars("\r") == b.trim_end_chars("\r")
)

// Reconstructs the base file from the head file and the hunks. Every context and added
// line is checked against the head, so a diff that does not describe this tree is an
// error rather than a guess.
export fn reverse_apply(head: String, hunks: List[DiffHunk]) String!:
	source := split_lines(head)
	var trailing_newline = head.ends_with("\n")

	// A later insertion-only hunk must retain an earlier old-side EOF marker.
	var old_eof = -1
	var out = List[String]()
	var position = 0

	for hunk in hunks:
		var index = hunk.new_start - 1
		if hunk.new_len == 0: index = hunk.new_start
		if index < position or index > source.length(): return error(
			fail(
				f"hunks overlap or fall outside the file at line {hunk.new_start}"
			)
		)

		for k in position..index: out.append(source[k].clone())

		expected := hunk.old_start - (if hunk.old_len > 0: 1 else: 0)
		if expected != out.length(): return error(
			fail(
				f"old hunk position {hunk.old_start} does not match the reconstructed base"
			)
		)

		for line in hunk.lines:
			text := line.slice(1, line.length())
			first := line.slice(0, 1)

			if first == "-":
				out.append(text.clone())
				continue

			if index >= source.length() or not same_line(source[index], text): return error(
				fail(f"line {index + 1} does not match the diff")
			)

			if first == " ": out.append(source[index].clone())
			index += 1

		if old_eof >= 0 and old_eof != out.length(): return error(
			fail(
				"no-newline marker appears before the end of the base file"
			)
		)

		if hunk.old_no_newline: old_eof = out.length()
		if hunk.new_no_newline and index != source.length(): return error(
			fail("no-newline marker appears before the end of the file")
		)

		if index == source.length():
			if hunk.new_len > 0 and hunk.new_no_newline == head.ends_with("\n"): return error(
				fail("final newline does not match the diff")
			)

			trailing_newline = old_eof < 0

		position = index

	for k in position..source.length(): out.append(source[k].clone())
	if old_eof >= 0 and old_eof != out.length(): return error(
		fail("no-newline marker appears before the end of the base file")
	)

	var result = out.join("\n")
	if not out.is_empty() and trailing_newline: result = result.concat("\n")
	return ok(result)

// The base text of a deleted file.
export fn removed_content(hunks: List[DiffHunk]) String:
	var out = List[String]()
	for hunk in hunks:
		for line in hunk.lines:
			if line.starts_with("-"): out.append(line.slice(1, line.length()))

	var result = out.join("\n")
	var no_newline = false
	if last := hunks.last(): no_newline = last.old_no_newline
	if not out.is_empty() and not no_newline: result = result.concat("\n")
	return result

// ---- Tests: the behavior crates/ms-tooling/tests/review.rs pinned ----

// The error text of `parse_diff`, or "" when it parses.
fn parse_error(patch: String) String:
	result := parse_diff(patch)
	if result.is_error(): return result.err().message.clone()

	return ""

fn parsed(patch: String) List[DiffFile]: parse_diff(patch).get_or([])

fn reversed(head: String, hunks: List[DiffHunk]) String: reverse_apply(head, hunks).get_or(
	"<error>"
)

fn reverse_error(head: String, hunks: List[DiffHunk]) Bool: reverse_apply(head, hunks).is_error()

SAMPLE_DIFF := "diff --git a/src/a.ms b/src/a.ms\nindex 111..222 100644\n--- a/src/a.ms\n+++ b/src/a.ms\n@@ -1,4 +1,5 @@\n fn one() Int:\n-    return 1\n+    x := 1\n+    return x\n \n fn two() Int:\ndiff --git a/new.ms b/new.ms\nnew file mode 100644\n--- /dev/null\n+++ b/new.ms\n@@ -0,0 +1,2 @@\n+fn n() Int:\n+    return 0\n"

test "a metadata-only git section keeps its path identity":
	pairs := [
		["a/main.ms", "b/main.ms", "main.ms"],
		["a/a b/name .ms", "b/a b/name .ms", "a b/name .ms"],
		["a/café.ms", "b/café.ms", "café.ms"],
		["\"a/caf\\303\\251.ms\"", "\"b/caf\\303\\251.ms\"", "café.ms"],
		[
			"\"a/quote\\\"tab\\t.ms\"", "\"b/quote\\\"tab\\t.ms\"", "quote\"tab\t.ms"
		],
	]

	for pair in pairs:
		files := parsed(
			f"diff --git {pair[0]} {pair[1]}\nold mode 100644\nnew mode 100755\n"
		)
		expect_equal(files.length(), 1)?
		expect_equal(files[0].old, pair[2])?
		expect_equal(files[0].new, pair[2])?
		expect_true(files[0].hunks.is_empty())?
		expect_true(files[0].touched_lines().is_empty())?
		expect_equal(reversed("unchanged\n", files[0].hunks), "unchanged\n")?

test "metadata-only empty files keep the absent side":
	files := parsed(
		"diff --git a/empty.ms b/empty.ms\nnew file mode 100644\nindex 0000000..e69de29\ndiff --git a/gone.ms b/gone.ms\ndeleted file mode 100644\nindex e69de29..0000000\n"
	)
	expect_equal(files.length(), 2)?
	expect_true(files[0].old.is_empty())?
	expect_equal(files[0].new, "empty.ms")?
	expect_equal(files[1].old, "gone.ms")?
	expect_true(files[1].new.is_empty())?
	expect_equal(removed_content(files[1].hunks), "")?

test "text headers override the section fallback paths":
	files := parsed(
		"diff --git a/ignored.ms b/ignored.ms\nold mode 100644\nnew mode 100755\n--- a/actual.ms\n+++ b/actual.ms\n@@ -1 +1 @@\n-old\n+new\n"
	)
	expect_equal(files[0].path(), "actual.ms")?
	expect_equal(reversed("new\n", files[0].hunks), "old\n")?

test "binary metadata stays rejected":
	for metadata in [
		"Binary files a/image.png and b/image.png differ", "GIT binary patch"
	]:
		message := parse_error(
			f"diff --git a/image.png b/image.png\nnew file mode 100644\n{metadata}\n"
		)
		expect_true(message.contains("git diff --text --no-renames"))?

	expect_true(not parse_error("diff --git a/x.ms b/x.ms\n").is_empty())?
	expect_true(
		not parse_error(
			"diff --git a/x.ms b/x.ms\n+missing hunk header\n"
		).is_empty()
	)?

test "a diff parses and reverses against the head":
	files := parsed(SAMPLE_DIFF)
	expect_equal(files.length(), 2)?
	expect_equal(files[0].path(), "src/a.ms")?
	expect_true(files[1].old.is_empty() and files[1].new == "new.ms")?

	head := "fn one() Int:\n    x := 1\n    return x\n\nfn two() Int:\n    return 2\n"
	expect_equal(
		reversed(head, files[0].hunks),
		"fn one() Int:\n    return 1\n\nfn two() Int:\n    return 2\n",
	)?
	expect_equal(files[0].touched_lines(), [2, 2, 3])?
	expect_true(reverse_error(head.replace("x := 1", "x := 9"), files[0].hunks))?

test "renames and non-diffs are rejected":
	expect_true(
		parse_error(
			"diff --git a/a.ms b/b.ms\nsimilarity index 100%\nrename from a.ms\nrename to b.ms\n"
		).contains("--no-renames")
	)?
	expect_true(parse_error("garbage\n").contains("not a unified diff"))?
	expect_true(parsed("").is_empty())?

test "the removed content of a deleted file is its base text":
	files := parsed(
		"--- a/gone.ms\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-fn a() Int:\n-    return 0\n"
	)
	expect_true(files[0].new.is_empty())?
	expect_equal(removed_content(files[0].hunks), "fn a() Int:\n    return 0\n")?

test "malformed hunks report their line":
	expect_equal(
		parse_error("--- a\n+++ b\n@@ -x +1 @@\n"),
		"diff line 3: malformed hunk range \"x\"",
	)?
	expect_equal(
		parse_error("--- a\n+++ a\n@@ -1 +1\n"),
		"diff line 3: malformed hunk header",
	)?
	expect_equal(
		parse_error("--- a\n+++ a\n@@ -1,2 +1,2 @@\n x"),
		"diff line 3: hunk is shorter than its header declares",
	)?
	expect_equal(
		parse_error("@@ -1 +1 @@\n"),
		"diff line 1: hunk before any file header",
	)?

test "hunk ranges reject signed, impossible and overflowing coordinates":
	ranges := [
		"-1", "+1", "1,-1", "1,+1", "0", "0,1", "-9223372036854775808",
		"9223372036854775807", "9223372036854775807,0", "9223372036854775806,2"
	]

	for range in ranges:
		for pair in [[range.clone(), "1"], ["1", range.clone()]]:
			message := parse_error(
				f"--- a/x.ms\n+++ b/x.ms\n@@ -{pair[0]} +{pair[1]} @@\n-old\n+new\n"
			)
			expect_true(message.starts_with("diff line 3: malformed hunk range"))?

test "zero-length ranges anchor the touched line":
	cases := [
		["0,0", "1", "+new\n", "new\n", "", "1"],
		["1", "0,0", "-old\n", "", "old\n", "1"],
		["1,0", "2", "+new\n", "same\nnew\n", "same\n", "2"],
	]

	for c in cases:
		files := parsed(f"--- a/x.ms\n+++ b/x.ms\n@@ -{c[0]} +{c[1]} @@\n{c[2]}")
		expect_equal(files[0].touched_lines(), [c[5].parse_int().get_or(0)])?
		expect_equal(reversed(c[3], files[0].hunks), c[4])?

	for c in [
		["9223372036854775806", "9223372036854775806", "-old\n+new\n"],
		["9223372036854775806,0", "9223372036854775806,0", ""],
	]:
		files := parsed(f"--- a/x.ms\n+++ b/x.ms\n@@ -{c[0]} +{c[1]} @@\n{c[2]}")
		expect_equal(files.length(), 1)?

test "surplus body lines are rejected":
	for extra in ["+extra\n", "-extra\n", " extra\n", "\n+extra\n"]:
		expect_true(
			not parse_error(
				f"--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n+new\n{extra}"
			).is_empty()
		)?

	repeated := "diff --git a/x.ms b/x.ms\n--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n+new\n--- a/x.ms\n+++ b/x.ms\n"
	expect_true(not parse_error(repeated).is_empty())?

test "old coordinates are checked and patch boundaries kept":
	cases := [
		["5", "1", "-old\n+new\n", "new\n"],
		["200", "0,0", "-old\n", ""],
		["1", "4,0", "-old\n", ""],
		["1,0", "1", "+new\n", "new\n"],
		["1", "2", "-old\n+new\n", "keep\nnew\n"],
	]

	for c in cases:
		files := parsed(f"--- a/x.ms\n+++ b/x.ms\n@@ -{c[0]} +{c[1]} @@\n{c[2]}")
		expect_true(reverse_error(c[3], files[0].hunks))?

	first := "--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n+new\n"
	second := "--- a/y.ms\n+++ b/y.ms\n@@ -1 +1 @@\n-before\n+after\n"
	expect_equal(parsed(f"{first}{second}").length(), 2)?
	expect_equal(reversed("new\n", parsed(f"{first}-- \n2.51.0\n")[0].hunks), "old\n")?

	mail := f"{first}-- \n+signature\n signer\n-next\nFrom next-message\nSubject: another change\ndiff --git a/y.ms b/y.ms\n{second}-- \n+second signature\n"
	files := parsed(mail)
	expect_equal(files.length(), 2)?
	expect_equal(reversed("new\n", files[0].hunks), "old\n")?
	expect_equal(reversed("after\n", files[1].hunks), "before\n")?

	multiple := parsed(
		"--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old_a\n+new_a\n@@ -3 +3 @@\n-old_b\n+new_b\n"
	)
	expect_equal(
		reversed("new_a\nkeep\nnew_b\n", multiple[0].hunks),
		"old_a\nkeep\nold_b\n",
	)?

	grows := parsed(
		"--- a/x.ms\n+++ b/x.ms\n@@ -1 +1,2 @@\n-old_a\n+new_a\n+extra\n@@ -3 +4 @@\n-old_b\n+new_b\n"
	)
	expect_equal(
		reversed("new_a\nextra\nkeep\nnew_b\n", grows[0].hunks),
		"old_a\nkeep\nold_b\n",
	)?

test "a mail stream without signatures splits into its files":
	patch := files().read("mail_without_signatures.patch", none).get_or(
		"".to_bytes()
	).decode_utf8().get_or("")
	files := parsed(patch)
	expect_equal(files.length(), 2)?
	expect_equal(files[0].path(), "x.ms")?
	expect_equal(files[1].path(), "y.ms")?

test "each side keeps its end-of-file state across split hunks":
	split := parsed(
		"--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n@@ -1,0 +2 @@\n+extra\n"
	)
	expect_equal(reversed("new\nextra\n", split[0].hunks), "old")?

	other := parsed(
		"--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n+new\n\\ No newline at end of file\n@@ -2 +1,0 @@\n-extra\n"
	)
	expect_equal(reversed("new", other[0].hunks), "old\nextra\n")?

	premature := "--- a/x.ms\n+++ b/x.ms\n@@ -1,2 +1,2 @@\n-old_a\n\\ No newline at end of file\n-old_b\n+new_a\n+new_b\n"
	expect_true(not parse_error(premature).is_empty())?

	before_tail := parsed(
		"--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n"
	)
	expect_true(reverse_error("new\nuntouched\n", before_tail[0].hunks))?

test "the end of the diff is not a context line":
	for newline in ["\n", "\r\n"]:
		for ending in ["", "\n"]:
			patch := f"--- a/x.ms\n+++ b/x.ms\n@@ -1,2 +1,2 @@\n same{ending}".replace(
				"\n",
				newline,
			)
			expect_equal(
				parse_error(patch),
				"diff line 3: hunk is shorter than its header declares",
			)?

		// A genuine empty context line still exists, with or without its space prefix.
		for blank in [" \n", "\n"]:
			patch := f"--- a/x.ms\n+++ b/x.ms\n@@ -1,2 +1,2 @@\n same\n{blank}".replace(
				"\n",
				newline,
			)
			files := parsed(patch)
			expect_equal(files[0].hunks[0].lines, [" same", " "])?
			expect_equal(reversed("same\n\n", files[0].hunks), "same\n\n")?

test "quoted git paths keep the exact filename bytes":
	pairs := [
		["caf\\303\\251.ms", "café.ms"],
		["\\360\\237\\246\\200.ms", "🦀.ms"],
		["a\\\"b\\\\c\\td\\ne.ms", "a\"b\\c\td\ne.ms"],
		["\\a\\b\\v\\f\\r.ms", "\u{7}\u{8}\u{b}\u{c}\r.ms"],
		["café.ms", "café.ms"],
		[" with spaces .ms ", " with spaces .ms "],
	]

	for pair in pairs:
		quoted := pair[0].clone()
		diff := f"diff --git \"a/{quoted}\" \"b/{quoted}\"\n--- \"a/{quoted}\"\n+++ \"b/{quoted}\"\n@@ -1 +1 @@\n-old\n+new\n"
		files := parsed(diff)
		expect_equal(files[0].old, pair[1])?
		expect_equal(files[0].new, pair[1])?
		expect_equal(reversed("new\n", files[0].hunks), "old\n")?

test "quoted paths keep additions, deletions and the rename rejection":
	added := parsed(
		"diff --git \"a/caf\\303\\251.ms\" \"b/caf\\303\\251.ms\"\n--- /dev/null\n+++ \"b/caf\\303\\251.ms\"\n@@ -0,0 +1 @@\n+new\n"
	)
	expect_true(added[0].old.is_empty())?
	expect_equal(added[0].new, "café.ms")?

	removed := parsed(
		"diff --git \"a/caf\\303\\251.ms\" \"b/caf\\303\\251.ms\"\n--- \"a/caf\\303\\251.ms\"\n+++ /dev/null\n@@ -1 +0,0 @@\n-old\n"
	)
	expect_true(removed[0].new.is_empty())?
	expect_equal(removed[0].old, "café.ms")?

	renamed := parse_error(
		"diff --git \"a/old.ms\" \"b/new.ms\"\n--- \"a/old.ms\"\n+++ \"b/new.ms\"\n"
	)
	expect_true(renamed.contains("renamed files are not supported"))?

	// `git diff -R` writes b/ before a/ for the same path.
	swapped := parsed(
		"diff --git b/src/x.ms a/src/x.ms\n--- b/src/x.ms\n+++ a/src/x.ms\n@@ -1 +1 @@\n-a\n+b\n"
	)
	expect_equal(swapped[0].old, "src/x.ms")?
	expect_equal(swapped[0].new, "src/x.ms")?

test "malformed quoted paths are errors, not guessed names":
	for path in [
		"\"a/unterminated", "\"a/embedded\"quote.ms\"", "\"a/bad\\q.ms\"",
		"\"a/short\\30.ms\"", "\"a/high\\400.ms\"", "\"a/invalid\\377.ms\"",
		"\"a/nul\\000.ms\""
	]:
		message := parse_error(f"diff --git a/x b/x\n--- {path}\n+++ b/x\n")
		expect_true(message.starts_with("diff line 2:"))?

test "unquoted git and plain paths keep their spelling":
	for header in ["diff --git a/café.ms b/café.ms\n", ""]:
		files := parsed(f"{header}--- a/café.ms\n+++ b/café.ms\n")
		expect_equal(files[0].path(), "café.ms")?

	literal := parsed(
		"--- \"literal.ms\"\told timestamp\n+++ \"literal.ms\"\tnew timestamp\n"
	)
	expect_equal(literal[0].path(), "\"literal.ms\"")?

	for path in [" space.ms", "space.ms ", "sp ace.ms"]:
		files := parsed(
			f"diff --git a/{path} b/{path}\n--- a/{path}\t\n+++ b/{path}\t\n"
		)
		expect_equal(files[0].old, path)?
		expect_equal(files[0].new, path)?

fn marker(present: Bool) String: if present: "" else: "\\ No newline at end of file\n"

test "reversing keeps the final newline of each side":
	for old_newline in [false, true]:
		for new_newline in [false, true]:
			patch := f"--- a/example.ms\n+++ b/example.ms\n@@ -1 +1 @@\n-old\n{marker(old_newline)}+new\n{marker(new_newline)}"
			files := parsed(patch)
			head := if new_newline: "new\n" else: "new"
			base := if old_newline: "old\n" else: "old"
			expect_equal(reversed(head, files[0].hunks), base)?

			wrong := if new_newline: "new" else: "new\n"
			expect_true(reverse_error(wrong, files[0].hunks))?
			if not new_newline: expect_true(reverse_error("new\ntail", files[0].hunks))?

test "reversing keeps unterminated context and the untouched tail":
	context := parsed(
		"--- a/x.ms\n+++ b/x.ms\n@@ -1,2 +1,2 @@\n-old\n+new\n tail\n\\ No newline at end of file\n"
	)
	expect_equal(reversed("new\ntail", context[0].hunks), "old\ntail")?

	plain := parsed("--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n+new\n")
	expect_equal(reversed("new\ntail", plain[0].hunks), "old\ntail")?
	expect_equal(reversed("new\ntail\n\n", plain[0].hunks), "old\ntail\n\n")?

test "added and deleted files keep empty and unterminated content":
	for newline in [false, true]:
		note := marker(newline)
		removed := parsed(f"--- a/x.ms\n+++ /dev/null\n@@ -1 +0,0 @@\n-old\n{note}")
		base := if newline: "old\n" else: "old"
		expect_equal(removed_content(removed[0].hunks), base)?
		expect_equal(reversed("", removed[0].hunks), base)?

		added := parsed(f"--- /dev/null\n+++ b/x.ms\n@@ -0,0 +1 @@\n+new\n{note}")
		head := if newline: "new\n" else: "new"
		expect_equal(reversed(head, added[0].hunks), "")?

	expect_equal(removed_content([]), "")?
	expect_equal(reversed("", []), "")?

test "a localized no-newline note keeps its structural meaning":
	files := parsed(
		"--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n\\ Sin salto de línea al final del archivo\n+new\n"
	)
	expect_equal(reversed("new\n", files[0].hunks), "old")?
