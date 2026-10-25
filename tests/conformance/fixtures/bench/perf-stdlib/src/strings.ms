from "@std/collections.ms" import range
from "./harness.ms" import bench, words
from "@std/string.ms" import StringBuilder

export def bench_string() -> Unit:
    let text = words(2000).join(" ")

    bench(
        "string.append_builder",
        100000,
        lambda () -> Int:
            var sb = StringBuilder()
            for i in range(0, 100000):
                sb.append("x")
            return sb.build().byte_length()
    )

    bench(
        "string.concat",
        20000,
        lambda () -> Int:
            var s = ""
            for i in range(0, 20000):
                s = s.concat("x")
            return s.length()
    )

    bench(
        "string.split",
        200,
        lambda () -> Int:
            var n = 0
            for i in range(0, 200):
                n += text.split(" ").length()
            return n
    )

    bench(
        "string.replace_all",
        200,
        lambda () -> Int:
            var n = 0
            for i in range(0, 200):
                n = (n + text.replace_all("word", "w").get("").length())
            return n
    )

    bench(
        "string.contains",
        2000,
        lambda () -> Int:
            var n = 0
            for i in range(0, 2000):
                if text.contains("word976 word0"): n += 1
            return n
    )

    bench(
        "string.upper",
        200,
        lambda () -> Int:
            var n = 0
            for i in range(0, 200):
                n += text.upper().length()
            return n
    )

    bench(
        "string.trim",
        100000,
        lambda () -> Int:
            var n = 0
            for i in range(0, 100000):
                n += "  padded  ".trim().length()
            return n
    )

    bench(
        "string.index_char_at",
        100000,
        lambda () -> Int:
            var n = 0
            for i in range(0, 100000):
                n += text.get(i % 5000, default: "").length()
            return n
    )

    bench(
        "string.chars",
        20,
        lambda () -> Int:
            var n = 0
            for i in range(0, 20):
                n += text.chars().length()
            return n
    )

    bench(
        "string.parse_int",
        100000,
        lambda () -> Int:
            var n = 0
            for i in range(0, 100000):
                n += "12345".parse_int().get(0)
            return n
    )

    bench(
        "string.interpolate",
        100000,
        lambda () -> Int:
            var n = 0
            for i in range(0, 100000):
                n += f"item {i} of {n}".length()
            return n
    )
