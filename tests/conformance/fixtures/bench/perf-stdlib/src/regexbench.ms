import bench, words from "./harness.ms"
import compile, Regex from "@std/regex.ms"

fn run(re: Regex) Unit:
    text := words(2000).join(" ")

    bench(
        "regex.find_all",
        2000,
        fn() Int:
            if m := re.find_all(text):
                return m.length()

            return 0
    )

    bench(
        "regex.matches",
        10000,
        fn() Int:
            var n = 0
            for i in 0..10000:
                if re.matches("xx word123 yy"): n += 1
            return n
    )

    bench(
        "regex.replace_all",
        2000,
        fn() Int:
            if s := re.replace_all(text, "w"):
                return s.length()

            return 0
    )

export fn bench_regex() Unit:
    if re := compile("word[0-9]+"):
        run(re)
