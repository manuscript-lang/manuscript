import lines from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"

// Token codes: 0 '+', 1 '-', 2 '*', 3 '/', 4 '(', 5 ')', 6 number, -1 invalid.
type Ps:
    codes: List[Int]
    vals: List[Int]
    pos: Int
    div0: Bool
    bad: Bool

fn cur(p: Ps) Int:
    if p.pos < p.codes.length():
        return p.codes[p.pos]

    return -2

fn primary(var p: Ps) Int:
    let c = cur(p)

    if c == 6:
        let v = p.vals[p.pos]
        p.pos += 1
        return v

    if c == 4:
        p.pos += 1

        let v = expr(var p)

        if cur(p) == 5:
            p.pos += 1
        else:
            p.bad = true

        return v

    p.bad = true
    return 0

fn unary(var p: Ps) Int:
    if cur(p) == 1:
        p.pos += 1
        return -unary(var p)

    return primary(var p)

fn term(var p: Ps) Int:
    var v = unary(var p)

    while cur(p) == 2 or cur(p) == 3:
        let op = cur(p)
        p.pos += 1

        let r = unary(var p)

        if op == 2:
            v = v * r
        else if r == 0:
            p.div0 = true
            v = 0
        else:
            v = v / r

    return v

fn expr(var p: Ps) Int:
    var v = term(var p)

    while cur(p) == 0 or cur(p) == 1:
        let op = cur(p)
        p.pos += 1

        let r = term(var p)

        if op == 0:
            v = v + r
        else:
            v = v - r

    return v

fn op_code(ch: String) Int:
    if ch == "+":
        return 0
    if ch == "-":
        return 1
    if ch == "*":
        return 2
    if ch == "/":
        return 3
    if ch == "(":
        return 4
    if ch == ")":
        return 5
    if ch == " " or ch == "\t":
        return -3

    return -1

fn eval_line(line: String) String:
    var codes = List[Int]()
    var vals = List[Int]()
    var num = 0
    var in_num = false

    for ch in line.chars():
        if let d = ch.parse_int():
            num = num * 10 + d
            in_num = true
        else:
            if in_num:
                codes.append(6)
                vals.append(num)
                num = 0
                in_num = false

            let code = op_code(ch)

            if code != -3:
                codes.append(code)
                vals.append(0)

    if in_num:
        codes.append(6)
        vals.append(num)

    var p = Ps(codes: codes, vals: vals, pos: 0, div0: false, bad: false)
    let v = expr(var p)
    if p.bad or p.pos != p.codes.length():
        return "error: syntax"
    if p.div0:
        return "error: division by zero"

    return "{v}"

fn run() Unit!:
    for line in stdin() | lines:
        if line.trim().length() > 0:
            print(eval_line(line))
    return ok(unit)

export fn main() Int:
    run().get()
    return 0
