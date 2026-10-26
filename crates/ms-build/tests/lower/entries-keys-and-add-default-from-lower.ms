# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "msrt_map_contains"

from "@std/io.ms" import stdout

export def main() -> Int:
    var m: Map[String, Int] = Map()
    m.add_default_from("a", lambda (key: String): 5)
    let items = [4, 5]
    let r = stdout().write(f"{items.keys()} {items.entries().length()}\n")
    return 0
