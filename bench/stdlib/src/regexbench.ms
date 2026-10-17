import {bench, words} from "./harness.ms"
import {compile, Regex} from "@std/regex.ms"

fn run(re: Regex) -> Unit:
    let text = words(2000).join(separator: " ")
    bench(
        "regex.find_all",
        2000,
        fn() -> Int:
            if let m = re.find_all(text: text): return m.length()

            return 0
    )
    bench(
        "regex.matches",
        10000,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 10000:
                if re.matches(text: "xx word123 yy"): n = n + 1
                i = i + 1

            return n
    )
    bench(
        "regex.replace_all",
        2000,
        fn() -> Int:
            if let s = re.replace_all(text: text, replacement: "w"): return s.length()

            return 0
    )

export fn bench_regex() -> Unit:
    if let re = compile(pattern: "word[0-9]+"): run(re)
