import stdout from "@std/io.ms"
import clock from "@std/time.ms"

fn prefix(pattern: String, length: Int) String:
    let repeated = pattern.repeat((length + 7) / 8).get()
    return repeated.slice_scalars(0, length).get()

fn consume(output: String, expected: String) Int:
    if output != expected: return -1

    return output.byte_length() + 17

fn case_sum(text: String, expected: String, upper: Bool) Int:
    if upper: return consume(text.upper(), expected)

    return consume(text.lower(), expected)

fn measure(
    name: String,
    text: String,
    expected: String,
    upper: Bool,
    iterations: Int
) Int:
    let expected_sum = expected.byte_length() + 17
    if case_sum(text, expected, upper) != expected_sum: return 1

    var checksum = 0
    let started = clock().now()
    for iteration in 0..iterations:
        checksum += case_sum(text, expected, upper)

    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected_sum * iterations: return 1

    let _written = stdout().write(
        "{name},{text.byte_length()},{iterations},{elapsed},{checksum}\n"
    )
    return 0

fn unicode_case(
    name: String,
    text: String,
    upper: String,
    lower: String,
    iterations: Int
) Int:
    if measure("upper_{name}", text, upper, true, iterations) != 0: return 1
    if measure("lower_{name}", text, lower, false, iterations) != 0: return 1

    return 0

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\n")

    for length in [0, 1, 2, 15, 16, 17, 31, 32, 128, 4096, 1048576]:
        let mixed = prefix("aZ09_-.\u{0}", length)
        let upper = prefix("AZ09_-.\u{0}", length)
        let lower = prefix("az09_-.\u{0}", length)
        let controls = prefix("09_-.\u{0}\t\n", length)
        var iterations = 100000
        if length == 4096: iterations = 4096
        if length == 1048576: iterations = 16
        if measure("upper_mixed_n{length}", mixed, upper, true, iterations) != 0: return 1
        if measure("lower_mixed_n{length}", mixed, lower, false, iterations) != 0: return 1
        if measure("upper_already_n{length}", upper, upper, true, iterations) != 0: return 1
        if measure("lower_already_n{length}", lower, lower, false, iterations) != 0: return 1
        if (
            measure(
                "upper_controls_n{length}", controls, controls, true, iterations
            ) != 0
        ): return 1
        if (
            measure(
                "lower_controls_n{length}", controls, controls, false, iterations
            ) != 0
        ): return 1

    if unicode_case("sharp_s", "straße", "STRASSE", "straße", 100000) != 0: return 1
    if unicode_case("turkish_i", "İ", "İ", "i\u{307}", 100000) != 0: return 1
    if unicode_case("final_sigma", "ΟΣ", "ΟΣ", "ος", 100000) != 0: return 1
    if unicode_case("medial_sigma", "ΟΣΑ", "ΟΣΑ", "οσα", 100000) != 0: return 1
    if unicode_case("sigma_mark", "AΣ\u{301}", "AΣ\u{301}", "aς\u{301}", 100000) != 0: return 1
    if (
        unicode_case(
            "sigma_format", "AΣ\u{2060}A", "AΣ\u{2060}A", "aσ\u{2060}a", 100000
        ) != 0
    ): return 1

    let ascii_prefix = "a".repeat(1048576).get()
    if (
        unicode_case(
            "long_prefix_unicode", ascii_prefix + "ßİ ΟΣ",
            "A".repeat(1048576).get() + "SSİ ΟΣ", ascii_prefix + "ßi\u{307} ος", 16
        ) != 0
    ): return 1

    return 0
