import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Calc:
    toks: List[String]
    pos: Int
    bad: Bool
    div_zero: Bool

fn is_digit(c: String) Bool:
    return "0123456789".contains(c)

fn tokenize(line: String) Calc:
    var calc = Calc(toks: List[String](), pos: 0, bad: false, div_zero: false)
    var cur = ""

    for c in line.chars():
        if is_digit(c):
            cur += c
            continue

        if cur.length() > 0:
            calc.toks.append(cur)
            cur = ""

        if c == " " or c == "\t" or c == "\r":
            continue

        if "+-*/()".contains(c):
            calc.toks.append(c)
        else:
            calc.bad = true

    if cur.length() > 0:
        calc.toks.append(cur)
    return calc

impl Calc:
    fn at(t: String) Bool:
        return self.pos < self.toks.length() and self.toks[self.pos] == t

    var fn expr() Int:
        var v = self.term()

        while self.at("+") or self.at("-"):
            let op = self.toks[self.pos].clone()
            self.pos += 1

            let r = self.term()

            if op == "+":
                v = v + r
            else:
                v = v - r

        return v

    var fn term() Int:
        var v = self.unary()

        while self.at("*") or self.at("/"):
            let op = self.toks[self.pos].clone()
            self.pos += 1

            let r = self.unary()

            if op == "*":
                v = v * r
            else if r == 0:
                self.div_zero = true
                v = 0
            else:
                v = v / r

        return v

    var fn unary() Int:
        if self.at("-"):
            self.pos += 1
            return -self.unary()

        return self.primary()

    var fn primary() Int:
        if self.pos >= self.toks.length():
            self.bad = true
            return 0

        let t = self.toks[self.pos].clone()
        self.pos += 1

        if t == "(":
            let v = self.expr()

            if self.at(")"):
                self.pos += 1
            else:
                self.bad = true

            return v

        if is_digit(t.get(0)):
            return t.parse_int().get(0)

        self.bad = true
        return 0

fn evaluate(line: String) Optional[String]:
    var calc = tokenize(line)
    if calc.toks.length() == 0 and not calc.bad:
        return none
    if calc.bad:
        return some("error: syntax")

    let v = calc.expr()
    if calc.bad or calc.pos != calc.toks.length():
        return some("error: syntax")
    if calc.div_zero:
        return some("error: division by zero")

    return some("{v}")

export fn main() Int:
    var out = stdout()
    for line in read_lines(stdin()).get():
        if let text = evaluate(line):
            out.write("{text}\n").get()
    out.flush().get()
    return 0
