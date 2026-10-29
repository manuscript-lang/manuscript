import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

# One lexical token: `kind` is "num", "op" (`+ - * /`), "lp", "rp", or "bad".
type Tok:
    kind: String
    text: String

# Result of parsing a sub-expression starting at a token index.
# `ok` is False on a syntax error; `div0` records a division by zero that was evaluated.
type Res:
    ok: Bool
    value: Int
    pos: Int
    div0: Bool

fn bad() Res: Res(ok: false, value: 0, pos: 0, div0: false)

fn tokenize(line: String) List[Tok]:
    var toks = List[Tok]()
    var digits = ""

    for c in line.chars():
        if "0123456789".contains(c):
            digits += c
            continue

        if digits.length() > 0:
            toks.append(Tok(kind: "num", text: digits))
            digits = ""

        if c == " " or c == "\t":
            continue

        if "+-*/".contains(c):
            toks.append(Tok(kind: "op", text: c))
        else if c == "(":
            toks.append(Tok(kind: "lp", text: c))
        else if c == ")":
            toks.append(Tok(kind: "rp", text: c))
        else:
            toks.append(Tok(kind: "bad", text: c))

    if digits.length() > 0:
        toks.append(Tok(kind: "num", text: digits))
    return toks

fn has_op(toks: List[Tok], pos: Int, ops: String) Bool:
    return (
        pos < toks.length()
        and toks[pos].kind == "op"
        and ops.contains(toks[pos].text)
    )

fn parse_primary(toks: List[Tok], pos: Int) Res:
    if pos >= toks.length():
        return bad()

    let t = toks[pos]
    if t.kind == "num":
        return Res(
            ok: true, value: t.text.parse_int().get(0), pos: pos + 1, div0: false
        )

    if t.kind == "lp":
        let inner = parse_expr(toks, pos + 1)
        if not inner.ok or inner.pos >= toks.length() or toks[inner.pos].kind != "rp":
            return bad()

        return Res(ok: true, value: inner.value, pos: inner.pos + 1, div0: inner.div0)

    return bad()

fn parse_unary(toks: List[Tok], pos: Int) Res:
    if has_op(toks, pos, "-"):
        let r = parse_unary(toks, pos + 1)
        if not r.ok:
            return r

        return Res(ok: true, value: 0 - r.value, pos: r.pos, div0: r.div0)

    return parse_primary(toks, pos)

fn parse_term(toks: List[Tok], pos: Int) Res:
    var cur = parse_unary(toks, pos)

    while cur.ok and has_op(toks, cur.pos, "*/"):
        let op = toks[cur.pos].text
        let r = parse_unary(toks, cur.pos + 1)
        if not r.ok:
            return r

        var value = 0
        var div0 = cur.div0 or r.div0

        if op == "*":
            value = cur.value * r.value
        else if r.value == 0:
            div0 = true
        else:
            value = cur.value / r.value

        cur = Res(ok: true, value: value, pos: r.pos, div0: div0)

    return cur

fn parse_expr(toks: List[Tok], pos: Int) Res:
    var cur = parse_term(toks, pos)

    while cur.ok and has_op(toks, cur.pos, "+-"):
        let op = toks[cur.pos].text
        let r = parse_term(toks, cur.pos + 1)
        if not r.ok:
            return r

        var value = cur.value + r.value
        if op == "-":
            value = cur.value - r.value
        cur = Res(ok: true, value: value, pos: r.pos, div0: cur.div0 or r.div0)

    return cur

fn evaluate(line: String) String:
    let toks = tokenize(line)
    let r = parse_expr(toks, 0)
    if not r.ok or r.pos != toks.length():
        return "error: syntax"
    if r.div0:
        return "error: division by zero"

    return "{r.value}"

export fn main() Int:
    var out = stdout()

    for line in read_lines(stdin()).get():
        let text = line.trim()
        if text.length() == 0:
            continue

        out.write("{evaluate(text)}\n").get()

    return 0
