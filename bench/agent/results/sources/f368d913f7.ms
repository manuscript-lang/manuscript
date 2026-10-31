import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Token:
    case Number(value: Int)
    case Symbol(text: String)
    case Invalid

type Parsed:
    value: Int
    next: Int
    failed: Bool
    div_zero: Bool

fn failed() Parsed:
    return Parsed(value: 0, next: 0, failed: true, div_zero: false)

fn tokenize(chars: List[String]) List[Token]:
    var tokens = List[Token]()
    var i = 0

    while i < chars.length():
        let c = chars[i]
        let digit = c.parse_int().get(-1)

        if c == " " or c == "\t":
            i += 1
        else if digit >= 0:
            var value = 0

            while i < chars.length() and chars[i].parse_int().get(-1) >= 0:
                value = value * 10 + chars[i].parse_int().get(0)
                i += 1

            tokens.append(Number(value))
        else if c == "+" or c == "-" or c == "*" or c == "/" or c == "(" or c == ")":
            tokens.append(Symbol(c))
            i += 1
        else:
            tokens.append(Invalid)
            i += 1

    return tokens

fn symbol_at(tokens: List[Token], pos: Int) String:
    if pos >= tokens.length():
        return ""

    match tokens[pos]:
        Symbol(text):
            return text
        _:
            return ""

fn parse_primary(tokens: List[Token], pos: Int) Parsed:
    if pos >= tokens.length():
        return failed()

    if symbol_at(tokens, pos) == "(":
        let inner = parse_expr(tokens, pos + 1)
        if inner.failed or symbol_at(tokens, inner.next) != ")":
            return failed()

        return Parsed(
            value: inner.value, next: inner.next + 1, failed: false,
            div_zero: inner.div_zero
        )

    match tokens[pos]:
        Number(value):
            return Parsed(value: value, next: pos + 1, failed: false, div_zero: false)
        _:
            return failed()

fn parse_unary(tokens: List[Token], pos: Int) Parsed:
    if symbol_at(tokens, pos) == "-":
        let inner = parse_unary(tokens, pos + 1)
        if inner.failed:
            return inner

        return Parsed(
            value: -inner.value, next: inner.next, failed: false,
            div_zero: inner.div_zero
        )

    return parse_primary(tokens, pos)

fn parse_term(tokens: List[Token], pos: Int) Parsed:
    let first = parse_unary(tokens, pos)
    if first.failed:
        return first

    var value = 0
    var next = 0
    var div_zero = false
    value = first.value
    next = first.next
    div_zero = first.div_zero

    while symbol_at(tokens, next) == "*" or symbol_at(tokens, next) == "/":
        let op = symbol_at(tokens, next)
        let right = parse_unary(tokens, next + 1)
        if right.failed:
            return right

        div_zero = div_zero or right.div_zero

        if op == "*":
            value = value * right.value
        else if right.value == 0:
            div_zero = true
            value = 0
        else:
            value = value / right.value

        next = right.next

    return Parsed(value: value, next: next, failed: false, div_zero: div_zero)

fn parse_expr(tokens: List[Token], pos: Int) Parsed:
    let first = parse_term(tokens, pos)
    if first.failed:
        return first

    var value = 0
    var next = 0
    var div_zero = false
    value = first.value
    next = first.next
    div_zero = first.div_zero

    while symbol_at(tokens, next) == "+" or symbol_at(tokens, next) == "-":
        let op = symbol_at(tokens, next)
        let right = parse_term(tokens, next + 1)
        if right.failed:
            return right

        div_zero = div_zero or right.div_zero

        if op == "+":
            value = value + right.value
        else:
            value = value - right.value

        next = right.next

    return Parsed(value: value, next: next, failed: false, div_zero: div_zero)

fn evaluate(line: String) String:
    let tokens = tokenize(line.chars())
    let parsed = parse_expr(tokens, 0)
    if parsed.failed or parsed.next != tokens.length():
        return "error: syntax"
    if parsed.div_zero:
        return "error: division by zero"

    return "{parsed.value}"

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var out = stdout()

    for line in lines:
        if line.trim().is_empty():
            continue

        out.write(evaluate(line) + "\n").get()

    return 0
