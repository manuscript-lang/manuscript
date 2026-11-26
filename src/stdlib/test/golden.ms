// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write

import (
	Bytes from "@std/bytes.ms",
	environment from "@std/os/env.ms",
	create_directory, read_file, write_file from "@std/os/fs.ms",
	dirname from "@std/os/path.ms",
	fail from "@std/test/test.ms",
)

/*
Golden files: expected output kept in a file next to the test and compared by `expect_golden`.
Run the tests with `MS_UPDATE_GOLDEN=1` to write the actual output to the files instead of comparing,
review the changes in version control, then run again without it.
A missing golden file fails with a hint to update; it is created only when updating.
*/
fn updating() Bool {
	env := environment().get_or(Map[String, String]())
	value := env.get("MS_UPDATE_GOLDEN")
	if value != null { return value != "" and value != "0" }

	return false
}

// Internal: names the first line where two texts differ, with both sides, so a
// mismatch is readable without a diff tool.
fn first_difference(expected, actual String) String {
	want := expected.split("\n")
	got := actual.split("\n")
	var line = 0

	while line < want.length() and line < got.length() {
		if want[line] != got[line] {
			return f"""
                line {line + 1}:
                  golden: {want[line]}
                  actual: {got[line]}
                """
		}

		line += 1
	}

	return f"line {line + 1}: golden has {want.length()} lines, actual has {got.length()}"
}

// Compares `actual` with the text in the golden file at `path`. Under
// `MS_UPDATE_GOLDEN=1` it rewrites the file instead. A mismatch names the file and the
// first differing line.
export fn expect_golden(path, actual String) Void! {
	if updating() {
		create_directory(dirname(path), true)?
		write_file(path, actual, replace: true).wait()?
		return ok()
	}

	stored := read_file(path).wait()
	if stored.is_error() {
		return fail(
			f"golden file {path} is missing or unreadable; run with MS_UPDATE_GOLDEN=1 to create it"
		)
	}

	text := stored.get().decode_utf8()
	expected := text

	if expected != null {
		if expected == actual { return ok() }
		return fail(
			f"{path} differs from the output at {first_difference(expected, actual)}\nrun with MS_UPDATE_GOLDEN=1 to accept the output"
		)
	}

	return fail(f"golden file {path} is not UTF-8; use expect_golden_bytes")
}

// Byte-for-byte version of `expect_golden`. A mismatch names the first differing
// offset.
export fn expect_golden_bytes(path String, actual Bytes) Void! {
	if updating() {
		create_directory(dirname(path), true)?
		write_file(path, actual, replace: true).wait()?
		return ok()
	}

	stored := read_file(path).wait()
	if stored.is_error() {
		return fail(
			f"golden file {path} is missing or unreadable; run with MS_UPDATE_GOLDEN=1 to create it"
		)
	}

	expected := stored.get()
	if expected == actual { return ok() }

	var offset = 0
	shared := if expected.length() < actual.length() { expected.length() } else { actual.length() }
	while offset < shared and expected.get(offset) == actual.get(offset) {
		offset += 1
	}
	return fail(
		f"{path} differs from the output at byte {offset} (golden {expected.length()} bytes, actual {actual.length()})\nrun with MS_UPDATE_GOLDEN=1 to accept the output"
	)
}
