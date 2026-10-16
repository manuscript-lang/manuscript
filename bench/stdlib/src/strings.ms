import {bench, words} from "./harness.ms"
import {StringBuilder} from "@std/string.ms"

export fn bench_string() -> Unit:
    let text = words(2000).join(separator: " ")
    bench(
        "string.append_builder",
        100000,
        fn() -> Int:
            let sb = StringBuilder()
            var i = 0

            while i < 100000:
                sb.append("x")
                i = i + 1

            return sb.freeze().byte_length()
    )
    bench(
        "string.concat",
        20000,
        fn() -> Int:
            var s = ""
            var i = 0

            while i < 20000:
                s = s.concat("x")
                i = i + 1

            return s.length()
    )
    bench(
        "string.split",
        200,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 200:
                n = n + text.split(separator: " ").length()
                i = i + 1

            return n
    )
    bench(
        "string.replace_all",
        200,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 200:
                n = (n + text.replace_all(old: "word", new: "w").unwrap_or("").length())
                i = i + 1

            return n
    )
    bench(
        "string.contains",
        2000,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 2000:
                if text.contains("word976 word0"): n = n + 1

                i = i + 1

            return n
    )
    bench(
        "string.upper",
        200,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 200:
                n = n + text.upper().length()
                i = i + 1

            return n
    )
    bench(
        "string.trim",
        100000,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 100000:
                n = n + "  padded  ".trim().length()
                i = i + 1

            return n
    )
    bench(
        "string.index_char_at",
        100000,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 100000:
                n = n + text.at(i % 5000).unwrap_or("").length()

                i = i + 1

            return n
    )
    bench(
        "string.chars",
        20,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 20:
                n = n + text.chars().length()
                i = i + 1

            return n
    )
    bench(
        "string.parse_int",
        100000,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 100000:
                n = n + "12345".parse_int().unwrap_or(0)
                i = i + 1

            return n
    )
    bench(
        "string.interpolate",
        100000,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 100000:
                n = n + "item {i} of {n}".length()
                i = i + 1

            return n
    )
