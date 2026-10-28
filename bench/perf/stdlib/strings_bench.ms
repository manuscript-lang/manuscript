from "@std/bench.ms" import keep, measure
from "./src/harness.ms" import words
from "@std/string.ms" import StringBuilder

bench "string.append_builder":
    def work() -> Result[Unit, Error]:
        var sb = StringBuilder()
        for i in 0..100000:
            sb.append("x")
        return keep(sb.build().byte_length())

    try measure(100000, work)

bench "string.concat":
    def work() -> Result[Unit, Error]:
        var s = ""
        for i in 0..20000:
            s = s.concat("x")
        return keep(s.length())

    try measure(20000, work)

bench "string.split":
    let text = words(2000).join(" ")

    def work() -> Result[Unit, Error]:
        var n = 0
        for i in 0..200:
            n += text.split(" ").length()
        return keep(n)

    try measure(200, work)

bench "string.replace":
    let text = words(2000).join(" ")

    def work() -> Result[Unit, Error]:
        var n = 0
        for i in 0..200:
            n = (n + text.replace("word", "w").length())
        return keep(n)

    try measure(200, work)

bench "string.contains":
    let text = words(2000).join(" ")

    def work() -> Result[Unit, Error]:
        var n = 0
        for i in 0..2000:
            if text.contains("word976 word0"): n += 1
        return keep(n)

    try measure(2000, work)

bench "string.upper":
    let text = words(2000).join(" ")

    def work() -> Result[Unit, Error]:
        var n = 0
        for i in 0..200:
            n += text.upper().length()
        return keep(n)

    try measure(200, work)

bench "string.trim":
    def work() -> Result[Unit, Error]:
        var n = 0
        for i in 0..100000:
            n += "  padded  ".trim().length()
        return keep(n)

    try measure(100000, work)

bench "string.index_char_at":
    let text = words(2000).join(" ")

    def work() -> Result[Unit, Error]:
        var n = 0
        for i in 0..100000:
            n += text.get(i % 5000, default: "").length()
        return keep(n)

    try measure(100000, work)

bench "string.chars":
    let text = words(2000).join(" ")

    def work() -> Result[Unit, Error]:
        var n = 0
        for i in 0..20:
            n += text.chars().length()
        return keep(n)

    try measure(20, work)

bench "string.parse_int":
    def work() -> Result[Unit, Error]:
        var n = 0
        for i in 0..100000:
            n += "12345".parse_int().get(0)
        return keep(n)

    try measure(100000, work)

bench "string.interpolate":
    def work() -> Result[Unit, Error]:
        var n = 0
        for i in 0..100000:
            n += f"item {i} of {n}".length()
        return keep(n)

    try measure(100000, work)
