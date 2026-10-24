from "@std/io.ms" import stdout
from "@std/io.ms" import stdin
from "@std/streams.ms" import read_lines

# Recursive-descent parser over the token list. Syntax errors set `bad`; division by zero sets `div0`
# and keeps evaluating, so a later syntax error still takes precedence.
type Parser:
    toks: List[String]
    pos: Int
    div0: Bool
    bad: Bool

impl Parser:
    def peek_is(op: String) -> Bool:
        return self.pos < self.toks.length() and self.toks[self.pos] == op

    var def expr() -> Int:
        var v = self.term()

        while self.peek_is("+") or self.peek_is("-"):
            let op = self.toks[self.pos]
            self.pos += 1

            let r = self.term()

            if op == "+":
                v = v + r
            else:
                v = v - r

        return v

    var def term() -> Int:
        var v = self.unary()

        while self.peek_is("*") or self.peek_is("/"):
            let op = self.toks[self.pos]
            self.pos += 1

            let r = self.unary()

            if op == "*":
                v = v * r
            elif r == 0:
                self.div0 = True
                v = 0
            else:
                v = v / r

        return v

    var def unary() -> Int:
        if self.peek_is("-"):
            self.pos += 1
            return 0 - self.unary()

        return self.primary()

    var def primary() -> Int:
        if self.pos >= self.toks.length():
            self.bad = True
            return 0

        let t = self.toks[self.pos]
        self.pos += 1

        if t == "(":
            let v = self.expr()

            if self.peek_is(")"):
                self.pos += 1
            else:
                self.bad = True

            return v

        if let n = t.parse_int():
            return n

        self.bad = True
        return 0

def tokenize(line: String) -> Parser:
    var p = Parser(toks: [], pos: 0, div0: False, bad: False)
    var in_num = False

    for c in line.chars():
        if c == " " or c == "\t":
            in_num = False
        elif "0123456789".chars().contains(c):
            if in_num:
                let last = p.toks.length() - 1
                p.toks[last] = p.toks[last] + c
            else:
                p.toks.append(c)

            in_num = True
        elif "+-*/()".chars().contains(c):
            p.toks.append(c)
            in_num = False
        else:
            p.bad = True

    return p

# Returns the output line for one input line, or "" when the input line is blank.
def answer(line: String) -> String:
    var p = tokenize(line)
    if p.bad:
        return "error: syntax"
    if p.toks.is_empty():
        return ""

    let v = p.expr()
    if p.bad or p.pos != p.toks.length():
        return "error: syntax"
    if p.div0:
        return "error: division by zero"

    return f"{v}"

export def main() -> Int:
    var out = stdout()

    for line in read_lines(stdin()).get():
        let s = answer(line)
        if not s.is_empty():
            out.write(f"{s}\n").get()

    return 0
