import stdout from "@std/io.ms"
import clock from "@std/time.ms"
import StringError from "@std/string.ms"

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

    for pattern in [
        Pattern("empty", "", "", "", "", ""),
        Pattern("one_ascii", "x", "x", "x", "x", "x"),
        Pattern(
            "ascii_controls", "abC9\u{0}\t", "abC9\u{0}\t", "abC9\u{0}\t",
            "abC9\u{0}\t", "abC9\u{0}\t"
        ),
        Pattern("compose", "e\u{301}", "é", "e\u{301}", "é", "e\u{301}"),
        Pattern("decompose", "é", "é", "e\u{301}", "é", "e\u{301}"),
        Pattern("compatibility", "ﬁ①", "ﬁ①", "ﬁ①", "fi1", "fi1"),
        Pattern(
            "reorder", "a\u{315}\u{300}", "à\u{315}", "a\u{300}\u{315}", "à\u{315}",
            "a\u{300}\u{315}"
        ),
        Pattern("hangul", "각", "각", "각", "각", "각"),
        Pattern(
            "replacement_nul", "a\u{fffd}\u{0}", "a\u{fffd}\u{0}", "a\u{fffd}\u{0}",
            "a\u{fffd}\u{0}", "a\u{fffd}\u{0}"
        )
    ]:
        for form in ["NFC", "NFD", "NFKC", "NFKD"]:
            let expected = expected_for(pattern, form)
            if (
                measure(
                    "{pattern.name}_{form}_full", pattern.text, form, false, 0,
                    expected, 0, iterations_for(pattern.text.byte_length())
                ) != 0
            ): return 1

    for pattern in [
        Pattern(
            "ascii_scale", "aZ09\u{0}", "aZ09\u{0}", "aZ09\u{0}", "aZ09\u{0}",
            "aZ09\u{0}"
        ),
        Pattern(
            "canonical_scale", "e\u{301}", "é", "e\u{301}", "é", "e\u{301}"
        ),
        Pattern("compatibility_scale", "ﬁ①", "ﬁ①", "ﬁ①", "fi1", "fi1")
    ]:
        for copies in [4096, 65536]:
            let text = pattern.text.repeat(copies).get()

            for form in ["NFC", "NFD", "NFKC", "NFKD"]:
                let expected = expected_for(pattern, form).repeat(copies).get()
                if (
                    measure(
                        "{pattern.name}_{copies}_{form}_full", text, form, false, 0,
                        expected, 0, iterations_for(text.byte_length())
                    ) != 0
                ): return 1

    let cluster = "a" + "\u{315}\u{300}".repeat(256).get()
    let decomposed = "a" + "\u{300}".repeat(256).get() + "\u{315}".repeat(256).get()
    let composed = "à" + "\u{300}".repeat(255).get() + "\u{315}".repeat(256).get()

    for form in ["NFC", "NFD", "NFKC", "NFKD"]:
        var expected = decomposed.clone()
        if form == "NFC" or form == "NFKC": expected = composed.clone()
        if (
            measure(
                "combining_segment_{form}_full", cluster, form, false, 0, expected, 0,
                64
            ) != 0
        ): return 1

    let budget_text = "e\u{301}".repeat(4096).get()

    for form in ["NFC", "NFD", "NFKC", "NFKD"]:
        var expected = "e\u{301}".repeat(4096).get()
        if form == "NFC" or form == "NFKC": expected = "é".repeat(4096).get()

        let exact = expected.byte_length()
        let iterations = iterations_for(budget_text.byte_length())
        if (
            measure(
                "budget_{form}_zero", budget_text, form, true, 0, "", 1, iterations
            ) != 0
        ): return 1
        if (
            measure(
                "budget_{form}_exact", budget_text, form, true, exact, expected, 0,
                iterations
            ) != 0
        ): return 1
        if (
            measure(
                "budget_{form}_exceeded", budget_text, form, true, exact - 1, "", 1,
                iterations
            ) != 0
        ): return 1
        if measure("negative_{form}", "é", form, true, -1, "", 2, 200000) != 0: return 1

    if measure("invalid_lowercase", "é", "nfc", false, 0, "", 2, 200000) != 0: return 1
    if measure("invalid_unknown", "é", "UNKNOWN", false, 0, "", 2, 200000) != 0: return 1
    if measure("invalid_nul", "é", "NFC\u{0}", false, 0, "", 2, 200000) != 0: return 1
    if measure("invalid_negative", "é", "UNKNOWN", true, -1, "", 2, 200000) != 0: return 1

    let unicode_boundary = Pattern(
        "unicode_boundary", "éﬁ", "éﬁ", "e\u{301}ﬁ", "éfi", "e\u{301}fi"
    )

    for length in [4096, 1048576]:
        let ascii_prefix = "x".repeat(length).get()

        for form in ["NFC", "NFD", "NFKC", "NFKD"]:
            let expected_block = expected_for(unicode_boundary, form)
            let iterations = iterations_for(
                length + unicode_boundary.text.byte_length()
            )
            if (
                measure(
                    "early_unicode_{length}_{form}",
                    unicode_boundary.text + ascii_prefix, form, false, 0,
                    expected_block + ascii_prefix, 0, iterations
                ) != 0
            ): return 1
            if (
                measure(
                    "late_unicode_{length}_{form}",
                    ascii_prefix + unicode_boundary.text, form, false, 0,
                    ascii_prefix + expected_block, 0, iterations
                ) != 0
            ): return 1

    return 0
