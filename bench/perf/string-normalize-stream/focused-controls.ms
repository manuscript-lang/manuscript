import stdout from "@std/io/io.ms"
import monotonic from "@std/os/time.ms"

type Pattern:
    name: String
    text: String
    nfc: String
    nfd: String
    nfkc: String
    nfkd: String

fn expected_for(pattern: Pattern, form: String) String:
    if form == "NFC": return pattern.nfc.clone()
    if form == "NFD": return pattern.nfd.clone()
    if form == "NFKC": return pattern.nfkc.clone()

    return pattern.nfkd.clone()

fn iterations_for(size: Int) Int:
    if size <= 128: return 200000
    if size >= 65536: return 16
    if size >= 4096: return 256

    return 4096

fn consume(result: Result[String, Error], expected: String, status: Int) Int:
    if status == 0:
        if result.is_error(): return -1

        let output = result.get()
        if output != expected: return -1

        return output.byte_length() + 17

    if not result.is_error(): return -1

    let actual_error = result.err()
    if (
        status == 1
        and actual_error != Error(
            "string: limit exceeded", kind: ErrorCategory.LimitExceeded
        )
    ): return (-1)
    if (
        status == 2
        and actual_error != Error(
            "string: invalid input", kind: ErrorCategory.InvalidInput
        )
    ): return (-1)

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
    let started = monotonic()
    for iteration in 0..iterations:
        checksum += normalize_sum(text, form, has_max, max, expected, status)

    let elapsed = monotonic().difference(started).to_nanoseconds()
    if checksum != expected_sum * iterations: return 1

    let _written = stdout().write(
        "{name},{text.byte_length()},{iterations},{elapsed},{checksum}\n"
    )
    return 0

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\n")
    if measure("empty_NFC_full", "", "NFC", false, 0, "", 0, 1000000) != 0: return 1
    if measure("empty_NFD_full", "", "NFD", false, 0, "", 0, 1000000) != 0: return 1
    if measure("empty_NFKC_full", "", "NFKC", false, 0, "", 0, 1000000) != 0: return 1
    if measure("empty_NFKD_full", "", "NFKD", false, 0, "", 0, 1000000) != 0: return 1
    if measure("one_ascii_NFC_full", "x", "NFC", false, 0, "x", 0, 1000000) != 0: return 1
    if measure("one_ascii_NFD_full", "x", "NFD", false, 0, "x", 0, 1000000) != 0: return 1
    if measure("one_ascii_NFKC_full", "x", "NFKC", false, 0, "x", 0, 1000000) != 0: return 1
    if measure("one_ascii_NFKD_full", "x", "NFKD", false, 0, "x", 0, 1000000) != 0: return 1
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
            "canonical_scale_65536_NFC_full", "é".repeat(65536).get(), "NFC", false, 0,
            "é".repeat(65536).get(), 0, 64
        ) != 0
    ): return 1
    if (
        measure(
            "canonical_scale_65536_NFD_full", "é".repeat(65536).get(), "NFD", false, 0,
            "é".repeat(65536).get(), 0, 64
        ) != 0
    ): return 1
    if (
        measure(
            "canonical_scale_65536_NFKC_full", "é".repeat(65536).get(), "NFKC", false,
            0, "é".repeat(65536).get(), 0, 64
        ) != 0
    ): return 1
    if (
        measure(
            "canonical_scale_65536_NFKD_full", "é".repeat(65536).get(), "NFKD", false,
            0, "é".repeat(65536).get(), 0, 64
        ) != 0
    ): return 1
    if (
        measure(
            "compatibility_scale_4096_NFKC_full", "ﬁ①".repeat(4096).get(), "NFKC",
            false, 0, "fi1".repeat(4096).get(), 0, 1024
        ) != 0
    ): return 1
    if (
        measure(
            "compatibility_scale_4096_NFKD_full", "ﬁ①".repeat(4096).get(), "NFKD",
            false, 0, "fi1".repeat(4096).get(), 0, 1024
        ) != 0
    ): return 1
    if (
        measure(
            "combining_segment_NFD_full", ("a" + "̀̕".repeat(256).get()), "NFD", false,
            0, ("a" + "̀".repeat(256).get() + "̕".repeat(256).get()), 0, 1024
        ) != 0
    ): return 1
    if (
        measure(
            "combining_segment_NFKD_full", ("a" + "̀̕".repeat(256).get()), "NFKD",
            false, 0, ("a" + "̀".repeat(256).get() + "̕".repeat(256).get()), 0, 1024
        ) != 0
    ): return 1

    return 0
