from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines

let DIGITS = "0123456789"

# Splits one line into number tokens and operator tokens; `none` means an unknown character.
def tokenize(line: String) -> Optional[List[String]]:
    var tokens = List[String]()
    var digits = ""

    for c in line.chars():
        if DIGITS.contains(c):
            digits += c
            continue

        if digits != "":
            tokens.append(digits)
            digits = ""

        if c == " " or c == "\t" or c == "\r":
            continue

        if c == "+" or c == "-" or c == "*" or c == "/" or c == "(" or c == ")":
            tokens.append(c)
        else:
            return none

    if digits != "":
        tokens.append(digits)
    return tokens

# Recursive-descent parser. Division by zero is only recorded, so that a syntax error anywhere in
# the line still takes precedence over it.
type Parser:
    tokens: List[String]
    pos: Int
    failed: Bool
    div_zero: Bool

impl Parser:
    def peek() -> String:
        if self.pos < self.tokens.length(): return self.tokens[self.pos].clone()

        return ""

    var def expr() -> Int:
        var value = self.term()

        while self.peek() == "+" or self.peek() == "-":
            let op = self.peek()
            self.pos += 1

            let rhs = self.term()

            value = value + rhs if op == "+" else value - rhs

        return value

    var def term() -> Int:
        var value = self.unary()

        while self.peek() == "*" or self.peek() == "/":
            let op = self.peek()
            self.pos += 1

            let rhs = self.unary()

            if op == "*":
                value = value * rhs
            elif rhs == 0:
                self.div_zero = True
                value = 0
            else:
                value = value / rhs

        return value

    var def unary() -> Int:
        if self.peek() == "-":
            self.pos += 1
            return -self.unary()

        return self.primary()

    var def primary() -> Int:
        let tok = self.peek()

        if tok == "(":
            self.pos += 1

            let value = self.expr()

            if self.peek() == ")":
                self.pos += 1
            else:
                self.failed = True

            return value

        if tok != "" and DIGITS.contains(tok.get(0)):
            self.pos += 1
            return tok.parse_int().get(0)

        self.failed = True
        return 0

# Returns the output line for one tokenized input line.
def evaluate(tokens: List[String]) -> String:
    let count = tokens.length()
    var parser = Parser(tokens: tokens, pos: 0, failed: False, div_zero: False)
    let value = parser.expr()
    if parser.failed or parser.pos != count:
        return "error: syntax"
    if parser.div_zero:
        return "error: division by zero"

    return f"{value}"

export def main() -> Int:
    for line in read_lines(stdin()).get():
        if let tokens = tokenize(line):
            if tokens.length() > 0:
                stdout().write(f"{evaluate(tokens)}\n").get()
        else:
            stdout().write("error: syntax\n").get()

    return 0
