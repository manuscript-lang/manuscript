import stdout from "@std/io.ms"
import clock from "@std/time.ms"
import StringError from "@std/string.ms"

fn consume(result: Result[String, StringError], expected: String, status: Int) Int:
    if status == 0:
        if result.is_error(): return -1

        let output = result.get()
        if output != expected: return -1

        return output.byte_length() + 17

    if not result.is_error(): return -1

    let actual_error = result.err()
    if status == 1 and actual_error != StringError.LimitExceeded: return -1
    if status == 2 and actual_error != StringError.InvalidInput: return -1

    return 17

fn normalize_sum(
    text: String,
    form: String,
    has_max: Bool,
    max: Int,
    expected: String,
    status: Int
) Int:
    if has_max: return consume(text.normalize(form, max), expected, status)

    return consume(text.normalize(form), expected, status)

fn measure(
    name: String,
    text: String,
    form: String,
    has_max: Bool,
    max: Int,
    expected: String,
    status: Int,
    iterations: Int
) Int:
    var expected_sum = 17
    if status == 0: expected_sum += expected.byte_length()
    if normalize_sum(text, form, has_max, max, expected, status) != expected_sum: return 1

    var checksum = 0
    let started = clock().now()
    for iteration in 0..iterations:
        checksum += normalize_sum(text, form, has_max, max, expected, status)

    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected_sum * iterations: return 1

    let _written = stdout().write(
        "{name},{text.byte_length()},{iterations},{elapsed},{checksum}\n"
    )
    return 0

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\n")
    if (
        measure(
            "early_unicode_4096_NFC", "éﬁ" + "x".repeat(4096).get(), "NFC", false, 0,
            "éﬁ" + "x".repeat(4096).get(), 0, 256
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_4096_NFC", "x".repeat(4096).get() + "éﬁ", "NFC", false, 0,
            "x".repeat(4096).get() + "éﬁ", 0, 256
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_4096_NFD", "éﬁ" + "x".repeat(4096).get(), "NFD", false, 0,
            "éﬁ" + "x".repeat(4096).get(), 0, 256
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_4096_NFD", "x".repeat(4096).get() + "éﬁ", "NFD", false, 0,
            "x".repeat(4096).get() + "éﬁ", 0, 256
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_4096_NFKC", "éﬁ" + "x".repeat(4096).get(), "NFKC", false, 0,
            "éfi" + "x".repeat(4096).get(), 0, 256
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_4096_NFKC", "x".repeat(4096).get() + "éﬁ", "NFKC", false, 0,
            "x".repeat(4096).get() + "éfi", 0, 256
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_4096_NFKD", "éﬁ" + "x".repeat(4096).get(), "NFKD", false, 0,
            "éfi" + "x".repeat(4096).get(), 0, 256
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_4096_NFKD", "x".repeat(4096).get() + "éﬁ", "NFKD", false, 0,
            "x".repeat(4096).get() + "éfi", 0, 256
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_1048576_NFC", "éﬁ" + "x".repeat(1048576).get(), "NFC", false,
            0, "éﬁ" + "x".repeat(1048576).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_1048576_NFC", "x".repeat(1048576).get() + "éﬁ", "NFC", false,
            0, "x".repeat(1048576).get() + "éﬁ", 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_1048576_NFD", "éﬁ" + "x".repeat(1048576).get(), "NFD", false,
            0, "éﬁ" + "x".repeat(1048576).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_1048576_NFD", "x".repeat(1048576).get() + "éﬁ", "NFD", false,
            0, "x".repeat(1048576).get() + "éﬁ", 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_1048576_NFKC", "éﬁ" + "x".repeat(1048576).get(), "NFKC",
            false, 0, "éfi" + "x".repeat(1048576).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_1048576_NFKC", "x".repeat(1048576).get() + "éﬁ", "NFKC",
            false, 0, "x".repeat(1048576).get() + "éfi", 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_1048576_NFKD", "éﬁ" + "x".repeat(1048576).get(), "NFKD",
            false, 0, "éfi" + "x".repeat(1048576).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_1048576_NFKD", "x".repeat(1048576).get() + "éﬁ", "NFKD",
            false, 0, "x".repeat(1048576).get() + "éfi", 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "canonical_scale_65536_NFC_full", "é".repeat(65536).get(), "NFC", false, 0,
            "é".repeat(65536).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "canonical_scale_65536_NFD_full", "é".repeat(65536).get(), "NFD", false, 0,
            "é".repeat(65536).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "canonical_scale_65536_NFKC_full", "é".repeat(65536).get(), "NFKC", false,
            0, "é".repeat(65536).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "canonical_scale_65536_NFKD_full", "é".repeat(65536).get(), "NFKD", false,
            0, "é".repeat(65536).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "compatibility_scale_65536_NFC_full", "ﬁ①".repeat(65536).get(), "NFC",
            false, 0, "ﬁ①".repeat(65536).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "compatibility_scale_65536_NFD_full", "ﬁ①".repeat(65536).get(), "NFD",
            false, 0, "ﬁ①".repeat(65536).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "compatibility_scale_65536_NFKC_full", "ﬁ①".repeat(65536).get(), "NFKC",
            false, 0, "fi1".repeat(65536).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "compatibility_scale_65536_NFKD_full", "ﬁ①".repeat(65536).get(), "NFKD",
            false, 0, "fi1".repeat(65536).get(), 0, 16
        ) != 0
    ): return 1
    if measure("empty_NFC_full", "", "NFC", false, 0, "", 0, 5000000) != 0: return 1
    if measure("empty_NFD_full", "", "NFD", false, 0, "", 0, 5000000) != 0: return 1
    if measure("empty_NFKC_full", "", "NFKC", false, 0, "", 0, 5000000) != 0: return 1
    if measure("empty_NFKD_full", "", "NFKD", false, 0, "", 0, 5000000) != 0: return 1
    if measure("one_ascii_NFC_full", "x", "NFC", false, 0, "x", 0, 5000000) != 0: return 1
    if measure("one_ascii_NFD_full", "x", "NFD", false, 0, "x", 0, 5000000) != 0: return 1
    if measure("one_ascii_NFKC_full", "x", "NFKC", false, 0, "x", 0, 5000000) != 0: return 1
    if measure("one_ascii_NFKD_full", "x", "NFKD", false, 0, "x", 0, 5000000) != 0: return 1
    if (
        measure(
            "ascii_scale_65536_NFC_full", "aZ09\u{0}".repeat(65536).get(), "NFC", false,
            0, "aZ09\u{0}".repeat(65536).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "ascii_scale_65536_NFD_full", "aZ09\u{0}".repeat(65536).get(), "NFD", false,
            0, "aZ09\u{0}".repeat(65536).get(), 0, 16
        ) != 0
    ): return 1
    if measure("negative_NFC", "é", "NFC", true, -1, "", 2, 5000000) != 0: return 1
    if measure("negative_NFD", "é", "NFD", true, -1, "", 2, 5000000) != 0: return 1
    if measure("negative_NFKC", "é", "NFKC", true, -1, "", 2, 5000000) != 0: return 1
    if measure("negative_NFKD", "é", "NFKD", true, -1, "", 2, 5000000) != 0: return 1
    if measure("invalid_lowercase", "é", "nfc", false, 0, "", 2, 5000000) != 0: return 1
    if measure("invalid_unknown", "é", "UNKNOWN", false, 0, "", 2, 5000000) != 0: return 1
    if measure("invalid_nul", "é", "NFC\u{0}", false, 0, "", 2, 5000000) != 0: return 1
    if measure("invalid_negative", "é", "UNKNOWN", true, -1, "", 2, 5000000) != 0: return 1
    if (
        measure(
            "budget_NFD_zero", "é".repeat(4096).get(), "NFD", true, 0, "", 1, 1024
        ) != 0
    ): return 1
    if (
        measure(
            "budget_NFD_exact", "é".repeat(4096).get(), "NFD", true, 12288,
            "é".repeat(4096).get(), 0, 1024
        ) != 0
    ): return 1
    if (
        measure(
            "budget_NFD_exceeded", "é".repeat(4096).get(), "NFD", true, 12287, "", 1,
            1024
        ) != 0
    ): return 1
    if (
        measure(
            "budget_NFKC_zero", "é".repeat(4096).get(), "NFKC", true, 0, "", 1, 1024
        ) != 0
    ): return 1
    if (
        measure(
            "budget_NFKC_exact", "é".repeat(4096).get(), "NFKC", true, 8192,
            "é".repeat(4096).get(), 0, 1024
        ) != 0
    ): return 1
    if (
        measure(
            "budget_NFKC_exceeded", "é".repeat(4096).get(), "NFKC", true, 8191, "", 1,
            1024
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_4096_NFC_max0", "éﬁ" + "x".repeat(4096).get(), "NFC", true,
            0, "", 1, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_4096_NFC_max1", "éﬁ" + "x".repeat(4096).get(), "NFC", true,
            1, "", 1, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_4096_NFC_max0", "x".repeat(4096).get() + "éﬁ", "NFC", true, 0,
            "", 1, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_4096_NFC_max1", "x".repeat(4096).get() + "éﬁ", "NFC", true, 1,
            "", 1, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_4096_NFD_max0", "éﬁ" + "x".repeat(4096).get(), "NFD", true,
            0, "", 1, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_4096_NFD_max1", "éﬁ" + "x".repeat(4096).get(), "NFD", true,
            1, "", 1, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_4096_NFD_max0", "x".repeat(4096).get() + "éﬁ", "NFD", true, 0,
            "", 1, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_4096_NFD_max1", "x".repeat(4096).get() + "éﬁ", "NFD", true, 1,
            "", 1, 4096
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_1048576_NFC_max0", "éﬁ" + "x".repeat(1048576).get(), "NFC",
            true, 0, "", 1, 64
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_1048576_NFC_max1", "éﬁ" + "x".repeat(1048576).get(), "NFC",
            true, 1, "", 1, 64
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_1048576_NFC_max0", "x".repeat(1048576).get() + "éﬁ", "NFC",
            true, 0, "", 1, 64
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_1048576_NFC_max1", "x".repeat(1048576).get() + "éﬁ", "NFC",
            true, 1, "", 1, 64
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_1048576_NFD_max0", "éﬁ" + "x".repeat(1048576).get(), "NFD",
            true, 0, "", 1, 64
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_1048576_NFD_max1", "éﬁ" + "x".repeat(1048576).get(), "NFD",
            true, 1, "", 1, 64
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_1048576_NFD_max0", "x".repeat(1048576).get() + "éﬁ", "NFD",
            true, 0, "", 1, 64
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_1048576_NFD_max1", "x".repeat(1048576).get() + "éﬁ", "NFD",
            true, 1, "", 1, 64
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_1048576_NFD_budget_exact", "éﬁ" + "x".repeat(1048576).get(),
            "NFD", true, 1048582, "éﬁ" + "x".repeat(1048576).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_1048576_NFD_budget_short", "éﬁ" + "x".repeat(1048576).get(),
            "NFD", true, 1048581, "", 1, 16
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_1048576_NFD_budget_exact", "x".repeat(1048576).get() + "éﬁ",
            "NFD", true, 1048582, "x".repeat(1048576).get() + "éﬁ", 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_1048576_NFD_budget_short", "x".repeat(1048576).get() + "éﬁ",
            "NFD", true, 1048581, "", 1, 16
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_1048576_NFKC_budget_exact", "éﬁ" + "x".repeat(1048576).get(),
            "NFKC", true, 1048580, "éfi" + "x".repeat(1048576).get(), 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "early_unicode_1048576_NFKC_budget_short", "éﬁ" + "x".repeat(1048576).get(),
            "NFKC", true, 1048579, "", 1, 16
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_1048576_NFKC_budget_exact", "x".repeat(1048576).get() + "éﬁ",
            "NFKC", true, 1048580, "x".repeat(1048576).get() + "éfi", 0, 16
        ) != 0
    ): return 1
    if (
        measure(
            "late_unicode_1048576_NFKC_budget_short", "x".repeat(1048576).get() + "éﬁ",
            "NFKC", true, 1048579, "", 1, 16
        ) != 0
    ): return 1

    return 0
