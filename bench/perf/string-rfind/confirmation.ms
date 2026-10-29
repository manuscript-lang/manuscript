import stdout from "@std/io.ms"
import clock from "@std/time.ms"

fn iterations_for(size: Int) Int:
    if size <= 128: return 3000000
    if size >= 262144: return 256
    if size >= 16384: return 4096
    if size >= 4096: return 65536

    return 100000

fn search_sum(text: String, needle: String, expected: Int) Int:
    let actual = text.last_index_of(needle).get(-1)
    if actual != expected: return -1

    return actual + 19

fn measure(name: String, text: String, needle: String, expected: Int) Int:
    let expected_sum = expected + 19
    if search_sum(text, needle, expected) != expected_sum: return 1

    let iterations = iterations_for(text.byte_length())
    var checksum = 0
    let started = clock().now()
    for iteration in 0..iterations:
        checksum += search_sum(text, needle, expected)

    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected_sum * iterations: return 1

    let _written = stdout().write(
        "{name},{text.byte_length()},{iterations},{elapsed},{checksum}\n"
    )
    return 0

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\n")
    if measure("one_miss_n0", "x".repeat(0).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n0", "x".repeat(0).get(), "", 0) != 0: return 1
    if measure("one_miss_n1", "x".repeat(1).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n1", "x".repeat(1).get(), "", 1) != 0: return 1
    if measure("one_end_n1", "x".repeat(0).get() + "!", "!", 0) != 0: return 1
    if measure("one_miss_n2", "x".repeat(2).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n2", "x".repeat(2).get(), "", 2) != 0: return 1
    if measure("one_end_n2", "x".repeat(1).get() + "!", "!", 1) != 0: return 1
    if measure("one_start_n2", "!" + "x".repeat(1).get(), "!", 0) != 0: return 1
    if measure("one_miss_n7", "x".repeat(7).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n7", "x".repeat(7).get(), "", 7) != 0: return 1
    if measure("one_end_n7", "x".repeat(6).get() + "!", "!", 6) != 0: return 1
    if measure("one_start_n7", "!" + "x".repeat(6).get(), "!", 0) != 0: return 1
    if (
        measure(
            "one_middle_n7", "x".repeat(3).get() + "!" + "x".repeat(3).get(), "!", 3
        ) != 0
    ): return 1
    if measure("one_miss_n15", "x".repeat(15).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n15", "x".repeat(15).get(), "", 15) != 0: return 1
    if measure("one_end_n15", "x".repeat(14).get() + "!", "!", 14) != 0: return 1
    if measure("one_start_n15", "!" + "x".repeat(14).get(), "!", 0) != 0: return 1
    if (
        measure(
            "one_middle_n15", "x".repeat(7).get() + "!" + "x".repeat(7).get(), "!", 7
        ) != 0
    ): return 1
    if measure("one_miss_n16", "x".repeat(16).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n16", "x".repeat(16).get(), "", 16) != 0: return 1
    if measure("one_end_n16", "x".repeat(15).get() + "!", "!", 15) != 0: return 1
    if measure("one_start_n16", "!" + "x".repeat(15).get(), "!", 0) != 0: return 1
    if (
        measure(
            "one_middle_n16", "x".repeat(8).get() + "!" + "x".repeat(7).get(), "!", 8
        ) != 0
    ): return 1
    if measure("one_miss_n31", "x".repeat(31).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n31", "x".repeat(31).get(), "", 31) != 0: return 1
    if measure("one_end_n31", "x".repeat(30).get() + "!", "!", 30) != 0: return 1
    if measure("one_start_n31", "!" + "x".repeat(30).get(), "!", 0) != 0: return 1
    if (
        measure(
            "one_middle_n31", "x".repeat(15).get() + "!" + "x".repeat(15).get(), "!", 15
        ) != 0
    ): return 1
    if measure("one_miss_n32", "x".repeat(32).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n32", "x".repeat(32).get(), "", 32) != 0: return 1
    if measure("one_end_n32", "x".repeat(31).get() + "!", "!", 31) != 0: return 1
    if measure("one_start_n32", "!" + "x".repeat(31).get(), "!", 0) != 0: return 1
    if (
        measure(
            "one_middle_n32", "x".repeat(16).get() + "!" + "x".repeat(15).get(), "!", 16
        ) != 0
    ): return 1
    if measure("one_miss_n63", "x".repeat(63).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n63", "x".repeat(63).get(), "", 63) != 0: return 1
    if measure("one_end_n63", "x".repeat(62).get() + "!", "!", 62) != 0: return 1
    if measure("one_start_n63", "!" + "x".repeat(62).get(), "!", 0) != 0: return 1
    if (
        measure(
            "one_middle_n63", "x".repeat(31).get() + "!" + "x".repeat(31).get(), "!", 31
        ) != 0
    ): return 1
    if measure("one_miss_n64", "x".repeat(64).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n64", "x".repeat(64).get(), "", 64) != 0: return 1
    if measure("one_end_n64", "x".repeat(63).get() + "!", "!", 63) != 0: return 1
    if measure("one_start_n64", "!" + "x".repeat(63).get(), "!", 0) != 0: return 1
    if (
        measure(
            "one_middle_n64", "x".repeat(32).get() + "!" + "x".repeat(31).get(), "!", 32
        ) != 0
    ): return 1
    if measure("one_miss_n65", "x".repeat(65).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n65", "x".repeat(65).get(), "", 65) != 0: return 1
    if measure("one_end_n65", "x".repeat(64).get() + "!", "!", 64) != 0: return 1
    if measure("one_start_n65", "!" + "x".repeat(64).get(), "!", 0) != 0: return 1
    if (
        measure(
            "one_middle_n65", "x".repeat(32).get() + "!" + "x".repeat(32).get(), "!", 32
        ) != 0
    ): return 1
    if measure("one_miss_n128", "x".repeat(128).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n128", "x".repeat(128).get(), "", 128) != 0: return 1
    if measure("one_end_n128", "x".repeat(127).get() + "!", "!", 127) != 0: return 1
    if measure("one_start_n128", "!" + "x".repeat(127).get(), "!", 0) != 0: return 1
    if (
        measure(
            "one_middle_n128", "x".repeat(64).get() + "!" + "x".repeat(63).get(), "!",
            64
        ) != 0
    ): return 1
    if measure("one_miss_n4096", "x".repeat(4096).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n4096", "x".repeat(4096).get(), "", 4096) != 0: return 1
    if measure("one_end_n4096", "x".repeat(4095).get() + "!", "!", 4095) != 0: return 1
    if measure("one_start_n4096", "!" + "x".repeat(4095).get(), "!", 0) != 0: return 1
    if (
        measure(
            "one_middle_n4096", "x".repeat(2048).get() + "!" + "x".repeat(2047).get(),
            "!", 2048
        ) != 0
    ): return 1
    if measure("one_miss_n1048576", "x".repeat(1048576).get(), "!", -1) != 0: return 1
    if measure("empty_needle_n1048576", "x".repeat(1048576).get(), "", 1048576) != 0: return 1
    if measure("one_end_n1048576", "x".repeat(1048575).get() + "!", "!", 1048575) != 0: return 1
    if measure("one_start_n1048576", "!" + "x".repeat(1048575).get(), "!", 0) != 0: return 1
    if (
        measure(
            "one_middle_n1048576",
            "x".repeat(524288).get() + "!" + "x".repeat(524287).get(), "!", 524288
        ) != 0
    ): return 1
    if measure("one_many_n7", "!x".repeat(3).get() + "!", "!", 6) != 0: return 1
    if measure("one_many_n63", "!x".repeat(31).get() + "!", "!", 62) != 0: return 1
    if measure("one_many_n64", "!x".repeat(32).get() + "", "!", 62) != 0: return 1
    if measure("one_many_n4096", "!x".repeat(2048).get() + "", "!", 4094) != 0: return 1
    if measure("one_many_n1048576", "!x".repeat(524288).get() + "", "!", 1048574) != 0: return 1
    if measure("two_tiny_miss", "a", "ab", -1) != 0: return 1
    if measure("two_tiny_hit", "ab", "ab", 0) != 0: return 1
    if measure("two_tiny_valid_length_miss", "ac", "ab", -1) != 0: return 1
    if measure("two_short_end", "x".repeat(61).get() + "ab", "ab", 61) != 0: return 1
    if measure("two_boundary_end", "x".repeat(62).get() + "ab", "ab", 62) != 0: return 1
    if measure("two_boundary_miss", "x".repeat(65).get(), "ab", -1) != 0: return 1
    if measure("two_repeated_last", "abababab", "ab", 6) != 0: return 1
    if measure("multi_empty_hay", "", "abcd", -1) != 0: return 1
    if measure("multi_tiny_longer", "abc", "abcd", -1) != 0: return 1
    if (
        measure(
            "multi_short_middle", "x".repeat(14).get() + "abcd" + "x".repeat(13).get(),
            "abcd", 14
        ) != 0
    ): return 1
    if measure("multi_boundary_end", "x".repeat(60).get() + "abcd", "abcd", 60) != 0: return 1
    if measure("multi_near_match_miss", "a".repeat(63).get(), "aaab", -1) != 0: return 1
    if measure("multi_overlap", "abababa", "aba", 4) != 0: return 1
    if measure("multi_large_end", "x".repeat(4092).get() + "abcd", "abcd", 4092) != 0: return 1
    if (
        measure(
            "multi_repetitive_miss", "a".repeat(4096).get(),
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab",
            -1
        ) != 0
    ): return 1
    if (
        measure(
            "multi_repetitive_end", "a".repeat(4095).get() + "b",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab",
            3840
        ) != 0
    ): return 1
    if (
        measure(
            "multi_repetitive_overlap", "ab".repeat(2048).get(),
            "abababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababab",
            3840
        ) != 0
    ): return 1
    if measure("unicode_two_end", "é".repeat(31).get() + "!", "!", 31) != 0: return 1
    if measure("unicode_two_start", "!" + "é".repeat(31).get(), "!", 0) != 0: return 1
    if (
        measure(
            "unicode_two_middle", "é".repeat(15).get() + "!" + "é".repeat(16).get(),
            "!", 15
        ) != 0
    ): return 1
    if measure("unicode_two_miss", "é".repeat(31).get() + "x", "!", -1) != 0: return 1
    if measure("unicode_multibyte_needle", "aé日😀é", "é", 4) != 0: return 1
    if measure("unicode_multiscalar_needle", "é日xé日", "é日", 3) != 0: return 1
    if measure("unicode_empty_needle", "é日😀", "", 3) != 0: return 1
    if measure("unicode_wide_end", "日😀".repeat(8).get() + "!", "!", 16) != 0: return 1
    if measure("unicode_combining_needle", "éé", "́", 3) != 0: return 1
    if (
        measure(
            "unicode_large_scalar_index", "é日😀".repeat(4096).get() + "!", "!", 12288
        ) != 0
    ): return 1
    if measure("nul_one", "\u{0}", "\u{0}", 0) != 0: return 1
    if measure("nul_short_start", "\u{0}" + "x".repeat(62).get(), "\u{0}", 0) != 0: return 1
    if measure("nul_short_end", "x".repeat(62).get() + "\u{0}", "\u{0}", 62) != 0: return 1
    if measure("nul_repeated_last", "a\u{0}b\u{0}", "\u{0}", 3) != 0: return 1
    if measure("nul_hay_miss", "a\u{0}b", "!", -1) != 0: return 1

    return 0
