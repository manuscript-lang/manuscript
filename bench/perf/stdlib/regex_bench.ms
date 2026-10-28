from "@std/bench.ms" import keep, measure
from "./src/harness.ms" import words
from "@std/string.ms" import compile

bench "regex.find_all":
    let text = words(2000).join(" ")

    if let re = compile("word[0-9]+"):
        def work() -> Result[Unit, Error]:
            if let m = re.find_all(text):
                return keep(m.length())

            return keep(0)

        try measure(2000, work)

bench "regex.matches":
    if let re = compile("word[0-9]+"):
        def work() -> Result[Unit, Error]:
            var n = 0
            for i in 0..10000:
                if re.matches("xx word123 yy"): n += 1
            return keep(n)

        try measure(10000, work)

bench "regex.replace_all":
    let text = words(2000).join(" ")

    if let re = compile("word[0-9]+"):
        def work() -> Result[Unit, Error]:
            if let s = re.replace_all(text, "w"):
                return keep(s.length())

            return keep(0)

        try measure(2000, work)
