import Bytes from "@std/bytes.ms"
import environment from "@std/os/process.ms"
import (
    create_directory,
    dirname,
    join,
    read_file,
    write_file,
    write_file_bytes
) from "@std/os/fs.ms"
import fail from "@std/test/test.ms"

# Golden files: expected output kept in a file next to the test and compared by `expect_golden`.
# Run the tests with `MS_UPDATE_GOLDEN=1` to write the actual output to the files instead of comparing;
# review the changes with your version control, then run again without it.
# A missing golden file fails with the update hint; it is created only when updating.
fn updating() Bool:
    let env = environment().get(Map[String, String]())
    if let value = env.get("MS_UPDATE_GOLDEN"):
        return value != "" and value != "0"

    return false

# Names the first line where two texts differ, with both sides, so a mismatch is readable without a diff tool.
fn first_difference(expected: String, actual: String) String:
    let want = expected.split("\n")
    let got = actual.split("\n")
    var line = 0

    while line < want.length() and line < got.length():
        if want[line] != got[line]:
            return "line {line + 1}:\n  golden: {want[line]}\n  actual: {got[line]}"

        line += 1

    return "line {line + 1}: golden has {want.length()} lines, actual has {got.length()}"

# Compares `actual` with the text in the golden file at `path`, or rewrites the file under `MS_UPDATE_GOLDEN=1`.
# The failure names the file and the first differing line.
export fn expect_golden(path: String, actual: String) Unit!:
    if updating():
        try create_directory(dirname(path), true)
        try write_file(path, actual, true)
        return ok(unit)

    let stored = read_file(path, none)
    if stored.is_error():
        return fail(
            "golden file {path} is missing or unreadable; run with MS_UPDATE_GOLDEN=1 to create it"
        )

    let expected = stored.get().decode_utf8()
    if expected.is_none():
        return fail("golden file {path} is not UTF-8; use expect_golden_bytes")
    if expected.get() == actual:
        return ok(unit)

    return fail(
        "{path} differs from the output at {first_difference(expected.get(), actual)}\nrun with MS_UPDATE_GOLDEN=1 to accept the output"
    )

# Byte-for-byte version of `expect_golden`; the failure names the first differing offset.
export fn expect_golden_bytes(path: String, actual: Bytes) Unit!:
    if updating():
        try create_directory(dirname(path), true)
        try write_file_bytes(path, actual, true)
        return ok(unit)

    let stored = read_file(path, none)
    if stored.is_error():
        return fail(
            "golden file {path} is missing or unreadable; run with MS_UPDATE_GOLDEN=1 to create it"
        )

    let expected = stored.get()
    if expected == actual:
        return ok(unit)

    var offset = 0
    let shared = if expected.length() < actual.length(): expected.length() else: actual.length()
    while offset < shared and expected.get(offset) == actual.get(offset):
        offset += 1
    return fail(
        "{path} differs from the output at byte {offset} (golden {expected.length()} bytes, actual {actual.length()})\nrun with MS_UPDATE_GOLDEN=1 to accept the output"
    )
