from "@std/collections.ms" import range
from "@std/io.ms" import stdout
from "@std/string.ms" import StringBuilder
from "@std/time.ms" import clock
from "@std/toml.ms" import parse

def document(count: Int) -> String:
    var sb = StringBuilder()
    for i in range(0, count):
        sb.append(f"[item{i}]\nid = {i}\nname = \"user{i}\"\ntags = [\"a\", \"b\"]\n")
    return sb.build()

def parse_ok(text: String) -> Int:
    if parse(text).is_ok():
        return 1

    return 0

# Parses the document 200 times and prints the best run in microseconds.
export def main() -> Int:
    let text = document(2000)
    var best = 1000000000000
    var ok = 0
    for run in range(0, 200):
        let started = clock().now()
        ok = parse_ok(text) + run * 0
        let elapsed = clock().now().difference(started).to_nanoseconds()
        if elapsed < best: best = elapsed

    let _ignored = stdout().write(f"ms toml bytes={text.byte_length()} ok={ok} best_us={best / 1000}\n")
    return 0
