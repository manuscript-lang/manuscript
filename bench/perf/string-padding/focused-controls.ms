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
    if measure("start_byte_target1", "!", 1, "0", "!", true, 1000000) != 0: return 1
    if measure("start_byte_target2", "!", 2, "0", ("0" + "!"), true, 1000000) != 0: return 1
    if measure("start_ascii_target1", "!", 1, "ab", "!", true, 1000000) != 0: return 1
    if (
        measure(
            "start_ascii_target17", "!", 17, "ab", ("abababababababab" + "!"), true,
            1000000
        ) != 0
    ): return 1
    if measure("start_unicode_target1", "!", 1, "é🙂", "!", true, 1000000) != 0: return 1
    if (
        measure(
            "start_unicode_target17", "!", 17, "é🙂", ("é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂" + "!"), true,
            1000000
        ) != 0
    ): return 1
    if measure("start_noop_empty_negative", "", -1, "ab", "", true, 1000000) != 0: return 1
    if measure("start_noop_empty_empty_padding", "", 8192, "", "", true, 1000000) != 0: return 1
    if measure("start_noop_tiny_negative", "é日😀", -1, "ab", "é日😀", true, 1000000) != 0: return 1
    if (
        measure(
            "start_noop_tiny_empty_padding", "é日😀", 8195, "", "é日😀", true, 1000000
        ) != 0
    ): return 1
    if (
        measure(
            "start_noop_long_ascii_negative", "q".repeat(1048576).get(), -1, "ab",
            "q".repeat(1048576).get(), true, 256
        ) != 0
    ): return 1
    if (
        measure(
            "start_noop_long_ascii_empty_padding", "q".repeat(1048576).get(), 1056768,
            "", "q".repeat(1048576).get(), true, 256
        ) != 0
    ): return 1
    if (
        measure(
            "start_noop_long_unicode_negative", "é日😀".repeat(116508).get(), -1, "ab",
            "é日😀".repeat(116508).get(), true, 256
        ) != 0
    ): return 1
    if (
        measure(
            "start_noop_long_unicode_empty_padding", "é日😀".repeat(116508).get(), 357716,
            "", "é日😀".repeat(116508).get(), true, 256
        ) != 0
    ): return 1
    if measure("start_positive_shorter", "é日😀", 2, "ab", "é日😀", true, 1000000) != 0: return 1
    if measure("start_empty_text_byte", "", 1, "0", "0", true, 1000000) != 0: return 1
    if measure("start_empty_text_unicode_small", "", 1, "é🙂", "é", true, 1000000) != 0: return 1
    if (
        measure(
            "start_empty_text_unicode_heap", "", 17, "é🙂", "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é", true,
            1000000
        ) != 0
    ): return 1
    if (
        measure(
            "start_mixed_text_unicode_target4", "é日😀", 4, "é🙂", ("é" + "é日😀"), true,
            1000000
        ) != 0
    ): return 1
    if (
        measure(
            "start_mixed_text_unicode_target5", "é日😀", 5, "é🙂", ("é🙂" + "é日😀"), true,
            1000000
        ) != 0
    ): return 1
    if (
        measure(
            "start_mixed_text_unicode_target17", "é日😀", 17, "é🙂",
            ("é🙂é🙂é🙂é🙂é🙂é🙂é🙂" + "é日😀"), true, 1000000
        ) != 0
    ): return 1
    if (
        measure(
            "start_mixed_text_ascii_target4", "é日😀", 4, "ab", ("a" + "é日😀"), true,
            1000000
        ) != 0
    ): return 1
    if measure("start_nul_target1", "", 1, "x\u{0}y", "x", true, 1000000) != 0: return 1
    if measure("start_nul_target2", "", 2, "x\u{0}y", "x\u{0}", true, 1000000) != 0: return 1
    if measure("end_byte_target1", "!", 1, "0", "!", false, 1000000) != 0: return 1
    if measure("end_byte_target2", "!", 2, "0", ("!" + "0"), false, 1000000) != 0: return 1
    if measure("end_ascii_target1", "!", 1, "ab", "!", false, 1000000) != 0: return 1
    if (
        measure(
            "end_ascii_target17", "!", 17, "ab", ("!" + "abababababababab"), false,
            1000000
        ) != 0
    ): return 1
    if (
        measure(
            "end_ascii_target4096", "!", 4096, "ab",
            ("!" + ("ab".repeat(2047).get() + "a")), false, 65536
        ) != 0
    ): return 1
    if measure("end_unicode_target1", "!", 1, "é🙂", "!", false, 1000000) != 0: return 1
    if (
        measure(
            "end_unicode_target17", "!", 17, "é🙂", ("!" + "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂"), false,
            1000000
        ) != 0
    ): return 1
    if (
        measure(
            "end_unicode_target4096", "!", 4096, "é🙂",
            ("!" + ("é🙂".repeat(2047).get() + "é")), false, 65536
        ) != 0
    ): return 1
    if measure("end_noop_empty_negative", "", -1, "ab", "", false, 1000000) != 0: return 1
    if measure("end_noop_empty_empty_padding", "", 8192, "", "", false, 1000000) != 0: return 1
    if measure("end_noop_tiny_negative", "é日😀", -1, "ab", "é日😀", false, 1000000) != 0: return 1
    if (
        measure(
            "end_noop_tiny_empty_padding", "é日😀", 8195, "", "é日😀", false, 1000000
        ) != 0
    ): return 1
    if (
        measure(
            "end_noop_long_ascii_negative", "q".repeat(1048576).get(), -1, "ab",
            "q".repeat(1048576).get(), false, 256
        ) != 0
    ): return 1
    if (
        measure(
            "end_noop_long_ascii_empty_padding", "q".repeat(1048576).get(), 1056768, "",
            "q".repeat(1048576).get(), false, 256
        ) != 0
    ): return 1
    if (
        measure(
            "end_noop_long_unicode_negative", "é日😀".repeat(116508).get(), -1, "ab",
            "é日😀".repeat(116508).get(), false, 256
        ) != 0
    ): return 1
    if (
        measure(
            "end_noop_long_unicode_empty_padding", "é日😀".repeat(116508).get(), 357716,
            "", "é日😀".repeat(116508).get(), false, 256
        ) != 0
    ): return 1
    if measure("end_positive_shorter", "é日😀", 2, "ab", "é日😀", false, 1000000) != 0: return 1
    if measure("end_empty_text_byte", "", 1, "0", "0", false, 1000000) != 0: return 1
    if measure("end_empty_text_unicode_small", "", 1, "é🙂", "é", false, 1000000) != 0: return 1
    if (
        measure(
            "end_empty_text_unicode_heap", "", 17, "é🙂", "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é", false,
            1000000
        ) != 0
    ): return 1
    if (
        measure(
            "end_mixed_text_unicode_target4", "é日😀", 4, "é🙂", ("é日😀" + "é"), false,
            1000000
        ) != 0
    ): return 1
    if (
        measure(
            "end_mixed_text_unicode_target5", "é日😀", 5, "é🙂", ("é日😀" + "é🙂"), false,
            1000000
        ) != 0
    ): return 1
    if (
        measure(
            "end_mixed_text_unicode_target17", "é日😀", 17, "é🙂",
            ("é日😀" + "é🙂é🙂é🙂é🙂é🙂é🙂é🙂"), false, 1000000
        ) != 0
    ): return 1
    if (
        measure(
            "end_mixed_text_ascii_target4", "é日😀", 4, "ab", ("é日😀" + "a"), false,
            1000000
        ) != 0
    ): return 1
    if measure("end_nul_target1", "", 1, "x\u{0}y", "x", false, 1000000) != 0: return 1
    if (
        measure(
            "end_nul_target16", "", 16, "x\u{0}y",
            "x\u{0}yx\u{0}yx\u{0}yx\u{0}yx\u{0}yx", false, 1000000
        ) != 0
    ): return 1

    return 0
