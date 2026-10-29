import stdout from "@std/io.ms"
import stdin from "@std/io.ms"
import read_all from "@std/io.ms"
import range from "@std/collections.ms"
import parse_float from "@std/numbers.ms"
import {abs, ceil, floor, infinity, pow, sqrt} from "@std/math.ms"
import from_int from "@std/bigint.ms"

let UPPER_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
let LOWER_LETTERS = "abcdefghijklmnopqrstuvwxyz"
let ASCII_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
let DIGITS = "0123456789"
let OPERATOR_CHARS = "+-*/^&=<>(),"

type Value:
    case Empty
    case Number(value: Float)
    case Text(value: String)
    case Boolean(flag: Bool)
    case Failure(code: String)

type Node:
    case NumberLit(value: Float)
    case TextLit(value: String)
    case BoolLit(flag: Bool)
    case ErrorLit(code: String)
    case RefNode(col: Int, row: Int, valid: Bool)
    case SpanNode(left: Int, top: Int, right: Int, bottom: Int, valid: Bool)
    case UnknownName
    case UnaryNode(op: String, operand: Node)
    case BinaryNode(op: String, left: Node, right: Node)
    case CallNode(name: String, args: List[Node])

type Token:
    kind: String
    text: String
    start: Int
    end: Int

type Address:
    col: Int
    row: Int
    valid: Bool
    col_absolute: Bool
    row_absolute: Bool

type Rect:
    left: Int
    top: Int
    right: Int
    bottom: Int

type SpanInfo:
    state: Int
    rect: Rect

type Item:
    value: Value
    ranged: Bool

type Criterion:
    op: String
    operand: Value

type Split:
    head: String
    rest: String

type Parser:
    tokens: List[Token]
    pos: Int
    failed: Bool

type Collector:
    keys: Set[Int]

type Cell:
    raw: String
    value: Value
    ast: Optional[Node]
    is_formula: Bool
    precedents: List[Int]

type Sheet:
    cells: Map[Int, Cell]
    dependents: Map[Int, Set[Int]]
    evals: Int
    affected: Set[Int]
    tarjan_index: Map[Int, Int]
    tarjan_low: Map[Int, Int]
    tarjan_stack: List[Int]
    tarjan_on: Set[Int]
    tarjan_counter: Int

# ---------- small helpers ----------
fn emit(text: String) Unit:
    stdout().write(text.concat("\n")).get()

fn char_at(chars: List[String], index: Int) String:
    if index >= 0 and index < chars.length():
        return chars.get(index)

    return ""

fn join_range(chars: List[String], start: Int, end: Int) String:
    var text = ""
    let stop = higher_of(0, lower_of(end, chars.length()))
    for i in range(start, stop):
        text = text.concat(chars.get(i))
    return text

fn lower_of(a: Int, b: Int) Int:
    if a < b:
        return a

    return b

fn higher_of(a: Int, b: Int) Int:
    if a > b:
        return a

    return b

fn is_letter(c: String) Bool:
    return not c.is_empty() and ASCII_LETTERS.contains(c)

fn is_digit(c: String) Bool:
    return not c.is_empty() and DIGITS.contains(c)

fn is_identifier_char(c: String) Bool:
    return is_letter(c) or is_digit(c) or c == "_" or c == "."

fn is_space(c: String) Bool:
    return c == " " or c == "\t"

fn key_of(col: Int, row: Int) Int:
    return col * 1000 + row

fn column_name(col: Int) String:
    return UPPER_LETTERS.chars().get(col - 1)

fn letter_index(c: String) Int:
    return UPPER_LETTERS.index_of(c.upper()).get(0) + 1

fn cell_name(key: Int) String:
    return column_name(key / 1000).concat("{key % 1000}")

fn order_key(key: Int) Int:
    return (key % 1000) * 100 + key / 1000

fn text_after(text: String, count: Int) String:
    return text.chars().drop(count).join("")

fn split_words(text: String) List[String]:
    var words: List[String] = []
    var current = ""

    for c in text.chars():
        if is_space(c):
            if not current.is_empty():
                words.append(current)
                current = ""
        else:
            current = current.concat(c)

    if not current.is_empty():
        words.append(current)
    return words

fn split_head(text: String) Split:
    var head = ""
    var rest: List[String] = []
    var seen_space = false

    for c in text.chars():
        if not seen_space and is_space(c):
            seen_space = true
        else if seen_space:
            rest.append(c)
        else:
            head = head.concat(c)

    return Split(head: head, rest: rest.join("").trim())

# ---------- values ----------
fn rank_of(v: Value) Int:
    match v:
        Empty:
            return 0
        Number(x):
            return 1
        Text(s):
            return 2
        Boolean(f):
            return 3
        Failure(code):
            return 4

fn is_failure(v: Value) Bool:
    match v:
        Failure(code):
            return true
        _:
            return false

fn is_blank(v: Value) Bool:
    match v:
        Empty:
            return true
        _:
            return false

fn is_number(v: Value) Bool:
    match v:
        Number(x):
            return true
        _:
            return false

fn is_text(v: Value) Bool:
    match v:
        Text(s):
            return true
        _:
            return false

fn is_true(v: Value) Bool:
    match v:
        Boolean(f):
            return f
        _:
            return false

fn number_of(v: Value) Float:
    match v:
        Number(x):
            return x
        _:
            return 0.0

fn finite_result(r: Float) Value:
    if r.is_finite():
        return Number(value: r)

    return Failure(code: "#NUM!")

# Parses the number grammar [+-]?(digits[.digits]|.digits)([eE][+-]?digits)?
# and returns the value only when it is finite.
fn number_text(text: String) Optional[Float]:
    let chars = text.chars()
    var i = 0
    var sign = ""
    let first = char_at(chars, 0)

    if first == "+" or first == "-":
        if first == "-":
            sign = "-"
        i = 1

    let int_start = i
    while is_digit(char_at(chars, i)):
        i += 1

    let int_part = join_range(chars, int_start, i)
    var frac_part = ""

    if char_at(chars, i) == ".":
        i += 1

        let frac_start = i
        while is_digit(char_at(chars, i)):
            i += 1
        frac_part = join_range(chars, frac_start, i)

    if int_part.is_empty() and frac_part.is_empty():
        return none

    var exponent = ""
    let marker = char_at(chars, i)

    if marker == "e" or marker == "E":
        i += 1

        var exp_sign = ""
        let exp_char = char_at(chars, i)

        if exp_char == "+" or exp_char == "-":
            if exp_char == "-":
                exp_sign = "-"
            i += 1

        let exp_start = i
        while is_digit(char_at(chars, i)):
            i += 1
        if i == exp_start:
            return none

        exponent = "e".concat(exp_sign).concat(join_range(chars, exp_start, i))

    if i != chars.length():
        return none

    let int_text = if_empty(int_part, "0")
    let frac_text = if_empty(frac_part, "0")
    let parsed = parse_float(
        sign.concat(int_text).concat(".").concat(frac_text).concat(exponent)
    )
    if parsed.is_error():
        return none

    let value = parsed.get(0.0)
    if not value.is_finite():
        return none

    return some(value)

fn if_empty(text: String, fallback: String) String:
    if text.is_empty():
        return fallback

    return text

fn to_number(v: Value) Value:
    match v:
        Empty:
            return Number(value: 0.0)
        Number(x):
            return Number(value: x)
        Boolean(f):
            if f:
                return Number(value: 1.0)

            return Number(value: 0.0)
        Text(s):
            let parsed = number_text(s.trim())
            if parsed.is_some():
                return Number(value: parsed.get(0.0))

            return Failure(code: "#VALUE!")
        Failure(code):
            return Failure(code: code)

fn truth_value(v: Value) Value:
    match v:
        Empty:
            return Boolean(flag: false)
        Number(x):
            return Boolean(flag: x != 0.0)
        Boolean(f):
            return Boolean(flag: f)
        Text(s):
            if s.upper() == "TRUE":
                return Boolean(flag: true)
            if s.upper() == "FALSE":
                return Boolean(flag: false)

            return Failure(code: "#VALUE!")
        Failure(code):
            return Failure(code: code)

# Display text of a value (also the string form used by &).
fn text_of(v: Value) String:
    match v:
        Empty:
            return ""
        Number(x):
            return format_number(x)
        Text(s):
            return s
        Boolean(f):
            if f:
                return "TRUE"

            return "FALSE"
        Failure(code):
            return code

fn format_number(x: Float) String:
    if not x.is_finite():
        return "#NUM!"
    if abs(x) >= 1e21:
        return integer_text(x)

    let fixed = x.to_fixed(10).get("0")
    let chars = fixed.chars()
    var last = chars.length() - 1
    while last >= 0 and char_at(chars, last) == "0":
        last -= 1
    if char_at(chars, last) == ".":
        last -= 1

    let text = join_range(chars, 0, last + 1)
    if text == "-0":
        return "0"

    return text

# Exact decimal text of a large integer-valued double.
fn integer_text(x: Float) String:
    var y = abs(x)
    var shift = 0

    for step in range(0, 1100):
        if y >= 9007199254740992.0:
            y = y / 2.0
            shift += 1

    let mantissa = y.truncate_to_int().get(0)
    let power = from_int(2).pow(shift).get()
    let digits = from_int(mantissa).multiply(power).to_string_radix(10)
    if x < 0.0:
        return "-".concat(digits)

    return digits

fn zero_like(v: Value) Value:
    match v:
        Number(x):
            return Number(value: 0.0)
        Text(s):
            return Text(value: "")
        Boolean(f):
            return Boolean(flag: false)
        _:
            return Empty

fn order_of(a: Value, b: Value) Int:
    let ra = rank_of(a)
    let rb = rank_of(b)
    if ra < rb:
        return -1
    if ra > rb:
        return 1

    match a:
        Number(x):
            return x.compare(number_of(b))
        Text(s):
            return sign_of(s.compare(text_of(b)))
        Boolean(f):
            let other = is_true(b)
            if f == other:
                return 0
            if f:
                return 1

            return -1
        _:
            return 0

fn sign_of(n: Int) Int:
    if n < 0:
        return -1
    if n > 0:
        return 1

    return 0

fn holds(op: String, c: Int) Bool:
    if op == "=":
        return c == 0
    if op == "<>":
        return c != 0
    if op == "<":
        return c < 0
    if op == "<=":
        return c <= 0
    if op == ">":
        return c > 0

    return c >= 0

fn is_comparison(op: String) Bool:
    return op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">="

fn normalize_against(v: Value, other: Value) Value:
    if is_blank(v) and not is_blank(other):
        return zero_like(other)

    return v

fn compare_values(op: String, a: Value, b: Value) Value:
    if is_failure(a):
        return a
    if is_failure(b):
        return b

    let left = normalize_against(a, b)
    let right = normalize_against(b, a)
    return Boolean(flag: holds(op, order_of(left, right)))

fn arithmetic(op: String, x: Float, y: Float) Value:
    if op == "+":
        return finite_result(x + y)
    if op == "-":
        return finite_result(x - y)
    if op == "*":
        return finite_result(x * y)

    if op == "/":
        if y == 0.0:
            return Failure(code: "#DIV/0!")

        return finite_result(x / y)

    return finite_result(pow(x, y))

fn round_half_away(v: Float) Float:
    let magnitude = abs(v)
    var whole = floor(magnitude)
    if magnitude - whole >= 0.5:
        whole = whole + 1.0
    if v < 0.0:
        return -whole

    return whole

fn truncate_toward_zero(v: Float) Float:
    if v < 0.0:
        return ceil(v)

    return floor(v)

fn clamp_count(amount: Float, limit: Int) Int:
    if amount >= limit.to_float():
        return limit

    return amount.truncate_to_int().get(0)

fn map_ascii(text: String, to_upper: Bool) String:
    var result = ""

    for c in text.chars():
        var mapped = c

        if to_upper and LOWER_LETTERS.contains(c) and not c.is_empty():
            mapped = UPPER_LETTERS.chars().get(LOWER_LETTERS.index_of(c).get(0))
        else if not to_upper and UPPER_LETTERS.contains(c) and not c.is_empty():
            mapped = LOWER_LETTERS.chars().get(UPPER_LETTERS.index_of(c).get(0))

        result = result.concat(mapped)

    return result

fn collapse_spaces(text: String) String:
    var result = ""
    var pending = false

    for c in text.chars():
        if is_space(c) or c == "\n" or c == "\r" or c == "\u{C}" or c == "\u{B}":
            pending = true
        else:
            if pending and not result.is_empty():
                result = result.concat(" ")
            pending = false
            result = result.concat(c)

    return result

fn criterion_of(v: Value) Criterion:
    match v:
        Text(s):
            var op = "="
            var operand_text = s

            if s.starts_with(">="):
                op = ">="
                operand_text = text_after(s, 2)
            else if s.starts_with("<="):
                op = "<="
                operand_text = text_after(s, 2)
            else if s.starts_with("<>"):
                op = "<>"
                operand_text = text_after(s, 2)
            else if s.starts_with(">"):
                op = ">"
                operand_text = text_after(s, 1)
            else if s.starts_with("<"):
                op = "<"
                operand_text = text_after(s, 1)
            else if s.starts_with("="):
                operand_text = text_after(s, 1)

            let parsed = number_text(operand_text)
            if parsed.is_some():
                return Criterion(op: op, operand: Number(value: parsed.get(0.0)))

            return Criterion(op: op, operand: Text(value: operand_text))
        _:
            return Criterion(op: "=", operand: v)

# ---------- addresses and references ----------
fn parse_address(text: String) Address:
    let chars = text.chars()
    var i = 0
    var col_absolute = false
    var row_absolute = false

    if char_at(chars, 0) == "$":
        col_absolute = true
        i = 1

    let letter_start = i
    while is_letter(char_at(chars, i)):
        i += 1

    let letter_count = i - letter_start

    if char_at(chars, i) == "$":
        row_absolute = true
        i += 1

    let digit_start = i
    while is_digit(char_at(chars, i)):
        i += 1

    let digit_count = i - digit_start
    let valid = (
        letter_count == 1
        and digit_count >= 1
        and digit_count <= 3
        and i == chars.length()
        and char_at(chars, digit_start) != "0"
    )
    if not valid:
        return Address(
            col: 0, row: 0, valid: false, col_absolute: false, row_absolute: false
        )

    var row = 0
    for j in range(digit_start, i):
        row = row * 10 + DIGITS.index_of(char_at(chars, j)).get(0)
    return Address(
        col: letter_index(char_at(chars, letter_start)), row: row, valid: true,
        col_absolute: col_absolute, row_absolute: row_absolute
    )

# Key of a plain cell argument (no $ markers); 0 when invalid.
fn cell_key(text: String) Int:
    if text.contains("$"):
        return 0

    let address = parse_address(text)
    if not address.valid:
        return 0

    return key_of(address.col, address.row)

fn rect_of(a: Int, b: Int) Rect:
    return Rect(
        left: lower_of(a / 1000, b / 1000), top: lower_of(a % 1000, b % 1000),
        right: higher_of(a / 1000, b / 1000), bottom: higher_of(a % 1000, b % 1000)
    )

# Range argument: one cell or two cells joined by a colon.
fn range_arg(text: String) Optional[Rect]:
    let parts = text.split(":")

    if parts.length() == 1:
        let key = cell_key(text)
        if key == 0:
            return none

        return some(rect_of(key, key))

    if parts.length() == 2:
        let a = cell_key(parts.get(0))
        let b = cell_key(parts.get(1))
        if a == 0 or b == 0:
            return none

        return some(rect_of(a, b))

    return none

# ---------- tokenizer ----------
fn reference_end(chars: List[String], start: Int) Int:
    var i = start
    if char_at(chars, i) == "$":
        i += 1

    let letters_start = i
    while is_letter(char_at(chars, i)):
        i += 1
    if i == letters_start:
        return -1

    if char_at(chars, i) == "$":
        i += 1

    let digits_start = i
    while is_digit(char_at(chars, i)):
        i += 1
    if i == digits_start:
        return -1

    let after = char_at(chars, i)
    if is_identifier_char(after) or after == "(" or after == "$":
        return -1

    return i

fn number_end(chars: List[String], start: Int) Int:
    var i = start
    while is_digit(char_at(chars, i)):
        i += 1

    if char_at(chars, i) == ".":
        i += 1
        while is_digit(char_at(chars, i)):
            i += 1

    let marker = char_at(chars, i)

    if marker == "e" or marker == "E":
        var j = i + 1
        let sign = char_at(chars, j)
        if sign == "+" or sign == "-":
            j += 1

        if is_digit(char_at(chars, j)):
            while is_digit(char_at(chars, j)):
                j += 1
            i = j

    return i

# Returns None when the source contains a character that cannot be tokenized.
fn tokenize(chars: List[String]) Optional[List[Token]]:
    var tokens: List[Token] = []
    let n = chars.length()
    var i = 0

    while i < n:
        let c = chars.get(i)

        if is_space(c):
            i += 1
        else if is_digit(c) or (c == "." and is_digit(char_at(chars, i + 1))):
            let end = number_end(chars, i)
            tokens.append(
                Token(
                    kind: "number", text: join_range(chars, i, end), start: i, end: end
                )
            )
            i = end
        else if c == "\"":
            var end = i + 1
            var content = ""
            var closed = false

            while end < n and not closed:
                let d = chars.get(end)

                if d == "\"":
                    if char_at(chars, end + 1) == "\"":
                        content = content.concat("\"")
                        end += 2
                    else:
                        closed = true
                        end += 1
                else:
                    content = content.concat(d)
                    end += 1

            if not closed:
                return none

            tokens.append(Token(kind: "string", text: content, start: i, end: end))
            i = end
        else if is_letter(c) or c == "_" or c == "$":
            let first_end = reference_end(chars, i)

            if first_end > 0:
                var end = first_end
                var kind = "reference"

                if char_at(chars, end) == ":":
                    let second_end = reference_end(chars, end + 1)

                    if second_end > 0:
                        end = second_end
                        kind = "span"

                tokens.append(
                    Token(
                        kind: kind, text: join_range(chars, i, end), start: i, end: end
                    )
                )
                i = end
            else if is_letter(c) or c == "_":
                var end = i + 1
                while is_identifier_char(char_at(chars, end)):
                    end += 1
                tokens.append(
                    Token(
                        kind: "identifier", text: join_range(chars, i, end), start: i,
                        end: end
                    )
                )
                i = end
            else:
                return none
        else if c == "#" and join_range(chars, i, i + 5) == "#REF!":
            tokens.append(Token(kind: "error", text: "#REF!", start: i, end: i + 5))
            i += 5
        else:
            let two = join_range(chars, i, i + 2)

            if two == "<>" or two == "<=" or two == ">=":
                tokens.append(Token(kind: "op", text: two, start: i, end: i + 2))
                i += 2
            else if OPERATOR_CHARS.contains(c):
                tokens.append(Token(kind: "op", text: c, start: i, end: i + 1))
                i += 1
            else:
                return none

    return some(tokens)

# ---------- parser ----------
fn span_node(text: String) Node:
    let parts = text.split(":")
    let a = parse_address(parts.get(0))
    let b = parse_address(parts.get(1))
    if not (a.valid and b.valid):
        return SpanNode(left: 0, top: 0, right: 0, bottom: 0, valid: false)

    return SpanNode(
        left: lower_of(a.col, b.col), top: lower_of(a.row, b.row),
        right: higher_of(a.col, b.col), bottom: higher_of(a.row, b.row), valid: true
    )

impl Parser:
    fn current_op() String:
        if self.pos >= self.tokens.length():
            return ""

        let token = self.tokens.get(self.pos)
        if token.kind == "op":
            return token.text

        return ""

    fn at_end() Bool:
        return self.pos >= self.tokens.length()

    var fn advance() Unit:
        self.pos += 1

    var fn parse_comparison() Node:
        var left = self.parse_concat()

        while is_comparison(self.current_op()):
            let op = self.current_op()
            self.advance()

            let right = self.parse_concat()
            left = BinaryNode(op: op, left: left, right: right)

        return left

    var fn parse_concat() Node:
        var left = self.parse_additive()

        while self.current_op() == "&":
            self.advance()

            let right = self.parse_additive()
            left = BinaryNode(op: "&", left: left, right: right)

        return left

    var fn parse_additive() Node:
        var left = self.parse_multiplicative()

        while self.current_op() == "+" or self.current_op() == "-":
            let op = self.current_op()
            self.advance()

            let right = self.parse_multiplicative()
            left = BinaryNode(op: op, left: left, right: right)

        return left

    var fn parse_multiplicative() Node:
        var left = self.parse_unary()

        while self.current_op() == "*" or self.current_op() == "/":
            let op = self.current_op()
            self.advance()

            let right = self.parse_unary()
            left = BinaryNode(op: op, left: left, right: right)

        return left

    var fn parse_unary() Node:
        let op = self.current_op()

        if op == "+" or op == "-":
            self.advance()

            let operand = self.parse_unary()
            return UnaryNode(op: op, operand: operand)

        return self.parse_power()

    var fn parse_power() Node:
        let base = self.parse_primary()

        if self.current_op() == "^":
            self.advance()

            let exponent = self.parse_exponent()
            return BinaryNode(op: "^", left: base, right: exponent)

        return base

    var fn parse_exponent() Node:
        let op = self.current_op()

        if op == "+" or op == "-":
            self.advance()

            let operand = self.parse_exponent()
            return UnaryNode(op: op, operand: operand)

        return self.parse_power()

    var fn parse_primary() Node:
        if self.at_end():
            self.failed = true
            return NumberLit(value: 0.0)

        let token = self.tokens.get(self.pos)
        self.advance()

        if token.kind == "number":
            let parsed = number_text(token.text)
            if parsed.is_some():
                return NumberLit(value: parsed.get(0.0))

            return NumberLit(value: infinity())

        if token.kind == "string":
            return TextLit(value: token.text)
        if token.kind == "error":
            return ErrorLit(code: token.text)

        if token.kind == "reference":
            let address = parse_address(token.text)
            return RefNode(col: address.col, row: address.row, valid: address.valid)

        if token.kind == "span":
            return span_node(token.text)

        if token.kind == "identifier":
            if self.current_op() == "(":
                self.advance()
                return self.parse_call(token.text)

            let upper = token.text.upper()
            if upper == "TRUE":
                return BoolLit(flag: true)
            if upper == "FALSE":
                return BoolLit(flag: false)

            return UnknownName

        if token.kind == "op" and token.text == "(":
            let inner = self.parse_comparison()

            if self.current_op() == ")":
                self.advance()
            else:
                self.failed = true

            return inner

        self.failed = true
        return NumberLit(value: 0.0)

    var fn parse_call(name: String) Node:
        var args: List[Node] = []

        if self.current_op() == ")":
            self.advance()
            return CallNode(name: name, args: args)

        var more = true

        while more and not self.failed:
            args.append(self.parse_comparison())

            if self.current_op() == ",":
                self.advance()
            else if self.current_op() == ")":
                self.advance()
                more = false
            else:
                self.failed = true
                more = false

        return CallNode(name: name, args: args)

# Parses formula source (the text after '='); None means #PARSE!.
fn parse_formula(source: List[String]) Optional[Node]:
    if let tokens = tokenize(source):
        var parser = Parser(tokens: tokens, pos: 0, failed: false)
        let node = parser.parse_comparison()
        if parser.failed or parser.pos != parser.tokens.length():
            return none

        return some(node)

    return none

impl Collector:
    # Gathers the cells a formula depends on; ROW and COLUMN arguments are not dependencies.
    var fn visit(node: Node) Unit:
        match node:
            RefNode(col, row, valid):
                if valid:
                    self.keys.add(key_of(col, row))
            SpanNode(left, top, right, bottom, valid):
                if valid:
                    for r in range(top, bottom + 1):
                        for c in range(left, right + 1):
                            self.keys.add(key_of(c, r))
            UnaryNode(op, operand):
                self.visit(operand)
            BinaryNode(op, left, right):
                self.visit(left)
                self.visit(right)
            CallNode(name, args):
                let upper = name.upper()
                if upper != "ROW" and upper != "COLUMN":
                    for arg in args:
                        self.visit(arg)
            _:
                return

fn precedents_of(node: Node) List[Int]:
    var collector = Collector(keys: Set[Int]())
    collector.visit(node)
    return collector.keys.values()

# Shifts a formula (raw text starting with '=') for copy; tokens keep their text.
fn shift_formula(raw: String, column_shift: Int, row_shift: Int) String:
    let source = raw.chars().drop(1)

    if let tokens = tokenize(source):
        var out = "="
        var position = 0

        for token in tokens:
            out = out.concat(join_range(source, position, token.start))

            if token.kind == "reference":
                out = out.concat(shift_reference(token.text, column_shift, row_shift))
            else if token.kind == "span":
                out = out.concat(shift_span(token.text, column_shift, row_shift))
            else:
                out = out.concat(join_range(source, token.start, token.end))

            position = token.end

        out = out.concat(join_range(source, position, source.length()))
        return out

    return raw

fn shift_address(address: Address, column_shift: Int, row_shift: Int) Optional[String]:
    var col = address.col
    if not address.col_absolute:
        col = address.col + column_shift

    var row = address.row
    if not address.row_absolute:
        row = address.row + row_shift
    if col < 1 or col > 26 or row < 1 or row > 999:
        return none

    var text = ""
    if address.col_absolute:
        text = "$"
    text = text.concat(column_name(col))
    if address.row_absolute:
        text = text.concat("$")
    return some(text.concat("{row}"))

fn shift_reference(text: String, column_shift: Int, row_shift: Int) String:
    let address = parse_address(text)
    if not address.valid:
        return text

    let moved = shift_address(address, column_shift, row_shift)
    if moved.is_none():
        return "#REF!"

    return moved.get("")

fn shift_span(text: String, column_shift: Int, row_shift: Int) String:
    let parts = text.split(":")
    var first = parts.get(0)
    var second = parts.get(1)
    let a = parse_address(first)

    if a.valid:
        let moved = shift_address(a, column_shift, row_shift)
        if moved.is_none():
            return "#REF!"

        first = moved.get("")

    let b = parse_address(second)

    if b.valid:
        let moved = shift_address(b, column_shift, row_shift)
        if moved.is_none():
            return "#REF!"

        second = moved.get("")

    return first.concat(":").concat(second)

# ---------- CSV ----------
fn parse_csv(block: List[String]) List[List[String]]:
    var records: List[List[String]] = []
    var fields: List[String] = []
    var field = ""
    var quoted = false
    var has_chars = false
    var skip_next = false
    let chars = block.join("\n").chars()
    let n = chars.length()

    for i in range(0, n):
        let c = chars.get(i)

        if skip_next:
            skip_next = false
        else if quoted:
            if c == "\"":
                if char_at(chars, i + 1) == "\"":
                    field = field.concat("\"")
                    skip_next = true
                else:
                    quoted = false
            else:
                field = field.concat(c)
        else if c == "\n":
            if has_chars:
                fields.append(field)
                records.append(fields)

            fields = []
            field = ""
            has_chars = false
        else if c != "\r":
            has_chars = true

            if c == "\"":
                quoted = true
            else if c == ",":
                fields.append(field)
                field = ""
            else:
                field = field.concat(c)

    if has_chars:
        fields.append(field)
        records.append(fields)

    return records

fn blank_cell() Cell:
    return Cell(raw: "", value: Empty, ast: none, is_formula: false, precedents: [])

fn with_value(cell: Cell, value: Value) Cell:
    let ast = cell.ast.clone().clone()
    let precedents = cell.precedents.clone()
    return Cell(
        raw: cell.raw, value: value, ast: ast, is_formula: cell.is_formula,
        precedents: precedents
    )

# Value of a constant cell, from its trimmed raw text.
fn constant_value(text: String) Value:
    if text.starts_with("'"):
        return Text(value: text_after(text, 1))

    let parsed = number_text(text)
    if parsed.is_some():
        return Number(value: parsed.get(0.0))
    if text.upper() == "TRUE":
        return Boolean(flag: true)
    if text.upper() == "FALSE":
        return Boolean(flag: false)

    return Text(value: text)

fn csv_field(text: String) String:
    if (
        text.contains(",")
        or text.contains("\"")
        or text.contains("\n")
        or text.contains("\r")
        or text.starts_with(" ")
        or text.ends_with(" ")
    ):
        return "\"".concat(text.replace_all("\"", "\"\"").get("")).concat("\"")

    return text

# ---------- sheet ----------
impl Sheet:
    fn value_at(key: Int) Value:
        if let cell = self.cells.get(key):
            return cell.value

        return Empty

    fn raw_at(key: Int) String:
        if let cell = self.cells.get(key):
            return cell.raw

        return ""

    fn display_at(key: Int) String:
        return text_of(self.value_at(key))

    fn is_formula_at(key: Int) Bool:
        if let cell = self.cells.get(key):
            return cell.is_formula

        return false

    fn dependents_of(key: Int) Set[Int]:
        return self.dependents.get(key).get(Set[Int]())

    var fn link(from: Int, to: Int) Unit:
        var deps = self.dependents_of(from)
        deps.add(to)
        self.dependents.add(from, deps)

    var fn unlink(key: Int) Unit:
        if let old = self.cells.get(key):
            if old.is_formula:
                for p in old.precedents:
                    var deps = self.dependents_of(p)
                    deps.remove(key)
                    self.dependents.add(p, deps)

    # Stores a cell from its raw VALUE text without recalculating.
    var fn assign(key: Int, raw: String) Unit:
        self.unlink(key)

        let text = raw.trim()

        if text.is_empty():
            self.cells.remove(key)
            return

        if text.starts_with("="):
            let parsed = parse_formula(text.chars().drop(1))
            var precedents: List[Int] = []
            if let node = parsed.clone():
                precedents = precedents_of(node.clone())
            for p in precedents:
                self.link(p, key)
            self.cells.add(
                key,
                Cell(
                    raw: text, value: Empty, ast: parsed, is_formula: true,
                    precedents: precedents
                )
            )
        else:
            self.cells.add(
                key,
                Cell(
                    raw: text, value: constant_value(text), ast: none,
                    is_formula: false, precedents: []
                )
            )

    fn eval(node: Node) Value:
        match node:
            NumberLit(value):
                if value.is_finite():
                    return Number(value: value)

                return Failure(code: "#NUM!")
            TextLit(text):
                return Text(value: text)
            BoolLit(flag):
                return Boolean(flag: flag)
            ErrorLit(code):
                return Failure(code: code)
            RefNode(col, row, valid):
                if valid:
                    return self.value_at(key_of(col, row))

                return Failure(code: "#REF!")
            SpanNode(left, top, right, bottom, valid):
                return Failure(code: "#VALUE!")
            UnknownName:
                return Failure(code: "#NAME?")
            UnaryNode(op, operand):
                return self.unary(op, operand)
            BinaryNode(op, left, right):
                return self.binary(op, left, right)
            CallNode(name, args):
                return self.call(name, args)

    fn unary(op: String, operand: Node) Value:
        let x = to_number(self.eval(operand))
        if is_failure(x):
            return x
        if op == "-":
            return Number(value: 0.0 - number_of(x))

        return x

    fn binary(op: String, left: Node, right: Node) Value:
        let a = self.eval(left)
        let b = self.eval(right)

        if op == "&":
            if is_failure(a):
                return a
            if is_failure(b):
                return b

            return Text(value: text_of(a).concat(text_of(b)))

        if is_comparison(op):
            return compare_values(op, a, b)

        let x = to_number(a)
        if is_failure(x):
            return x

        let y = to_number(b)
        if is_failure(y):
            return y

        return arithmetic(op, number_of(x), number_of(y))

    # Items of the aggregate arguments: range cells are ranged items, anything else is a direct item.
    fn items_of(args: List[Node]) List[Item]:
        var items: List[Item] = []

        for arg in args:
            let info = span_info(arg.clone())

            if info.state == 0:
                items.append(Item(value: self.eval(arg), ranged: false))
            else if info.state == 1:
                items.append(Item(value: Failure(code: "#REF!"), ranged: false))
            else:
                for r in range(info.rect.top, info.rect.bottom + 1):
                    for c in range(info.rect.left, info.rect.right + 1):
                        items.append(
                            Item(
                                value: self.value_at(
                                    key_of(c, r)
                                ),
                                ranged: true
                            )
                        )

        return items

    fn aggregate(kind: String, args: List[Node]) Value:
        if args.is_empty():
            return Failure(code: "#VALUE!")

        var numbers: List[Float] = []

        for item in self.items_of(args):
            if is_failure(item.value):
                return item.value

            if item.ranged:
                if is_number(item.value):
                    numbers.append(number_of(item.value))
            else:
                let coerced = to_number(item.value)
                if is_failure(coerced):
                    return coerced

                numbers.append(number_of(coerced))

        if kind == "SUM":
            var total = 0.0
            for x in numbers:
                total += x
            return finite_result(total)

        if kind == "PRODUCT":
            if numbers.is_empty():
                return Number(value: 0.0)

            var product = 1.0
            for x in numbers:
                product *= x
            return finite_result(product)

        if numbers.is_empty():
            if kind == "AVERAGE":
                return Failure(code: "#DIV/0!")
            if kind == "MEDIAN":
                return Failure(code: "#NUM!")

            return Number(value: 0.0)

        if kind == "AVERAGE":
            var total = 0.0
            for x in numbers:
                total += x
            return finite_result(total / numbers.length().to_float())

        if kind == "MIN" or kind == "MAX":
            var best = numbers.get(0)

            for x in numbers:
                if kind == "MIN" and x < best:
                    best = x
                if kind == "MAX" and x > best:
                    best = x

            return Number(value: best)

        let sorted = numbers.sorted(fn(a: Float, b: Float) Int: return a.compare(b))
        let count = sorted.length()
        if count % 2 == 1:
            return Number(value: sorted.get(count / 2))

        return finite_result((sorted.get(count / 2 - 1) + sorted.get(count / 2)) / 2.0)

    fn count_items(kind: String, args: List[Node]) Value:
        if args.is_empty():
            return Failure(code: "#VALUE!")

        var count = 0

        for item in self.items_of(args):
            if kind == "COUNT":
                if is_number(item.value):
                    count += 1
            else if not is_blank(item.value):
                count += 1

        return Number(value: count.to_float())

    fn logic(is_and: Bool, args: List[Node]) Value:
        if args.is_empty():
            return Failure(code: "#VALUE!")

        var result = is_and
        var took = 0

        for item in self.items_of(args):
            if is_failure(item.value):
                return item.value

            var skip = false
            if item.ranged:
                skip = is_text(item.value) or is_blank(item.value)

            if not skip:
                let t = truth_value(item.value)
                if is_failure(t):
                    return t

                took += 1

                if is_and:
                    result = result and is_true(t)
                else:
                    result = result or is_true(t)

        if took == 0:
            return Failure(code: "#VALUE!")

        return Boolean(flag: result)

    fn row_or_column(by_row: Bool, node: Node) Value:
        match node:
            RefNode(col, row, valid):
                if not valid:
                    return Failure(code: "#REF!")
                if by_row:
                    return Number(value: row.to_float())

                return Number(value: col.to_float())
            SpanNode(left, top, right, bottom, valid):
                if not valid:
                    return Failure(code: "#REF!")
                if by_row:
                    return Number(value: top.to_float())

                return Number(value: left.to_float())
            _:
                return Failure(code: "#VALUE!")

    fn index_call(args: List[Node]) Value:
        if args.length() < 2 or args.length() > 3:
            return Failure(code: "#VALUE!")

        let info = span_info(args.get(0).clone())
        if info.state == 0:
            return Failure(code: "#VALUE!")
        if info.state == 1:
            return Failure(code: "#REF!")

        let rect = info.rect
        let height = rect.bottom - rect.top + 1
        let width = rect.right - rect.left + 1
        let first = to_number(self.eval(args.get(1).clone()))
        if is_failure(first):
            return first

        var row_index = floor(number_of(first))
        var col_index = 1.0

        if args.length() == 3:
            let second = to_number(self.eval(args.get(2).clone()))
            if is_failure(second):
                return second

            col_index = floor(number_of(second))
        else if height == 1:
            col_index = row_index
            row_index = 1.0

        if (
            row_index < 1.0
            or row_index > height.to_float()
            or col_index < 1.0
            or col_index > width.to_float()
        ):
            return Failure(code: "#REF!")

        let row = rect.top + row_index.truncate_to_int().get(0) - 1
        let col = rect.left + col_index.truncate_to_int().get(0) - 1
        return self.value_at(key_of(col, row))

    fn countif_call(args: List[Node]) Value:
        if args.length() != 2:
            return Failure(code: "#VALUE!")

        let info = span_info(args.get(0).clone())
        if info.state == 0:
            return Failure(code: "#VALUE!")
        if info.state == 1:
            return Failure(code: "#REF!")

        let criterion_value = self.eval(args.get(1).clone())
        if is_failure(criterion_value):
            return criterion_value

        let criterion = criterion_of(criterion_value)
        var count = 0

        for r in range(info.rect.top, info.rect.bottom + 1):
            for c in range(info.rect.left, info.rect.right + 1):
                let v = self.value_at(key_of(c, r))

                if rank_of(v) == rank_of(criterion.operand):
                    if holds(criterion.op, order_of(v, criterion.operand)):
                        count += 1
                else if criterion.op == "<>" and not is_blank(v):
                    count += 1

        return Number(value: count.to_float())

    fn call(name: String, args: List[Node]) Value:
        let fname = name.upper()
        if (
            fname == "SUM"
            or fname == "AVERAGE"
            or fname == "MIN"
            or fname == "MAX"
            or fname == "PRODUCT"
            or fname == "MEDIAN"
        ):
            return self.aggregate(fname, args)
        if fname == "COUNT" or fname == "COUNTA":
            return self.count_items(fname, args)
        if fname == "AND" or fname == "OR":
            return self.logic(fname == "AND", args)
        if fname == "INDEX":
            return self.index_call(args)
        if fname == "COUNTIF":
            return self.countif_call(args)

        if fname == "ROW" or fname == "COLUMN":
            if args.length() != 1:
                return Failure(code: "#VALUE!")

            return self.row_or_column(fname == "ROW", args.get(0).clone())

        if fname == "IF":
            if args.length() < 2 or args.length() > 3:
                return Failure(code: "#VALUE!")

            let condition = truth_value(self.eval(args.get(0).clone()))
            if is_failure(condition):
                return condition
            if is_true(condition):
                return self.eval(args.get(1).clone())
            if args.length() == 3:
                return self.eval(args.get(2).clone())

            return Boolean(flag: false)

        if fname == "IFERROR":
            if args.length() != 2:
                return Failure(code: "#VALUE!")

            let attempt = self.eval(args.get(0).clone())
            if is_failure(attempt):
                return self.eval(args.get(1).clone())

            return attempt

        if fname == "CHOOSE":
            if args.length() < 2:
                return Failure(code: "#VALUE!")

            let index = to_number(self.eval(args.get(0).clone()))
            if is_failure(index):
                return index

            let position = floor(number_of(index))
            if position < 1.0 or position > (args.length() - 1).to_float():
                return Failure(code: "#VALUE!")

            let chosen = position.truncate_to_int().get(0)
            return self.eval(args.get(chosen).clone())

        if fname == "NOT":
            if args.length() != 1:
                return Failure(code: "#VALUE!")

            let t = truth_value(self.eval(args.get(0).clone()))
            if is_failure(t):
                return t

            return Boolean(flag: not is_true(t))

        if fname == "ABS" or fname == "INT" or fname == "SQRT":
            if args.length() != 1:
                return Failure(code: "#VALUE!")

            let x = to_number(self.eval(args.get(0).clone()))
            if is_failure(x):
                return x

            let n = number_of(x)
            if fname == "ABS":
                return Number(value: abs(n))
            if fname == "INT":
                return Number(value: floor(n))
            if n < 0.0:
                return Failure(code: "#NUM!")

            return Number(value: sqrt(n))

        if fname == "POW" or fname == "MOD":
            if args.length() != 2:
                return Failure(code: "#VALUE!")

            let a = to_number(self.eval(args.get(0).clone()))
            if is_failure(a):
                return a

            let b = to_number(self.eval(args.get(1).clone()))
            if is_failure(b):
                return b
            if fname == "POW":
                return arithmetic("^", number_of(a), number_of(b))

            let divisor = number_of(b)
            if divisor == 0.0:
                return Failure(code: "#DIV/0!")

            let dividend = number_of(a)
            return finite_result(dividend - divisor * floor(dividend / divisor))

        if fname == "ROUND":
            if args.length() < 1 or args.length() > 2:
                return Failure(code: "#VALUE!")

            let x = to_number(self.eval(args.get(0).clone()))
            if is_failure(x):
                return x

            var digits = 0.0

            if args.length() == 2:
                let d = to_number(self.eval(args.get(1).clone()))
                if is_failure(d):
                    return d

                digits = number_of(d)

            let places = truncate_toward_zero(digits)
            if abs(places) > 15.0:
                return Failure(code: "#NUM!")

            let scale = pow(10.0, places)
            return finite_result(round_half_away(number_of(x) * scale) / scale)

        if fname == "LEN" or fname == "UPPER" or fname == "LOWER" or fname == "TRIM":
            if args.length() != 1:
                return Failure(code: "#VALUE!")

            let v = self.eval(args.get(0).clone())
            if is_failure(v):
                return v

            let text = text_of(v)
            if fname == "LEN":
                return Number(value: text.scalar_length().to_float())
            if fname == "UPPER":
                return Text(value: map_ascii(text, true))
            if fname == "LOWER":
                return Text(value: map_ascii(text, false))

            return Text(value: collapse_spaces(text))

        if fname == "LEFT" or fname == "RIGHT":
            if args.length() < 1 or args.length() > 2:
                return Failure(code: "#VALUE!")

            let s = self.eval(args.get(0).clone())
            if is_failure(s):
                return s

            var count = 1.0

            if args.length() == 2:
                let n = to_number(self.eval(args.get(1).clone()))
                if is_failure(n):
                    return n

                count = floor(number_of(n))

            if count < 0.0:
                return Failure(code: "#VALUE!")

            let chars = text_of(s).chars()
            let taken = clamp_count(count, chars.length())
            if fname == "LEFT":
                return Text(value: chars.take(taken).join(""))

            return Text(value: chars.drop(chars.length() - taken).join(""))

        if fname == "MID":
            if args.length() != 3:
                return Failure(code: "#VALUE!")

            let s = self.eval(args.get(0).clone())
            if is_failure(s):
                return s

            let start_value = to_number(self.eval(args.get(1).clone()))
            if is_failure(start_value):
                return start_value

            let size_value = to_number(self.eval(args.get(2).clone()))
            if is_failure(size_value):
                return size_value

            let start = floor(number_of(start_value))
            let size = floor(number_of(size_value))
            if start < 1.0 or size < 0.0:
                return Failure(code: "#VALUE!")

            let chars = text_of(s).chars()
            let total = chars.length()
            if start > total.to_float():
                return Text(value: "")

            let from = start.truncate_to_int().get(0) - 1
            let count = clamp_count(size, total - from)
            return Text(value: chars.drop(from).take(count).join(""))

        if fname == "CONCAT":
            if args.is_empty():
                return Failure(code: "#VALUE!")

            var text = ""

            for item in self.items_of(args):
                if is_failure(item.value):
                    return item.value

                text = text.concat(text_of(item.value))

            return Text(value: text)

        if fname == "SUBSTITUTE":
            if args.length() != 3:
                return Failure(code: "#VALUE!")

            let s = self.eval(args.get(0).clone())
            if is_failure(s):
                return s

            let old = self.eval(args.get(1).clone())
            if is_failure(old):
                return old

            let replacement = self.eval(args.get(2).clone())
            if is_failure(replacement):
                return replacement

            let old_text = text_of(old)
            if old_text.is_empty():
                return Text(value: text_of(s))

            return Text(
                value: text_of(s).replace_all(
                    old_text, text_of(replacement)
                ).get("")
            )

        if fname == "VALUE":
            if args.length() != 1:
                return Failure(code: "#VALUE!")

            return to_number(self.eval(args.get(0).clone()))

        if (
            fname == "ISERROR"
            or fname == "ISBLANK"
            or fname == "ISNUMBER"
            or fname == "ISTEXT"
        ):
            if args.length() != 1:
                return Failure(code: "#VALUE!")

            let v = self.eval(args.get(0).clone())
            if fname == "ISERROR":
                return Boolean(flag: is_failure(v))
            if fname == "ISBLANK":
                return Boolean(flag: is_blank(v))
            if fname == "ISNUMBER":
                return Boolean(flag: is_number(v))

            return Boolean(flag: is_text(v))

        return Failure(code: "#NAME?")

    fn compute(key: Int) Value:
        if let cell = self.cells.get(key):
            if let ast = cell.ast.clone():
                let v = self.eval(ast.clone())
                if is_blank(v):
                    return Number(value: 0.0)

                return v

            return Failure(code: "#PARSE!")

        return Empty

    var fn store_value(key: Int, value: Value) Unit:
        if self.cells.contains(key):
            let cell = self.cells.get(key).get(blank_cell()).clone()
            self.cells.add(key, with_value(cell, value))

    fn successors(key: Int) List[Int]:
        var result: List[Int] = []
        if let cell = self.cells.get(key):
            for p in cell.precedents:
                if self.affected.contains(p):
                    result.append(p)
        return result

    fn has_self_loop(key: Int) Bool:
        if let cell = self.cells.get(key):
            return cell.precedents.contains(key)

        return false

    fn low_of(key: Int) Int:
        return self.tarjan_low.get(key).get(0)

    fn index_of_node(key: Int) Int:
        return self.tarjan_index.get(key).get(0)

    var fn strong_connect(key: Int) Unit:
        self.tarjan_index.add(key, self.tarjan_counter)
        self.tarjan_low.add(key, self.tarjan_counter)
        self.tarjan_counter += 1
        self.tarjan_stack.append(key)
        self.tarjan_on.add(key)

        for w in self.successors(key):
            if not self.tarjan_index.contains(w):
                self.strong_connect(w)
                self.tarjan_low.add(key, lower_of(self.low_of(key), self.low_of(w)))
            else if self.tarjan_on.contains(w):
                self.tarjan_low.add(
                    key,
                    lower_of(
                        self.low_of(key), self.index_of_node(w)
                    )
                )

        if self.low_of(key) == self.index_of_node(key):
            self.emit_component(key)

    # Tarjan emits components after their precedents, so evaluation order is correct.
    var fn emit_component(key: Int) Unit:
        let position = self.tarjan_stack.index_of(key).get(0)
        let members = self.tarjan_stack.drop(position)
        self.tarjan_stack = self.tarjan_stack.take(position)
        for m in members:
            self.tarjan_on.remove(m)

        if members.length() > 1 or self.has_self_loop(key):
            for m in members:
                self.store_value(m, Failure(code: "#CYCLE!"))
        else:
            self.store_value(key, self.compute(key))

    # Recalculates everything affected by the changed cells; returns the number of affected formulas.
    var fn recalc(changed: List[Int]) Int:
        var visited = Set[Int]()
        var queue: List[Int] = []

        for k in changed:
            if not visited.contains(k):
                visited.add(k)
                queue.append(k)

        var head = 0

        while head < queue.length():
            let k = queue.get(head)
            head += 1

            for d in self.dependents_of(k).values():
                if not visited.contains(d):
                    visited.add(d)
                    queue.append(d)

        var affected = Set[Int]()
        for k in queue:
            if self.is_formula_at(k):
                affected.add(k)
        self.affected = affected.clone()
        self.tarjan_index = Map[Int, Int]()
        self.tarjan_low = Map[Int, Int]()
        self.tarjan_stack = []
        self.tarjan_on = Set[Int]()
        self.tarjan_counter = 0
        for k in affected.values():
            if not self.tarjan_index.contains(k):
                self.strong_connect(k)

        let count = affected.length()
        self.evals += count
        return count

    var fn execute(command: String, rest: String, block: List[String]) Unit:
        if command == "set":
            self.set_command(rest)
        else if command == "clear":
            self.clear_command(rest)
        else if command == "get":
            self.get_command(rest)
        else if command == "show":
            self.show_command(rest)
        else if command == "print":
            self.print_command(rest)
        else if command == "export":
            self.export_command(rest)
        else if command == "copy":
            self.copy_command(rest)
        else if command == "import":
            self.import_command(rest, block)
        else if command == "precedents":
            self.precedents_command(rest)
        else if command == "dependents":
            self.dependents_command(rest)
        else if command == "stats":
            self.stats_command()
        else:
            emit("error: unknown command '{command}'")

    var fn set_command(rest: String) Unit:
        if rest.is_empty():
            emit("error: usage: set CELL VALUE")
            return

        let split = split_head(rest)
        let key = cell_key(split.head)

        if key == 0:
            emit("error: bad cell reference '{split.head}'")
            return

        self.assign(key, split.rest)
        emit("recalc {self.recalc([key])}")

    var fn clear_command(rest: String) Unit:
        let words = split_words(rest)

        if words.length() != 1:
            emit("error: usage: clear CELL")
            return

        let key = cell_key(words.get(0))

        if key == 0:
            emit("error: bad cell reference '{words.get(0)}'")
            return

        self.assign(key, "")
        emit("recalc {self.recalc([key])}")

    fn get_command(rest: String) Unit:
        let words = split_words(rest)

        if words.length() != 1:
            emit("error: usage: get CELL")
            return

        let key = cell_key(words.get(0))

        if key == 0:
            emit("error: bad cell reference '{words.get(0)}'")
            return

        if self.cells.contains(key):
            emit(self.display_at(key))
        else:
            emit("(empty)")

    fn show_command(rest: String) Unit:
        let words = split_words(rest)

        if words.length() != 1:
            emit("error: usage: show CELL")
            return

        let key = cell_key(words.get(0))

        if key == 0:
            emit("error: bad cell reference '{words.get(0)}'")
            return

        let name = cell_name(key)

        if let cell = self.cells.get(key):
            if cell.is_formula:
                emit("{name}: {cell.raw} => {self.display_at(key)}")
            else:
                emit("{name}: {cell.raw}")
        else:
            emit("{name}: (empty)")

    # Bounding rectangle of the non-empty cells; None when the sheet is empty.
    fn used_rect() Optional[Rect]:
        var max_col = 0
        var max_row = 0

        for k in self.cells.keys():
            max_col = higher_of(max_col, k / 1000)
            max_row = higher_of(max_row, k % 1000)

        if max_col == 0:
            return none

        return some(Rect(left: 1, top: 1, right: max_col, bottom: max_row))

    fn print_command(rest: String) Unit:
        let words = split_words(rest)

        if words.length() > 1 or (words.length() == 1 and words.get(0) == "formulas"):
            emit("error: usage: print [RANGE]")
            return

        var rect = self.used_rect()

        if words.length() == 1:
            rect = range_arg(words.get(0))

            if rect.is_none():
                emit("error: bad range '{words.get(0)}'")
                return

        if rect.is_none():
            emit("(empty sheet)")
            return

        let area = rect.get(Rect(left: 1, top: 1, right: 1, bottom: 1))

        for r in range(area.top, area.bottom + 1):
            var fields: List[String] = []
            for c in range(area.left, area.right + 1):
                fields.append(self.display_at(key_of(c, r)))
            emit(fields.join(" | "))

    fn export_command(rest: String) Unit:
        let words = split_words(rest)
        var formulas = false
        var mode_seen = false
        var range_text = ""
        var range_seen = false

        if words.length() > 2:
            emit("error: usage: export [formulas] [RANGE]")
            return

        for word in words:
            if word == "formulas" or word == "values":
                if mode_seen:
                    emit("error: usage: export [formulas] [RANGE]")
                    return

                mode_seen = true
                formulas = word == "formulas"
            else:
                if range_seen:
                    emit("error: usage: export [formulas] [RANGE]")
                    return

                range_seen = true
                range_text = word

        var rect = self.used_rect()

        if range_seen:
            rect = range_arg(range_text)

            if rect.is_none():
                emit("error: bad range '{range_text}'")
                return

        if rect.is_none():
            emit("(empty sheet)")
            return

        let area = rect.get(Rect(left: 1, top: 1, right: 1, bottom: 1))

        for r in range(area.top, area.bottom + 1):
            var fields: List[String] = []

            for c in range(area.left, area.right + 1):
                let key = key_of(c, r)

                if formulas:
                    fields.append(csv_field(self.raw_at(key)))
                else:
                    fields.append(csv_field(self.display_at(key)))

            emit(fields.join(","))

    var fn copy_command(rest: String) Unit:
        let words = split_words(rest)

        if words.length() != 2:
            emit("error: usage: copy SRC DST")
            return

        let source = cell_key(words.get(0))

        if source == 0:
            emit("error: bad cell reference '{words.get(0)}'")
            return

        let target = range_arg(words.get(1))

        if target.is_none():
            emit("error: bad range '{words.get(1)}'")
            return

        let area = target.get(Rect(left: 1, top: 1, right: 1, bottom: 1))
        let raw = self.raw_at(source)
        let formula = self.is_formula_at(source)
        let source_col = source / 1000
        let source_row = source % 1000
        var keys: List[Int] = []

        for r in range(area.top, area.bottom + 1):
            for c in range(area.left, area.right + 1):
                let destination = key_of(c, r)
                var text = raw
                if formula:
                    text = shift_formula(raw, c - source_col, r - source_row)
                self.assign(destination, text)
                keys.append(destination)

        emit("recalc {self.recalc(keys)}")

    var fn import_command(rest: String, block: List[String]) Unit:
        let words = split_words(rest)

        if words.length() != 1:
            emit("error: usage: import CELL")
            return

        let origin = cell_key(words.get(0))

        if origin == 0:
            emit("error: bad cell reference '{words.get(0)}'")
            return

        let records = parse_csv(block)
        var columns = 0
        for record in records:
            columns = higher_of(columns, record.length())

        let rows = records.length()
        let first_col = origin / 1000
        let first_row = origin % 1000

        if first_col + columns - 1 > 26 or first_row + rows - 1 > 999:
            emit("error: import out of range")
            return

        var keys: List[Int] = []

        for i in range(0, rows):
            let record = records.get(i)

            for j in range(0, record.length()):
                let destination = key_of(first_col + j, first_row + i)
                self.assign(destination, record.get(j).trim())
                keys.append(destination)

        let count = self.recalc(keys)
        emit("imported {rows} rows, {columns} columns; recalc {count}")

    fn precedents_command(rest: String) Unit:
        let words = split_words(rest)

        if words.length() != 1:
            emit("error: usage: precedents CELL")
            return

        let key = cell_key(words.get(0))

        if key == 0:
            emit("error: bad cell reference '{words.get(0)}'")
            return

        var found: List[Int] = []
        if let cell = self.cells.get(key):
            if cell.is_formula:
                found = cell.precedents.clone()
        emit(self.names_or_none(found))

    fn dependents_command(rest: String) Unit:
        let words = split_words(rest)

        if words.length() != 1:
            emit("error: usage: dependents CELL")
            return

        let key = cell_key(words.get(0))

        if key == 0:
            emit("error: bad cell reference '{words.get(0)}'")
            return

        var seen = Set[Int]()
        var queue: List[Int] = self.dependents_of(key).values()
        var head = 0

        while head < queue.length():
            let k = queue.get(head)
            head += 1

            if not seen.contains(k):
                seen.add(k)
                for d in self.dependents_of(k).values():
                    queue.append(d)

        emit(self.names_or_none(seen.values()))

    fn names_or_none(keys: List[Int]) String:
        if keys.is_empty():
            return "(none)"

        let sorted = keys.sorted(
            fn(a: Int, b: Int) Int: return order_key(a).compare(
                order_key(b)
            )
        )
        var names: List[String] = []
        for k in sorted:
            names.append(cell_name(k))
        return names.join(" ")

    fn stats_command() Unit:
        var formulas = 0
        for k in self.cells.keys():
            if self.is_formula_at(k):
                formulas += 1
        emit("cells {self.cells.length()} formulas {formulas} evals {self.evals}")

# Classifies a function argument: 0 not a range, 1 range with an invalid corner, 2 valid range.
fn span_info(node: Node) SpanInfo:
    match node:
        SpanNode(left, top, right, bottom, valid):
            if valid:
                return SpanInfo(
                    state: 2,
                    rect: Rect(
                        left: left, top: top, right: right, bottom: bottom
                    )
                )

            return SpanInfo(state: 1, rect: Rect(left: 0, top: 0, right: 0, bottom: 0))
        _:
            return SpanInfo(state: 0, rect: Rect(left: 0, top: 0, right: 0, bottom: 0))

export fn main() Int:
    let data = read_all(stdin(), none).get()
    let lines = data.decode_utf8().get("").lines()
    var sheet = Sheet(
        cells: Map[Int, Cell](), dependents: Map[Int, Set[Int]](), evals: 0,
        affected: Set[Int](), tarjan_index: Map[Int, Int](),
        tarjan_low: Map[Int, Int](), tarjan_stack: [], tarjan_on: Set[Int](),
        tarjan_counter: 0
    )
    var index = 0

    while index < lines.length():
        let line = lines.get(index)
        index += 1

        let trimmed = line.trim()

        if not trimmed.is_empty() and not trimmed.starts_with("#"):
            emit("> {line.trim_end()}")

            let split = split_head(trimmed)
            var block: List[String] = []

            if split.head == "import":
                let start = index
                while index < lines.length() and lines.get(index) != ".":
                    index += 1
                block = lines.drop(start).take(index - start)
                if index < lines.length():
                    index += 1

            sheet.execute(split.head, split.rest, block)

    return 0
