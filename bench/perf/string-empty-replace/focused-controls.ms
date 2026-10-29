import stdout from "@std/io.ms"
import clock from "@std/time.ms"

type Pattern:
    name: String
    text: String
    inserted: String
    old: String
    grown: String
    growing: String
    deleted: String

fn iterations_for(size: Int) Int:
    if size <= 128: return 1000000
    if size <= 16384: return 4096

    return 64

fn replace_sum(text: String, old: String, new: String, expected: String) Int:
    let result = text.replace(old, new)
    if result != expected: return -1

    return result.byte_length() + 17

fn measure(name: String, text: String, old: String, new: String, expected: String) Int:
    let expected_sum = expected.byte_length() + 17
    if replace_sum(text, old, new, expected) != expected_sum: return 1

    let iterations = iterations_for(text.byte_length())
    var checksum = 0
    let started = clock().now()
    for iteration in 0..iterations:
        checksum += replace_sum(text, old, new, expected)

    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected_sum * iterations: return 1

    let _written = stdout().write(
        "{name},{text.byte_length()},{iterations},{elapsed},{checksum}\n"
    )
    return 0

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\n")
    if measure("cache_ascii_noop", "x", "", "", "x") != 0: return 1
    if measure("cache_ascii_insert", "x", "", "-", ("-" + "x-")) != 0: return 1
    if measure("cache_ascii_miss", "x", "|", "!", "x") != 0: return 1
    if measure("cache_ascii_delete", "x", "x", "", "") != 0: return 1
    if measure("ascii_0_noop", "", "", "", "") != 0: return 1
    if measure("ascii_0_insert", "", "", "-", ("-" + "")) != 0: return 1
    if measure("ascii_0_delete", "", "b", "", "") != 0: return 1
    if measure("ascii_1_insert", "abC9", "", "-", ("-" + "a-b-C-9-")) != 0: return 1
    if (
        measure(
            "ascii_8_insert",
            "abC9abC9abC9abC9abC9abC9abC9abC9",
            "",
            "-",
            (
                "-"
                + "a-b-C-9-a-b-C-9-a-b-C-9-a-b-C-9-a-b-C-9-a-b-C-9-a-b-C-9-a-b-C-9-"
            )
        ) != 0
    ): return 1
    if (
        measure(
            "ascii_8_miss", "abC9abC9abC9abC9abC9abC9abC9abC9", "|", "!",
            "abC9abC9abC9abC9abC9abC9abC9abC9"
        ) != 0
    ): return 1
    if (
        measure(
            "ascii_4096_noop", "abC9".repeat(4096).get(), "", "",
            "abC9".repeat(4096).get()
        ) != 0
    ): return 1
    if (
        measure(
            "ascii_4096_insert", "abC9".repeat(4096).get(), "", "-",
            ("-" + "a-b-C-9-".repeat(4096).get())
        ) != 0
    ): return 1
    if (
        measure(
            "ascii_262144_insert", "abC9".repeat(262144).get(), "", "-",
            ("-" + "a-b-C-9-".repeat(262144).get())
        ) != 0
    ): return 1
    if measure("unicode_1_noop", "é日😀", "", "", "é日😀") != 0: return 1
    if measure("unicode_1_insert", "é日😀", "", "-", ("-" + "é-日-😀-")) != 0: return 1
    if (
        measure(
            "unicode_8_insert", "é日😀é日😀é日😀é日😀é日😀é日😀é日😀é日😀", "", "-",
            ("-" + "é-日-😀-é-日-😀-é-日-😀-é-日-😀-é-日-😀-é-日-😀-é-日-😀-é-日-😀-")
        ) != 0
    ): return 1
    if (
        measure(
            "unicode_8_grow", "é日😀é日😀é日😀é日😀é日😀é日😀é日😀é日😀", "日", "日日",
            "é日日😀é日日😀é日日😀é日日😀é日日😀é日日😀é日日😀é日日😀"
        ) != 0
    ): return 1
    if (
        measure(
            "unicode_4096_insert", "é日😀".repeat(4096).get(), "", "-",
            ("-" + "é-日-😀-".repeat(4096).get())
        ) != 0
    ): return 1
    if (
        measure(
            "unicode_262144_noop", "é日😀".repeat(262144).get(), "", "",
            "é日😀".repeat(262144).get()
        ) != 0
    ): return 1
    if (
        measure(
            "unicode_262144_insert", "é日😀".repeat(262144).get(), "", "-",
            ("-" + "é-日-😀-".repeat(262144).get())
        ) != 0
    ): return 1
    if (
        measure(
            "unicode_262144_grow", "é日😀".repeat(262144).get(), "日", "日日",
            "é日日😀".repeat(262144).get()
        ) != 0
    ): return 1
    if measure("nul_1_insert", "a\u{0}b", "", "-", ("-" + "a-\u{0}-b-")) != 0: return 1
    if (
        measure(
            "nul_8_noop", "a\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}b",
            "", "", "a\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}b"
        ) != 0
    ): return 1
    if (
        measure(
            "nul_8_insert",
            "a\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}b",
            "",
            "-",
            (
                "-"
                + "a-\u{0}-b-a-\u{0}-b-a-\u{0}-b-a-\u{0}-b-a-\u{0}-b-a-\u{0}-b-a-\u{0}-b-a-\u{0}-b-"
            )
        ) != 0
    ): return 1
    if (
        measure(
            "nul_8_miss", "a\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}b",
            "|", "!", "a\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}ba\u{0}b"
        ) != 0
    ): return 1
    if (
        measure(
            "nul_4096_insert", "a\u{0}b".repeat(4096).get(), "", "-",
            ("-" + "a-\u{0}-b-".repeat(4096).get())
        ) != 0
    ): return 1
    if (
        measure(
            "nul_4096_miss", "a\u{0}b".repeat(4096).get(), "|", "!",
            "a\u{0}b".repeat(4096).get()
        ) != 0
    ): return 1
    if (
        measure(
            "nul_4096_grow", "a\u{0}b".repeat(4096).get(), "\u{0}", "\u{0}\u{0}",
            "a\u{0}\u{0}b".repeat(4096).get()
        ) != 0
    ): return 1
    if (
        measure(
            "nul_262144_insert", "a\u{0}b".repeat(262144).get(), "", "-",
            ("-" + "a-\u{0}-b-".repeat(262144).get())
        ) != 0
    ): return 1

    return 0
