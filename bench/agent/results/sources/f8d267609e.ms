import stdin from "@std/io/io.ms"
import stdout from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

// Result of parsing a fragment starting at token index `pos`.
// `ok` false means a syntax error; `divz` records a division by zero
// seen anywhere in the fragment (syntax errors take priority over it).
type Step:
    value: Int
    pos: Int
    ok: Bool
    divz: Bool

fn bad(pos: Int) Step:
    return Step(value: 0, pos: pos, ok: false, divz: false)

fn is_at(toks: List[String], i: Int, s: String) Bool:
    return i < toks.length() and toks[i] == s

fn tokenize(s: String) List[String]:
    var toks = List[String]()
    var num = ""

    for c in s.chars():
        if c.parse_int().is_some():
            num += c
        else:
            if num.length() > 0:
                toks.append(num.clone())
                num = ""

            if c != " " and c != "\t" and c != "\r":
                toks.append(c.clone())

    if num.length() > 0:
        toks.append(num.clone())
    return toks

fn primary(toks: List[String], pos: Int) Step:
    if pos >= toks.length():
        return bad(pos)

    if is_at(toks, pos, "("):
        let inner = expr(toks, pos + 1)
        if not inner.ok:
            return inner
        if is_at(toks, inner.pos, ")"):
            return Step(
                value: inner.value, pos: inner.pos + 1, ok: true, divz: inner.divz
            )

        return bad(inner.pos)

    if let v = toks[pos].parse_int():
        return Step(value: v, pos: pos + 1, ok: true, divz: false)

    return bad(pos)

fn unary(toks: List[String], pos: Int) Step:
    if is_at(toks, pos, "-"):
        let s = unary(toks, pos + 1)
        return Step(value: 0 - s.value, pos: s.pos, ok: s.ok, divz: s.divz)

    return primary(toks, pos)

fn term(toks: List[String], pos: Int) Step:
    var cur = unary(toks, pos)

    while cur.ok and (is_at(toks, cur.pos, "*") or is_at(toks, cur.pos, "/")):
        let mul = is_at(toks, cur.pos, "*")
        let nxt = unary(toks, cur.pos + 1)
        var dz = cur.divz or nxt.divz
        var v = 0

        if mul:
            v = cur.value * nxt.value
        else if nxt.value == 0:
            dz = true
        else:
            v = cur.value / nxt.value

        cur = Step(value: v, pos: nxt.pos, ok: nxt.ok, divz: dz)

    return cur

fn expr(toks: List[String], pos: Int) Step:
    var cur = term(toks, pos)

    while cur.ok and (is_at(toks, cur.pos, "+") or is_at(toks, cur.pos, "-")):
        let plus = is_at(toks, cur.pos, "+")
        let nxt = term(toks, cur.pos + 1)
        var v = 0

        if plus:
            v = cur.value + nxt.value
        else:
            v = cur.value - nxt.value

        cur = Step(value: v, pos: nxt.pos, ok: nxt.ok, divz: cur.divz or nxt.divz)

    return cur

fn evaluate(line: String) String:
    let toks = tokenize(line)
    if toks.length() == 0:
        return ""

    let st = expr(toks, 0)
    if not st.ok or st.pos != toks.length():
        return "error: syntax"
    if st.divz:
        return "error: division by zero"

    return "{st.value}"

fn run() Unit!:
    for line in stdin() | lines:
        let out = evaluate(line)
        if out.length() > 0:
            try stdout().write("{out}\n")

    return ok(unit)

export fn main() Int:
    if let _ = run():
        return 0

    return 1
