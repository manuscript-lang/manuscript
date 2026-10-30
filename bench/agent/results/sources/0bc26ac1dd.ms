import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

let DIGITS = "0123456789"
let OPERATORS = "+-*/()"

# Splits a line into number, operator and parenthesis tokens; none on an unknown character.
fn tokenize(line: String) Optional[List[String]]:
    let cs = line.chars()
    var toks = List[String]()
    var i = 0

    while i < cs.length():
        let c = cs[i]

        if c == " " or c == "\t":
            i += 1
        else if DIGITS.contains(c):
            var num = ""

            while i < cs.length() and DIGITS.contains(cs[i]):
                num = num + cs[i]
                i += 1

            toks.append(num)
        else if OPERATORS.contains(c):
            toks.append(c.clone())
            i += 1
        else:
            return none

    return some(toks)

type Parser:
    toks: List[String]
    pos: Int
    bad: Bool
    div_zero: Bool

impl Parser:
    fn at_end() Bool:
        return self.pos >= self.toks.length()

    var fn expr() Int:
        var v = self.term()

        while not self.bad and not self.at_end():
            let op = self.toks[self.pos].clone()
            if op != "+" and op != "-":
                break

            self.pos += 1

            let r = self.term()

            if op == "+":
                v = v + r
            else:
                v = v - r

        return v

    var fn term() Int:
        var v = self.unary()

        while not self.bad and not self.at_end():
            let op = self.toks[self.pos].clone()
            if op != "*" and op != "/":
                break

            self.pos += 1

            let r = self.unary()

            if op == "*":
                v = v * r
            else if r == 0:
                # Keep parsing so a later syntax error still wins.
                self.div_zero = true
            else:
                v = v / r

        return v

    var fn unary() Int:
        if not self.at_end() and self.toks[self.pos] == "-":
            self.pos += 1
            return 0 - self.unary()

        return self.primary()

    var fn primary() Int:
        if self.at_end():
            self.bad = true
            return 0

        let t = self.toks[self.pos].clone()
        self.pos += 1

        if t == "(":
            let v = self.expr()

            if self.bad or self.at_end() or self.toks[self.pos] != ")":
                self.bad = true
                return 0

            self.pos += 1
            return v

        if DIGITS.contains(t.get(0)):
            if let v = t.parse_int():
                return v
        self.bad = true
        return 0

fn evaluate(toks: List[String]) String:
    var p = Parser(toks: toks, pos: 0, bad: false, div_zero: false)
    let v = p.expr()
    if p.bad or not p.at_end():
        return "error: syntax"
    if p.div_zero:
        return "error: division by zero"

    return "{v}"

export fn main() Int:
    let lines = read_lines(stdin()).get()

    for line in lines:
        if let toks = tokenize(line):
            if toks.length() > 0:
                stdout().write("{evaluate(toks)}\n").get()
        else:
            stdout().write("error: syntax\n").get()

    return 0
