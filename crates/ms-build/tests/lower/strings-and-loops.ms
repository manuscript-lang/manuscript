# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "msrt_string_concat"
# expect-mir: "iadd.chk"

from "@std/io.ms" import stdout

export def main() -> Int:
    var total = 0
    for x in [1, 2, 3]:
        total += x
    let r = stdout().write(f"total {total}\n")
    return 0
