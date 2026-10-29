import stdout from "@std/io.ms"
import clock from "@std/time.ms"

fn consume(parts: List[String]) Int:
    var checksum = parts.length() * 17
    for part in parts:
        checksum += part.byte_length()
    return checksum

fn split_sum(text: String, separator: String, limit: Int, expected: List[String]) Int:
    if limit < 0:
        let parts = text.split(separator)
        if parts != expected: return -1

        return consume(parts)

    let parts = text.split(separator, max_parts: limit)
    if parts != expected: return -1

    return consume(parts)

fn expected_fields(field: String, count: Int, tail: String = "") List[String]:
    var expected: List[String] = []
    for index in 0..count:
        expected.append(field.clone())
    expected.append(tail)
    return expected

fn measure(
    name: String,
    text: String,
    separator: String,
    expected: Int,
    iterations: Int,
    expected_parts: List[String],
    limit: Int = -1
) Int:
    if split_sum(text, separator, limit, expected_parts) != expected: return 1

    var checksum = 0
    let started = clock().now()
    for iteration in 0..iterations:
        checksum += split_sum(text, separator, limit, expected_parts)

    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected * iterations: return 1

    let _written = stdout().write(
        "{name},{text.byte_length()},{iterations},{elapsed},{checksum}\n"
    )
    return 0

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\n")
    let long_separator = "abcdefghij".repeat(9).get()

    for separator in ["::", "<split>", long_separator]:
        let size = separator.byte_length()

        for width in [7, 64]:
            for count in [8, 64, 512, 4096]:
                let field = "x".repeat(width).get()
                let text = (field + separator).repeat(count).get()
                var iterations = 32
                if count == 8: iterations = 10000
                if count == 64: iterations = 2000
                if count == 512: iterations = 256
                if (
                    measure(
                        "d{size}_w{width}_fields{count}", text, separator,
                        (width + 17) * count + 17, iterations,
                        expected_fields(field, count)
                    ) != 0
                ): return 1

        for length in [31, 32, 63, 64, 65]:
            let text = "x".repeat(length).get()
            if (
                measure(
                    "d{size}_absent_n{length}", text, separator, length + 17, 100000,
                    [text]
                ) != 0
            ):
                return 1

        for length in [4096, 65536]:
            let text = "x".repeat(length).get()
            if (
                measure(
                    "d{size}_absent_n{length}", text, separator, length + 17, 1024,
                    [text]
                ) != 0
            ):
                return 1

        for offset in [0, 32768, 65536]:
            let before = "x".repeat(offset).get()
            let after = "y".repeat(65536 - offset).get()
            let text = before + separator + after
            if (
                measure(
                    "d{size}_single_hit_at{offset}", text, separator, 65570, 1024,
                    [before, after]
                ) != 0
            ): return 1

        for tail_size in [4096, 65536]:
            let tail = "z".repeat(tail_size).get()
            let text = "a" + separator + "b" + separator + tail
            if (
                measure(
                    "d{size}_two_hits_tail{tail_size}", text, separator, tail_size + 53,
                    1024, ["a", "b", tail]
                ) != 0
            ): return 1

        let repeated = ("field" + separator).repeat(4096).get()

        for limit in [0, 1, 2]:
            var expected: List[String] = []
            for index in 0..limit:
                expected.append("field")
            if (
                measure(
                    "d{size}_limit{limit}", repeated, separator, limit * 22, 100000,
                    expected, limit
                ) != 0
            ): return 1

    for width in [1, 7, 16, 31, 64, 1024]:
        let field = "x".repeat(width).get()
        let text = (field + " ").repeat(512).get()
        if (
            measure(
                "byte_w{width}", text, " ", (width + 17) * 512 + 17, 256,
                expected_fields(field, 512)
            ) != 0
        ):
            return 1

    for padding in [0, 1, 24, 25, 55, 56, 57, 58, 88]:
        let prefix = "x".repeat(padding).get()
        let text = prefix + "::a::::"
        if (
            measure(
                "short_fields_pad{padding}", text, "::", padding + 69, 100000,
                [prefix, "a", "", ""]
            ) != 0
        ):
            return 1

    let unicode = "é日😀<split>".repeat(512).get() + "終"
    if (
        measure(
            "unicode", unicode, "<split>", 512 * 26 + 20, 256,
            expected_fields("é日😀", 512, "終")
        ) != 0
    ): return 1
    if measure("empty", "", "::", 17, 100000, [""]) != 0: return 1
    if measure("empty_separator", "é日😀", "", 60, 100000, ["é", "日", "😀"]) != 0: return 1

    let scalar_input = "é日😀".repeat(512).get()
    if (
        measure(
            "empty_separator_prefix", scalar_input, "", 39, 100000, ["é", "日"], 2
        ) != 0
    ):
        return 1

    var scalars: List[String] = []

    for index in 0..512:
        scalars.append("é")
        scalars.append("日")
        scalars.append("😀")

    if measure("empty_separator_full", scalar_input, "", 30720, 256, scalars) != 0: return 1

    return 0
