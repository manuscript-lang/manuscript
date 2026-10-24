from "@std/collections.ms" import range
from "./harness.ms" import bench, words
from "@std/string.ms" import compile, Regex

def run(re: Regex) -> Unit:
    let text = words(2000).join(" ")

    bench(
        "regex.find_all",
        2000,
        lambda () -> Int:
            if let m = re.find_all(text):
                return m.length()

            return 0
    )

    bench(
        "regex.matches",
        10000,
        lambda () -> Int:
            var n = 0
            for i in range(0, 10000):
                if re.matches("xx word123 yy"): n += 1
            return n
    )

    bench(
        "regex.replace_all",
        2000,
        lambda () -> Int:
            if let s = re.replace_all(text, "w"):
                return s.length()

            return 0
    )

export def bench_regex() -> Unit:
    if let re = compile("word[0-9]+"):
        run(re)
