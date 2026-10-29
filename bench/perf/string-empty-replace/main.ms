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
    if size <= 128: return 200000
    if size <= 16384: return 4096

    return 32

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
    if measure("cache_ascii_insert", "x", "", "-", "-x-") != 0: return 1
    if measure("cache_ascii_miss", "x", "|", "!", "x") != 0: return 1
    if measure("cache_ascii_grow", "x", "x", "XX", "XX") != 0: return 1
    if measure("cache_ascii_delete", "x", "x", "", "") != 0: return 1

    for pattern in [
        Pattern("ascii", "abC9", "a-b-C-9-", "b", "BB", "aBBC9", "aC9"),
        Pattern("unicode", "é日😀", "é-日-😀-", "日", "日日", "é日日😀", "é😀"),
        Pattern(
            "nul", "a\u{0}b", "a-\u{0}-b-", "\u{0}", "\u{0}\u{0}", "a\u{0}\u{0}b", "ab"
        )
    ]:
        for copies in [0, 1, 8, 4096, 262144]:
            if copies == 0 and pattern.name != "ascii": continue

            let text = pattern.text.repeat(copies).get()
            if measure("{pattern.name}_{copies}_noop", text, "", "", text) != 0: return 1

            let inserted = "-" + pattern.inserted.repeat(copies).get()
            if measure("{pattern.name}_{copies}_insert", text, "", "-", inserted) != 0: return 1
            if measure("{pattern.name}_{copies}_miss", text, "|", "!", text) != 0: return 1

            let grown = pattern.growing.repeat(copies).get()
            if (
                measure(
                    "{pattern.name}_{copies}_grow", text, pattern.old, pattern.grown,
                    grown
                ) != 0
            ): return 1

            let deleted = pattern.deleted.repeat(copies).get()
            if (
                measure(
                    "{pattern.name}_{copies}_delete", text, pattern.old, "", deleted
                ) != 0
            ): return 1

    return 0
