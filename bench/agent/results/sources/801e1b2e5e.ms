import read_all, stdin, stdout from "@std/io.ms"

type Token:
    case Num(value: Int)
    case Op(symbol: String)

type Parsed:
    value: Int
    next: Int
    zero_division: Bool

# Splits one line into tokens; `none` means an unknown character was found.
fn tokenize(line: String) Optional[List[Token]]:
    var tokens = List[Token]()
    var value = 0
    var in_number = false

    for code in line.scalar_values():
        if code >= 48 and code <= 57:
            value = value * 10 + (code - 48)
            in_number = true
        else:
            if in_number:
                tokens.append(Num(value: value))
                value = 0
                in_number = false

            if code == 43:
                tokens.append(Op(symbol: "+"))
            else if code == 45:
                tokens.append(Op(symbol: "-"))
            else if code == 42:
                tokens.append(Op(symbol: "*"))
            else if code == 47:
                tokens.append(Op(symbol: "/"))
            else if code == 40:
                tokens.append(Op(symbol: "("))
            else if code == 41:
                tokens.append(Op(symbol: ")"))
            else if code != 32 and code != 9:
                return none

    if in_number:
        tokens.append(Num(value: value))
    return some(tokens)

fn number_at(tokens: List[Token], pos: Int) Optional[Int]:
    if pos >= tokens.length():
        return none

    match tokens.get(pos):
        Num(value):
            return some(value)
        _:
            return none

fn symbol_at(tokens: List[Token], pos: Int) String:
    if pos >= tokens.length():
        return ""

    match tokens.get(pos):
        Op(symbol):
            return symbol
        _:
            return ""

fn parse_primary(tokens: List[Token], pos: Int) Optional[Parsed]:
    if let value = number_at(tokens, pos):
        return some(Parsed(value: value, next: pos + 1, zero_division: false))
    if symbol_at(tokens, pos) != "(":
        return none

    if let inner = parse_sum(tokens, pos + 1):
        if symbol_at(tokens, inner.next) == ")":
            return some(
                Parsed(
                    value: inner.value, next: inner.next + 1,
                    zero_division: inner.zero_division
                )
            )
    return none

fn parse_unary(tokens: List[Token], pos: Int) Optional[Parsed]:
    if symbol_at(tokens, pos) == "-":
        if let operand = parse_unary(tokens, pos + 1):
            return some(
                Parsed(
                    value: 0 - operand.value, next: operand.next,
                    zero_division: operand.zero_division
                )
            )

        return none

    return parse_primary(tokens, pos)

fn product_rest(tokens: List[Token], left: Parsed) Optional[Parsed]:
    let symbol = symbol_at(tokens, left.next)
    if symbol != "*" and symbol != "/":
        return some(left)

    if let right = parse_unary(tokens, left.next + 1):
        let zero = left.zero_division or right.zero_division
        if symbol == "*":
            return product_rest(
                tokens,
                Parsed(
                    value: left.value * right.value, next: right.next,
                    zero_division: zero
                )
            )
        if right.value == 0:
            return product_rest(
                tokens, Parsed(value: 0, next: right.next, zero_division: true)
            )

        return product_rest(
            tokens,
            Parsed(
                value: left.value / right.value, next: right.next, zero_division: zero
            )
        )

    return none

fn parse_product(tokens: List[Token], pos: Int) Optional[Parsed]:
    if let first = parse_unary(tokens, pos):
        return product_rest(tokens, first)

    return none

fn sum_rest(tokens: List[Token], left: Parsed) Optional[Parsed]:
    let symbol = symbol_at(tokens, left.next)
    if symbol != "+" and symbol != "-":
        return some(left)

    if let right = parse_product(tokens, left.next + 1):
        let zero = left.zero_division or right.zero_division
        if symbol == "+":
            return sum_rest(
                tokens,
                Parsed(
                    value: left.value + right.value, next: right.next,
                    zero_division: zero
                )
            )

        return sum_rest(
            tokens,
            Parsed(
                value: left.value - right.value, next: right.next, zero_division: zero
            )
        )

    return none

fn parse_sum(tokens: List[Token], pos: Int) Optional[Parsed]:
    if let first = parse_product(tokens, pos):
        return sum_rest(tokens, first)

    return none

# Returns the output line for one non-blank input line.
fn evaluate(line: String) String:
    if let tokens = tokenize(line):
        if let parsed = parse_sum(tokens, 0):
            if parsed.next == tokens.length():
                if parsed.zero_division:
                    return "error: division by zero"

                return "{parsed.value}"

    return "error: syntax"

export fn main() Int:
    let bytes = read_all(stdin()).get()
    let text = bytes.decode_utf8().get("")
    var output = List[String]()

    for line in text.lines():
        if line.trim() == "":
            continue

        output.append(evaluate(line))

    if output.length() > 0:
        stdout().write("{output.join("\n")}\n").get()
        stdout().flush().get()

    return 0
