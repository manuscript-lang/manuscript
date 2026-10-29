import stdout from "@std/io.ms"
import clock from "@std/time.ms"

fn consume(result: String, expected: String) Int:
    if result != expected: return -1

    return result.byte_length() + 17

fn pad_sum(
    text: String,
    target: Int,
    padding: String,
    expected: String,
    at_start: Bool
) Int:
    if at_start: return consume(text.pad_start(target, padding), expected)

    return consume(text.pad_end(target, padding), expected)

fn measure(
    name: String,
    text: String,
    target: Int,
    padding: String,
    expected: String,
    at_start: Bool,
    iterations: Int
) Int:
    let expected_sum = expected.byte_length() + 17
    if pad_sum(text, target, padding, expected, at_start) != expected_sum: return 1

    var checksum = 0
    let started = clock().now()
    for iteration in 0..iterations:
        checksum += pad_sum(text, target, padding, expected, at_start)

    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected_sum * iterations: return 1

    let _written = stdout().write(
        "{name},{text.byte_length()},{iterations},{elapsed},{checksum}\n"
    )
    return 0

fn measure_changing(
    name: String,
    text: String,
    padding: String,
    targets: List[Int],
    expected: List[String],
    at_start: Bool,
    iterations: Int
) Int:
    if iterations % 4 != 0: return 1

    let t0 = targets.get(0)
    let t1 = targets.get(1)
    let t2 = targets.get(2)
    let t3 = targets.get(3)
    let e0 = expected.get(0)
    let e1 = expected.get(1)
    let e2 = expected.get(2)
    let e3 = expected.get(3)
    let expected_cycle = (
        e0.byte_length()
        + e1.byte_length()
        + e2.byte_length()
        + e3.byte_length()
        + 68
    )
    let warm = (
        pad_sum(text, t0, padding, e0, at_start)
        + pad_sum(text, t1, padding, e1, at_start)
        + pad_sum(text, t2, padding, e2, at_start)
        + pad_sum(text, t3, padding, e3, at_start)
    )
    if warm != expected_cycle: return 1

    var checksum = 0
    let started = clock().now()

    for cycle in 0..(iterations / 4):
        checksum += pad_sum(text, t0, padding, e0, at_start)
        checksum += pad_sum(text, t1, padding, e1, at_start)
        checksum += pad_sum(text, t2, padding, e2, at_start)
        checksum += pad_sum(text, t3, padding, e3, at_start)

    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected_cycle * (iterations / 4): return 1

    let _written = stdout().write(
        "{name},{text.byte_length()},{iterations},{elapsed},{checksum}\n"
    )
    return 0

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\n")
    if measure("start_byte_target1", "!", 1, "0", "!", true, 100000) != 0: return 1
    if measure("start_byte_target2", "!", 2, "0", ("0" + "!"), true, 100000) != 0: return 1
    if (
        measure(
            "start_byte_target15", "!", 15, "0", ("00000000000000" + "!"), true, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_byte_target16", "!", 16, "0", ("000000000000000" + "!"), true, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_byte_target17", "!", 17, "0", ("0000000000000000" + "!"), true,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_byte_target32", "!", 32, "0",
            ("0000000000000000000000000000000" + "!"), true, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_byte_target4096", "!", 4096, "0", ("0".repeat(4095).get() + "!"),
            true, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "start_byte_target1048576", "!", 1048576, "0",
            ("0".repeat(1048575).get() + "!"), true, 128
        ) != 0
    ): return 1
    if measure("start_ascii_target1", "!", 1, "ab", "!", true, 100000) != 0: return 1
    if measure("start_ascii_target2", "!", 2, "ab", ("a" + "!"), true, 100000) != 0: return 1
    if (
        measure(
            "start_ascii_target15", "!", 15, "ab", ("ababababababab" + "!"), true,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_ascii_target16", "!", 16, "ab", ("abababababababa" + "!"), true,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_ascii_target17", "!", 17, "ab", ("abababababababab" + "!"), true,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_ascii_target32", "!", 32, "ab",
            ("abababababababababababababababa" + "!"), true, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_ascii_target4096", "!", 4096, "ab",
            (("ab".repeat(2047).get() + "a") + "!"), true, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "start_ascii_target1048576", "!", 1048576, "ab",
            (("ab".repeat(524287).get() + "a") + "!"), true, 128
        ) != 0
    ): return 1
    if measure("start_unicode_target1", "!", 1, "é🙂", "!", true, 100000) != 0: return 1
    if measure("start_unicode_target2", "!", 2, "é🙂", ("é" + "!"), true, 100000) != 0: return 1
    if (
        measure(
            "start_unicode_target15", "!", 15, "é🙂", ("é🙂é🙂é🙂é🙂é🙂é🙂é🙂" + "!"), true,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_unicode_target16", "!", 16, "é🙂", ("é🙂é🙂é🙂é🙂é🙂é🙂é🙂é" + "!"), true,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_unicode_target17", "!", 17, "é🙂", ("é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂" + "!"), true,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_unicode_target32", "!", 32, "é🙂",
            ("é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é" + "!"), true, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_unicode_target4096", "!", 4096, "é🙂",
            (("é🙂".repeat(2047).get() + "é") + "!"), true, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "start_unicode_target1048576", "!", 1048576, "é🙂",
            (("é🙂".repeat(524287).get() + "é") + "!"), true, 128
        ) != 0
    ): return 1
    if measure("start_noop_empty_negative", "", -1, "ab", "", true, 100000) != 0: return 1
    if measure("start_noop_empty_empty_padding", "", 8192, "", "", true, 100000) != 0: return 1
    if measure("start_noop_tiny_negative", "é日😀", -1, "ab", "é日😀", true, 100000) != 0: return 1
    if (
        measure(
            "start_noop_tiny_empty_padding", "é日😀", 8195, "", "é日😀", true, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_noop_long_ascii_negative", "q".repeat(1048576).get(), -1, "ab",
            "q".repeat(1048576).get(), true, 128
        ) != 0
    ): return 1
    if (
        measure(
            "start_noop_long_ascii_empty_padding", "q".repeat(1048576).get(), 1056768,
            "", "q".repeat(1048576).get(), true, 128
        ) != 0
    ): return 1
    if (
        measure(
            "start_noop_long_unicode_negative", "é日😀".repeat(116508).get(), -1, "ab",
            "é日😀".repeat(116508).get(), true, 128
        ) != 0
    ): return 1
    if (
        measure(
            "start_noop_long_unicode_empty_padding", "é日😀".repeat(116508).get(), 357716,
            "", "é日😀".repeat(116508).get(), true, 128
        ) != 0
    ): return 1
    if measure("start_positive_shorter", "é日😀", 2, "ab", "é日😀", true, 100000) != 0: return 1
    if measure("start_empty_text_byte", "", 1, "0", "0", true, 100000) != 0: return 1
    if measure("start_empty_text_unicode_small", "", 1, "é🙂", "é", true, 100000) != 0: return 1
    if (
        measure(
            "start_empty_text_unicode_heap", "", 17, "é🙂", "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é", true,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_mixed_text_unicode_target4", "é日😀", 4, "é🙂", ("é" + "é日😀"), true,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_mixed_text_unicode_target5", "é日😀", 5, "é🙂", ("é🙂" + "é日😀"), true,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_mixed_text_unicode_target17", "é日😀", 17, "é🙂",
            ("é🙂é🙂é🙂é🙂é🙂é🙂é🙂" + "é日😀"), true, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_mixed_text_ascii_target4", "é日😀", 4, "ab", ("a" + "é日😀"), true,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_large_input_ascii_add3", "q".repeat(1048576).get(), 1048579, "é🙂",
            ("é🙂é" + "q".repeat(1048576).get()), true, 128
        ) != 0
    ): return 1
    if (
        measure(
            "start_large_input_unicode_add3", "é日😀".repeat(116508).get(), 349527, "é🙂",
            ("é🙂é" + "é日😀".repeat(116508).get()), true, 128
        ) != 0
    ): return 1
    if measure("start_nul_target1", "", 1, "x\u{0}y", "x", true, 100000) != 0: return 1
    if measure("start_nul_target2", "", 2, "x\u{0}y", "x\u{0}", true, 100000) != 0: return 1
    if (
        measure(
            "start_nul_target16", "", 16, "x\u{0}y",
            "x\u{0}yx\u{0}yx\u{0}yx\u{0}yx\u{0}yx", true, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "start_nul_target17", "", 17, "x\u{0}y",
            "x\u{0}yx\u{0}yx\u{0}yx\u{0}yx\u{0}yx\u{0}", true, 100000
        ) != 0
    ): return 1
    if (
        measure_changing(
            "start_changing_byte_grow_shrink",
            "!",
            "0",
            [32, 4096, 64, 1048576],
            [
                ("0000000000000000000000000000000" + "!"),
                ("0".repeat(4095).get() + "!"),
                (
                    "000000000000000000000000000000000000000000000000000000000000000"
                    + "!"
                ),
                ("0".repeat(1048575).get() + "!")
            ],
            true,
            128
        ) != 0
    ): return 1
    if (
        measure_changing(
            "start_changing_byte_shrink_grow",
            "!",
            "0",
            [1048576, 64, 4096, 32],
            [
                ("0".repeat(1048575).get() + "!"),
                (
                    "000000000000000000000000000000000000000000000000000000000000000"
                    + "!"
                ),
                ("0".repeat(4095).get() + "!"),
                ("0000000000000000000000000000000" + "!")
            ],
            true,
            128
        ) != 0
    ): return 1
    if (
        measure_changing(
            "start_changing_unicode_grow_shrink",
            "!",
            "é🙂",
            [32, 4096, 64, 1048576],
            [
                ("é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é" + "!"),
                (("é🙂".repeat(2047).get() + "é") + "!"),
                (
                    "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é"
                    + "!"
                ),
                (("é🙂".repeat(524287).get() + "é") + "!")
            ],
            true,
            128
        ) != 0
    ): return 1
    if measure("end_byte_target1", "!", 1, "0", "!", false, 100000) != 0: return 1
    if measure("end_byte_target2", "!", 2, "0", ("!" + "0"), false, 100000) != 0: return 1
    if (
        measure(
            "end_byte_target15", "!", 15, "0", ("!" + "00000000000000"), false, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_byte_target16", "!", 16, "0", ("!" + "000000000000000"), false, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_byte_target17", "!", 17, "0", ("!" + "0000000000000000"), false, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_byte_target32", "!", 32, "0",
            ("!" + "0000000000000000000000000000000"), false, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_byte_target4096", "!", 4096, "0", ("!" + "0".repeat(4095).get()),
            false, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "end_byte_target1048576", "!", 1048576, "0",
            ("!" + "0".repeat(1048575).get()), false, 128
        ) != 0
    ): return 1
    if measure("end_ascii_target1", "!", 1, "ab", "!", false, 100000) != 0: return 1
    if measure("end_ascii_target2", "!", 2, "ab", ("!" + "a"), false, 100000) != 0: return 1
    if (
        measure(
            "end_ascii_target15", "!", 15, "ab", ("!" + "ababababababab"), false, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_ascii_target16", "!", 16, "ab", ("!" + "abababababababa"), false,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_ascii_target17", "!", 17, "ab", ("!" + "abababababababab"), false,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_ascii_target32", "!", 32, "ab",
            ("!" + "abababababababababababababababa"), false, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_ascii_target4096", "!", 4096, "ab",
            ("!" + ("ab".repeat(2047).get() + "a")), false, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "end_ascii_target1048576", "!", 1048576, "ab",
            ("!" + ("ab".repeat(524287).get() + "a")), false, 128
        ) != 0
    ): return 1
    if measure("end_unicode_target1", "!", 1, "é🙂", "!", false, 100000) != 0: return 1
    if measure("end_unicode_target2", "!", 2, "é🙂", ("!" + "é"), false, 100000) != 0: return 1
    if (
        measure(
            "end_unicode_target15", "!", 15, "é🙂", ("!" + "é🙂é🙂é🙂é🙂é🙂é🙂é🙂"), false,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_unicode_target16", "!", 16, "é🙂", ("!" + "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é"), false,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_unicode_target17", "!", 17, "é🙂", ("!" + "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂"), false,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_unicode_target32", "!", 32, "é🙂",
            ("!" + "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é"), false, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_unicode_target4096", "!", 4096, "é🙂",
            ("!" + ("é🙂".repeat(2047).get() + "é")), false, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "end_unicode_target1048576", "!", 1048576, "é🙂",
            ("!" + ("é🙂".repeat(524287).get() + "é")), false, 128
        ) != 0
    ): return 1
    if measure("end_noop_empty_negative", "", -1, "ab", "", false, 100000) != 0: return 1
    if measure("end_noop_empty_empty_padding", "", 8192, "", "", false, 100000) != 0: return 1
    if measure("end_noop_tiny_negative", "é日😀", -1, "ab", "é日😀", false, 100000) != 0: return 1
    if (
        measure(
            "end_noop_tiny_empty_padding", "é日😀", 8195, "", "é日😀", false, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_noop_long_ascii_negative", "q".repeat(1048576).get(), -1, "ab",
            "q".repeat(1048576).get(), false, 128
        ) != 0
    ): return 1
    if (
        measure(
            "end_noop_long_ascii_empty_padding", "q".repeat(1048576).get(), 1056768, "",
            "q".repeat(1048576).get(), false, 128
        ) != 0
    ): return 1
    if (
        measure(
            "end_noop_long_unicode_negative", "é日😀".repeat(116508).get(), -1, "ab",
            "é日😀".repeat(116508).get(), false, 128
        ) != 0
    ): return 1
    if (
        measure(
            "end_noop_long_unicode_empty_padding", "é日😀".repeat(116508).get(), 357716,
            "", "é日😀".repeat(116508).get(), false, 128
        ) != 0
    ): return 1
    if measure("end_positive_shorter", "é日😀", 2, "ab", "é日😀", false, 100000) != 0: return 1
    if measure("end_empty_text_byte", "", 1, "0", "0", false, 100000) != 0: return 1
    if measure("end_empty_text_unicode_small", "", 1, "é🙂", "é", false, 100000) != 0: return 1
    if (
        measure(
            "end_empty_text_unicode_heap", "", 17, "é🙂", "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é", false,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_mixed_text_unicode_target4", "é日😀", 4, "é🙂", ("é日😀" + "é"), false,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_mixed_text_unicode_target5", "é日😀", 5, "é🙂", ("é日😀" + "é🙂"), false,
            100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_mixed_text_unicode_target17", "é日😀", 17, "é🙂",
            ("é日😀" + "é🙂é🙂é🙂é🙂é🙂é🙂é🙂"), false, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_mixed_text_ascii_target4", "é日😀", 4, "ab", ("é日😀" + "a"), false, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_large_input_ascii_add3", "q".repeat(1048576).get(), 1048579, "é🙂",
            ("q".repeat(1048576).get() + "é🙂é"), false, 128
        ) != 0
    ): return 1
    if (
        measure(
            "end_large_input_unicode_add3", "é日😀".repeat(116508).get(), 349527, "é🙂",
            ("é日😀".repeat(116508).get() + "é🙂é"), false, 128
        ) != 0
    ): return 1
    if measure("end_nul_target1", "", 1, "x\u{0}y", "x", false, 100000) != 0: return 1
    if measure("end_nul_target2", "", 2, "x\u{0}y", "x\u{0}", false, 100000) != 0: return 1
    if (
        measure(
            "end_nul_target16", "", 16, "x\u{0}y",
            "x\u{0}yx\u{0}yx\u{0}yx\u{0}yx\u{0}yx", false, 100000
        ) != 0
    ): return 1
    if (
        measure(
            "end_nul_target17", "", 17, "x\u{0}y",
            "x\u{0}yx\u{0}yx\u{0}yx\u{0}yx\u{0}yx\u{0}", false, 100000
        ) != 0
    ): return 1
    if (
        measure_changing(
            "end_changing_byte_grow_shrink",
            "!",
            "0",
            [32, 4096, 64, 1048576],
            [
                ("!" + "0000000000000000000000000000000"),
                ("!" + "0".repeat(4095).get()),
                (
                    "!"
                    + "000000000000000000000000000000000000000000000000000000000000000"
                ),
                ("!" + "0".repeat(1048575).get())
            ],
            false,
            128
        ) != 0
    ): return 1
    if (
        measure_changing(
            "end_changing_byte_shrink_grow",
            "!",
            "0",
            [1048576, 64, 4096, 32],
            [
                ("!" + "0".repeat(1048575).get()),
                (
                    "!"
                    + "000000000000000000000000000000000000000000000000000000000000000"
                ),
                ("!" + "0".repeat(4095).get()),
                ("!" + "0000000000000000000000000000000")
            ],
            false,
            128
        ) != 0
    ): return 1
    if (
        measure_changing(
            "end_changing_unicode_grow_shrink",
            "!",
            "é🙂",
            [32, 4096, 64, 1048576],
            [
                ("!" + "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é"),
                ("!" + ("é🙂".repeat(2047).get() + "é")),
                (
                    "!"
                    + "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é"
                ),
                ("!" + ("é🙂".repeat(524287).get() + "é"))
            ],
            false,
            128
        ) != 0
    ): return 1

    return 0
