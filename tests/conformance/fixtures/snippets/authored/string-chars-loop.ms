// conform: tags=strings,control-flow,tier-io
// conform: phase=run
// conform: origin=for over String.chars scans bytes: ASCII, multibyte, break, continue, return, nesting
import stdout from "@std/io/io.ms"

fn show(s String) Void:
    var out = ""
    var n = 0

    for c in s.chars():
        out = f"{out}[{c}]"
        n += 1

    _i := stdout().write(f"{out} {n}\n")

fn first_o(s String) Int:
    var at = 0

    for c in s.chars():
        if c == "o":
            return at

        at += 1

    return -1

fn main() Void:
    show("héllo wörld ✓ 😀!")
    show("")
    show("abc")

    _i := stdout().write(f"{first_o("héllo wörld")} {first_o("xyz")}\n")
    var kept List[String] = []

    for c in "añb".chars():
        kept.append(c.clone())
        if c == "b":
            break

    _j := stdout().write(f"{kept.length()} {kept.get(1)}\n")
    var total = 0

    for a in "ab".chars():
        for b in "xé".chars():
            if a == "a":
                continue

            total += 1

    _k := stdout().write(f"{total}\n")
