import stdout from "@std/io.ms"
import stdin from "@std/io.ms"
import read_lines from "@std/streams.ms"

# Recursive-descent parser over the token list. Syntax errors set `bad`; division by zero sets `div0`
# and keeps evaluating, so a later syntax error still takes precedence.
type Parser:
    toks: List[String]
    pos: Int
    div0: Bool
    bad: Bool

impl Parser:
    fn peek_is(op: String) Bool:
        return self.pos < self.toks.length() and self.toks[self.pos] == op

    var fn expr() Int:
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

    var fn term() Int:
        var v = self.unary()

        while self.peek_is("*") or self.peek_is("/"):
            let op = self.toks[self.pos]
            self.pos += 1
            let r = self.unary()

            if op == "*":
                v = v * r
            else if r == 0:
                self.div0 = true
                v = 0
            else:
                v = v / r

        return v

    var fn unary() Int:
        if self.peek_is("-"):
            self.pos += 1
            return 0 - self.unary()

        return self.primary()

    var fn primary() Int:
        if self.pos >= self.toks.length():
            self.bad = true
            return 0

        let t = self.toks[self.pos]
        self.pos += 1

        if t == "(":
            let v = self.expr()

            if self.peek_is(")"):
                self.pos += 1
            else:
                self.bad = true

            return v

        if let n = t.parse_int():
            return n

        self.bad = true
        return 0

fn tokenize(line: String) Parser:
    var p = Parser(toks: [], pos: 0, div0: false, bad: false)
    var in_num = false

    for c in line.chars():
        if c == " " or c == "\t":
            in_num = false
        else if "0123456789".chars().contains(c):
            if in_num:
                let last = p.toks.length() - 1
                p.toks[last] = p.toks[last] + c
            else:
                p.toks.append(c)

            in_num = true
        else if "+-*/()".chars().contains(c):
            p.toks.append(c)
            in_num = false
        else:
            p.bad = true

    return p

# Returns the output line for one input line, or "" when the input line is blank.
fn answer(line: String) String:
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

    return "{v}"

export fn main() Int:
    var out = stdout()

    for line in read_lines(stdin()).get():
        let s = answer(line)
        if not s.is_empty():
            out.write("{s}\n").get()

    return 0
