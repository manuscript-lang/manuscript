# conform: tags=strings,control-flow,tier-io
# conform: phase=run
# conform: origin=for over String.chars scans bytes: ASCII, multibyte, break, continue, return, nesting
import stdout from "@std/io/io.ms"

fn show(s: String) Unit:
    var out = ""
    var n = 0

    for c in s.chars():
        out = "{out}[{c}]"
        n += 1

    let _i = stdout().write("{out} {n}\n")

fn first_o(s: String) Int:
    var at = 0

    for c in s.chars():
        if c == "o":
            return at

        at += 1

    return -1

export fn main() Int:
    show("héllo wörld ✓ 😀!")
    show("")
    show("abc")

    let _i = stdout().write("{first_o("héllo wörld")} {first_o("xyz")}\n")
    var kept: List[String] = []

    for c in "añb".chars():
        kept.append(c.clone())
        if c == "b":
            break

    let _j = stdout().write("{kept.length()} {kept.get(1)}\n")
    var total = 0

    for a in "ab".chars():
        for b in "xé".chars():
            if a == "a":
                continue

            total += 1

    let _k = stdout().write("{total}\n")
    return 0
