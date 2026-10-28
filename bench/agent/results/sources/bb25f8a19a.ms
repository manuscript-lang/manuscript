from "@std/io.ms" import stdin, stdout
from "@std/math.ms" import floor, pow, sqrt
from "@std/streams.ms" import read_lines

# A cell value. kind is "empty", "num", "text", "bool" or "err"; text holds
# the text itself or the error code.
type Val:
    kind: String = "empty"
    num: Float = 0.0
    text: String = ""
    flag: Bool = False

# A formula syntax node. kind selects which other fields are meaningful.
type Node:
    kind: String
    name: String = ""
    value: Val = Val()
    valid: Bool = True
    c1: Int = 0
    r1: Int = 0
    c2: Int = 0
    r2: Int = 0
    args: List[Node] = []

type Tok:
    kind: String
    text: String
    at: Int
    stop: Int

type Lexed:
    ok: Bool
    toks: List[Tok]

type Parser:
    toks: List[Tok]
    pos: Int = 0
    bad: Bool = False

# A reference spelled as in the source: `valid` is the grid rule, `whole`
# says the whole text was consumed.
type CellRef:
    valid: Bool
    whole: Bool
    col: Int
    row: Int
    col_abs: Bool
    row_abs: Bool

# A rectangle of cells, normalized so that c1 <= c2 and r1 <= r2.
type Rect:
    ok: Bool
    c1: Int
    r1: Int
    c2: Int
    r2: Int

# One argument item of an aggregate function; ranged marks range members.
type Item:
    v: Val
    ranged: Bool

type Split:
    word: String
    rest: String

# The whole sheet. Cell key = row * 26 + col (col 0 is A, row 1..999).
type Sheet:
    raws: Map[Int, String]
    vals: Map[Int, Val]
    forms: Map[Int, Node]
    precs: Map[Int, List[Int]]
    deps: Map[Int, Set[Int]]
    evals: Int
    index: Map[Int, Int]
    low: Map[Int, Int]
    onstack: Set[Int]
    stack: List[Int]
    counter: Int
    aff: Set[Int]

def num_val(x: Float) -> Val:
    return Val(kind: "num", num: x)

def text_val(s: String) -> Val:
    return Val(kind: "text", text: s)

def bool_val(b: Bool) -> Val:
    return Val(kind: "bool", flag: b)

def err_val(code: String) -> Val:
    return Val(kind: "err", text: code)

def finite(x: Float) -> Val:
    if x.is_finite():
        return num_val(x)

    return err_val("#NUM!")

def bad_node() -> Node:
    return Node(kind: "bad")

def key_of(col: Int, row: Int) -> Int:
    return row * 26 + col

def key_row(k: Int) -> Int:
    return k / 26

def key_col(k: Int) -> Int:
    return k % 26

def letter_of(col: Int) -> String:
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZ".slice(col, col + 1).get()

def name_of(k: Int) -> String:
    return letter_of(key_col(k)) + f"{key_row(k)}"

def names_of(keys: List[Int]) -> String:
    var parts = List[String]()
    for k in keys:
        parts.append(name_of(k))
    return parts.join(" ")

def emit(s: String) -> Unit:
    stdout().write(s + "\n").get()

def imin(a: Int, b: Int) -> Int:
    if a < b:
        return a

    return b

def imax(a: Int, b: Int) -> Int:
    if a > b:
        return a

    return b

# Converts a float to an Int, clamping huge magnitudes (callers check ranges).
def to_int(x: Float) -> Int:
    if x > 1000000000.0:
        return 1000000000
    if x < -1000000000.0:
        return -1000000000

    return x.truncate_to_int().get(0)

def code_of(ch: String) -> Int:
    return ch.scalar_at(0, 0)

def is_digit(ch: String) -> Bool:
    let c = code_of(ch)
    return c >= 48 and c <= 57

def is_alpha(ch: String) -> Bool:
    let c = code_of(ch)
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

def is_word(ch: String) -> Bool:
    return is_alpha(ch) or is_digit(ch) or ch == "_" or ch == "."

def is_blank(ch: String) -> Bool:
    let c = code_of(ch)
    return c == 32 or c == 9

def is_space(ch: String) -> Bool:
    let c = code_of(ch)
    return c == 32 or (c >= 9 and c <= 13)

def span(cs: List[String], a: Int, b: Int) -> String:
    var out = ""
    for i in a..b:
        out += cs[i]
    return out

def cut(s: String) -> Split:
    let cs = s.chars()
    let n = cs.length()
    var i = 0
    while i < n and is_blank(cs[i]):
        i += 1

    let start = i
    while i < n and not is_blank(cs[i]):
        i += 1

    let word = span(cs, start, i)
    while i < n and is_blank(cs[i]):
        i += 1
    return Split(word: word, rest: span(cs, i, n))

def words(s: String) -> List[String]:
    var out = List[String]()
    var r = cut(s)

    while r.word != "":
        out.append(r.word.clone())
        r = cut(r.rest)

    return out

# ---------------------------------------------------------------- numbers

# Parses the number grammar [+-]?(digits[.digits]|.digits)([eE][+-]?digits)?
# (digits. is allowed); overflow to infinity is not a number.
def num_from_text(s: String) -> Val:
    let cs = s.chars()
    let n = cs.length()
    var i = 0
    var sign = ""

    if i < n and (cs[i] == "+" or cs[i] == "-"):
        if cs[i] == "-":
            sign = "-"
        i += 1

    var int_part = ""

    while i < n and is_digit(cs[i]):
        int_part += cs[i]
        i += 1

    var frac = ""

    if i < n and cs[i] == ".":
        i += 1

        while i < n and is_digit(cs[i]):
            frac += cs[i]
            i += 1

    if int_part == "" and frac == "":
        return err_val("#VALUE!")

    var expo = ""

    if i < n and (cs[i] == "e" or cs[i] == "E"):
        i += 1

        var esign = ""

        if i < n and (cs[i] == "+" or cs[i] == "-"):
            esign = cs[i].clone()
            i += 1

        var edig = ""

        while i < n and is_digit(cs[i]):
            edig += cs[i]
            i += 1

        if edig == "":
            return err_val("#VALUE!")

        expo = "e" + esign + edig

    if i != n:
        return err_val("#VALUE!")

    let ip = int_part if int_part != "" else "0"

    let fp = frac if frac != "" else "0"

    let parsed = (sign + ip + "." + fp + expo).parse_float()
    if parsed.is_none():
        return err_val("#VALUE!")

    return num_val(parsed.get(0.0))

# Exact decimal digits of a large whole number: m * 2^e, by repeated doubling.
def big_text(x: Float) -> String:
    var m = x.abs()
    var e = 0

    while m >= 9007199254740992.0:
        m = m / 2.0
        e += 1

    var rest = m.truncate_to_int().get(0)
    var digits = List[Int]()
    if rest == 0:
        digits.append(0)

    while rest > 0:
        digits.append(rest % 10)
        rest = rest / 10

    for step in 0..e:
        var carry = 0

        for i in 0..digits.length():
            let d = digits[i] * 2 + carry
            digits[i] = d % 10
            carry = d / 10

        if carry > 0:
            digits.append(carry)

    var out = ""
    for i in 0..digits.length():
        out = f"{digits[i]}" + out
    if x < 0.0:
        out = "-" + out
    return out

def fmt_num(x: Float) -> String:
    if x.abs() >= 1e21:
        return big_text(x)

    var s = x.to_fixed(10)

    if s.contains("."):
        while s.ends_with("0"):
            s = s.slice(0, s.length() - 1).get()
        if s.ends_with("."):
            s = s.slice(0, s.length() - 1).get()

    if s == "-0":
        return "0"

    return s

def display(v: Val) -> String:
    if v.kind == "num":
        return fmt_num(v.num)
    if v.kind == "text":
        return v.text.clone()
    if v.kind == "bool":
        return "TRUE" if v.flag else "FALSE"
    if v.kind == "err":
        return v.text.clone()

    return ""

# Number coercion: numbers, booleans, empties and number text.
def to_num(v: Val) -> Val:
    if v.kind == "num":
        return v
    if v.kind == "bool":
        return num_val(1.0 if v.flag else 0.0)
    if v.kind == "empty":
        return num_val(0.0)
    if v.kind == "text":
        return num_from_text(v.text.trim().clone())

    return v

def to_bool(v: Val) -> Val:
    if v.kind == "bool":
        return v
    if v.kind == "num":
        return bool_val(v.num != 0.0)
    if v.kind == "empty":
        return bool_val(False)

    if v.kind == "text":
        let u = v.text.upper()
        if u == "TRUE":
            return bool_val(True)
        if u == "FALSE":
            return bool_val(False)

        return err_val("#VALUE!")

    return v

def zero_like(v: Val) -> Val:
    if v.kind == "num":
        return num_val(0.0)
    if v.kind == "text":
        return text_val("")
    if v.kind == "bool":
        return bool_val(False)

    return v

def rank_of(v: Val) -> Int:
    if v.kind == "num":
        return 0
    if v.kind == "text":
        return 1

    return 2

# Comparison rules: empties take the zero value of the other side; numbers
# sort before text, text before booleans.
def compare_vals(a0: Val, b0: Val) -> Int:
    if a0.kind == "empty" and b0.kind == "empty":
        return 0

    var a = a0
    var b = b0
    if a.kind == "empty":
        a = zero_like(b.clone())
    if b.kind == "empty":
        b = zero_like(a.clone())

    let ra = rank_of(a)
    let rb = rank_of(b)
    if ra != rb:
        return -1 if ra < rb else 1

    if a.kind == "num":
        if a.num < b.num:
            return -1
        if a.num > b.num:
            return 1

        return 0

    if a.kind == "text":
        if a.text < b.text:
            return -1
        if a.text > b.text:
            return 1

        return 0

    if a.flag == b.flag:
        return 0

    return 1 if a.flag else - 1

def cmp_op(op: String, c: Int) -> Bool:
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

def is_cmp(op: String) -> Bool:
    return ["=", "<>", "<", "<=", ">", ">="].contains(op)

def arith(op: String, a: Val, b: Val) -> Val:
    let x = to_num(a)
    if x.kind == "err":
        return x

    let y = to_num(b)
    if y.kind == "err":
        return y
    if op == "+":
        return finite(x.num + y.num)
    if op == "-":
        return finite(x.num - y.num)
    if op == "*":
        return finite(x.num * y.num)

    if op == "/":
        if y.num == 0.0:
            return err_val("#DIV/0!")

        return finite(x.num / y.num)

    return finite(pow(x.num, y.num))

def binary(op: String, a: Val, b: Val) -> Val:
    if op == "&" or is_cmp(op):
        if a.kind == "err":
            return a
        if b.kind == "err":
            return b
        if op == "&":
            return text_val(display(a) + display(b))

        return bool_val(cmp_op(op, compare_vals(a, b)))

    return arith(op, a, b)

def unary(op: String, x: Val) -> Val:
    let v = to_num(x)
    if v.kind == "err":
        return v
    if op == "-":
        return finite(-v.num)

    return v

def round_half_away(y: Float) -> Float:
    let a = y.abs()
    let f = floor(a)
    var r = f
    if a - f >= 0.5:
        r = f + 1.0
    if y < 0.0:
        return -r

    return r

def ascii_map(s: String, up: Bool) -> String:
    var out = ""

    for ch in s.chars():
        let c = code_of(ch)

        if up and c >= 97 and c <= 122:
            out += ch.upper()
        elif not up and c >= 65 and c <= 90:
            out += ch.lower()
        else:
            out += ch

    return out

def collapse_spaces(s: String) -> String:
    var out = ""
    var pending = False

    for ch in s.chars():
        if is_space(ch):
            pending = True
        else:
            if pending and out != "":
                out += " "
            pending = False
            out += ch

    return out

# ---------------------------------------------------------------- references

def parse_ref(text: String) -> CellRef:
    let cs = text.chars()
    let n = cs.length()
    var i = 0
    var col_abs = False
    var row_abs = False

    if i < n and cs[i] == "$":
        col_abs = True
        i += 1

    let letters_at = i
    while i < n and is_alpha(cs[i]):
        i += 1

    let letters = span(cs, letters_at, i)

    if i < n and cs[i] == "$":
        row_abs = True
        i += 1

    let digits_at = i
    while i < n and is_digit(cs[i]):
        i += 1

    let digits = span(cs, digits_at, i)
    var valid = letters.length() == 1 and digits.length() >= 1 and digits.length() <= 3
    if valid and code_of(digits) == 48:
        valid = False

    var row = 0
    for ch in digits.chars():
        row = row * 10 + code_of(ch) - 48

    let col = code_of(letters.upper()) - 65
    return CellRef(
        valid: valid, whole: i == n, col: col, row: row, col_abs: col_abs,
        row_abs: row_abs
    )

# A cell argument of a command: letter plus row, no $ markers.
def parse_cell(text: String) -> Rect:
    let r = parse_ref(text)
    if r.valid and r.whole and not r.col_abs and not r.row_abs:
        return Rect(ok: True, c1: r.col, r1: r.row, c2: r.col, r2: r.row)

    return Rect(ok: False, c1: 0, r1: 0, c2: 0, r2: 0)

def parse_range(text: String) -> Rect:
    let parts = text.split(":")
    if parts.length() == 1:
        return parse_cell(text)

    let bad = Rect(ok: False, c1: 0, r1: 0, c2: 0, r2: 0)
    if parts.length() != 2:
        return bad

    let a = parse_cell(parts[0])
    let b = parse_cell(parts[1])
    if not a.ok or not b.ok:
        return bad

    return Rect(
        ok: True, c1: imin(a.c1, b.c1), r1: imin(a.r1, b.r1), c2: imax(a.c1, b.c1),
        r2: imax(a.r1, b.r1)
    )

# Canonical text of a moved reference, or #REF! when it leaves the grid.
def moved_ref(r: CellRef, dc: Int, dr: Int) -> String:
    let col = r.col if r.col_abs else r.col + dc

    let row = r.row if r.row_abs else r.row + dr

    if col < 0 or col > 25 or row < 1 or row > 999:
        return "#REF!"

    let cabs = "$" if r.col_abs else ""

    let rabs = "$" if r.row_abs else ""

    return cabs + letter_of(col) + rabs + f"{row}"

def shift_token(text: String, dc: Int, dr: Int) -> String:
    let parts = text.split(":")
    let a = parse_ref(parts[0])

    if parts.length() == 1:
        if not a.valid:
            return text

        return moved_ref(a, dc, dr)

    let b = parse_ref(parts[1])
    if not a.valid or not b.valid:
        return text

    let x = moved_ref(a, dc, dr)
    let y = moved_ref(b, dc, dr)
    if x == "#REF!" or y == "#REF!":
        return "#REF!"

    return x + ":" + y

# Shifts every reference token of a formula source by (dc, dr); text that
# cannot be tokenized is returned unchanged.
def shift_formula(src: String, dc: Int, dr: Int) -> String:
    let lx = lex(src)
    if not lx.ok:
        return src

    let cs = src.chars()
    var out = ""
    var pos = 0

    for t in lx.toks:
        if t.kind == "ref" or t.kind == "range":
            out += span(cs, pos, t.at)
            out += shift_token(t.text.clone(), dc, dr)
            pos = t.stop

    out += span(cs, pos, cs.length())
    return out

# ---------------------------------------------------------------- lexer

# Length of a reference lexeme starting at start, or -1 if none does.
def ref_end(cs: List[String], start: Int) -> Int:
    let n = cs.length()
    var i = start
    if i < n and cs[i] == "$":
        i += 1

    let letters_at = i
    while i < n and is_alpha(cs[i]):
        i += 1
    if i == letters_at:
        return -1

    if i < n and cs[i] == "$":
        i += 1

    let digits_at = i
    while i < n and is_digit(cs[i]):
        i += 1
    if i == digits_at:
        return -1
    if i < n and (is_word(cs[i]) or cs[i] == "(" or cs[i] == "$"):
        return -1

    return i

def lex(src: String) -> Lexed:
    let cs = src.chars()
    let n = cs.length()
    var toks = List[Tok]()
    var i = 0

    while i < n:
        let ch = cs[i]

        if ch == " " or ch == "\t":
            i += 1
        elif ch == "\"":
            var text = ""
            var j = i + 1

            while j < n:
                if cs[j] == "\"" and j + 1 < n and cs[j + 1] == "\"":
                    text += "\""
                    j += 2
                elif cs[j] == "\"":
                    break
                else:
                    text += cs[j]
                    j += 1

            if j >= n:
                return Lexed(ok: False, toks: toks)

            toks.append(Tok(kind: "str", text: text, at: i, stop: j + 1))
            i = j + 1
        elif is_digit(ch) or (ch == "." and i + 1 < n and is_digit(cs[i + 1])):
            var j = i
            while j < n and is_digit(cs[j]):
                j += 1

            if j < n and cs[j] == ".":
                j += 1
                while j < n and is_digit(cs[j]):
                    j += 1

            if j < n and (cs[j] == "e" or cs[j] == "E"):
                var k = j + 1
                if k < n and (cs[k] == "+" or cs[k] == "-"):
                    k += 1

                if k < n and is_digit(cs[k]):
                    while k < n and is_digit(cs[k]):
                        k += 1
                    j = k

            toks.append(Tok(kind: "num", text: span(cs, i, j), at: i, stop: j))
            i = j
        elif ch == "#":
            if i + 5 <= n and span(cs, i, i + 5).upper() == "#REF!":
                toks.append(Tok(kind: "err", text: "#REF!", at: i, stop: i + 5))
                i += 5
            else:
                return Lexed(ok: False, toks: toks)
        elif ch == "$" or is_alpha(ch) or ch == "_":
            let e = ref_end(cs, i)

            let e2 = ref_end(cs, e + 1) if e >= 0 and e + 1 < n and cs[e] == ":" else - 1

            if e >= 0 and e2 >= 0:
                toks.append(Tok(kind: "range", text: span(cs, i, e2), at: i, stop: e2))
                i = e2
            elif e >= 0:
                toks.append(Tok(kind: "ref", text: span(cs, i, e), at: i, stop: e))
                i = e
            elif is_alpha(ch) or ch == "_":
                var j = i + 1
                while j < n and is_word(cs[j]):
                    j += 1
                toks.append(Tok(kind: "name", text: span(cs, i, j), at: i, stop: j))
                i = j
            else:
                return Lexed(ok: False, toks: toks)
        else:
            let two = span(cs, i, i + 2) if i + 2 <= n else ""

            if two == "<>" or two == "<=" or two == ">=":
                toks.append(Tok(kind: "op", text: two, at: i, stop: i + 2))
                i += 2
            elif "+-*/^&=<>(),".contains(ch):
                toks.append(Tok(kind: "op", text: ch.clone(), at: i, stop: i + 1))
                i += 1
            else:
                return Lexed(ok: False, toks: toks)

    return Lexed(ok: True, toks: toks)

# ---------------------------------------------------------------- parser

impl Parser:
    def peek_op() -> String:
        if self.bad or self.pos >= self.toks.length():
            return ""

        let t = self.toks[self.pos]
        if t.kind == "op":
            return t.text.clone()

        return ""

    var def take_any(ops: List[String]) -> String:
        let op = self.peek_op()

        if op != "" and ops.contains(op):
            self.pos += 1
            return op

        return ""

    var def fail() -> Unit:
        self.bad = True
        self.pos = self.toks.length()

    var def binary(level: Int) -> Node:
        if level == 4:
            return self.unary()

        var ops = ["="]

        if level == 0:
            ops = ["=", "<>", "<", "<=", ">", ">="]
        elif level == 1:
            ops = ["&"]
        elif level == 2:
            ops = ["+", "-"]
        else:
            ops = ["*", "/"]

        var left = self.binary(level + 1)
        var op = self.take_any(ops)

        while op != "":
            let right = self.binary(level + 1)
            left = Node(kind: "bin", name: op, args: [left, right])
            op = self.take_any(ops)

        return left

    var def unary() -> Node:
        let sign = self.take_any(["+", "-"])

        if sign != "":
            let x = self.unary()
            return Node(kind: "un", name: sign, args: [x])

        return self.power()

    var def power() -> Node:
        let base = self.primary()

        if self.take_any(["^"]) != "":
            let rhs = self.power_rhs()
            return Node(kind: "bin", name: "^", args: [base, rhs])

        return base

    var def power_rhs() -> Node:
        let sign = self.take_any(["+", "-"])

        if sign != "":
            let x = self.power_rhs()
            return Node(kind: "un", name: sign, args: [x])

        return self.power()

    var def args() -> List[Node]:
        var out = List[Node]()
        if self.take_any([")"]) != "":
            return out

        out.append(self.binary(0))
        while self.take_any([","]) != "":
            out.append(self.binary(0))
        if self.take_any([")"]) == "":
            self.fail()
        return out

    var def primary() -> Node:
        if self.bad or self.pos >= self.toks.length():
            self.fail()
            return bad_node()

        let t = self.toks[self.pos].clone()
        self.pos += 1

        if t.kind == "num":
            let v = num_from_text(t.text)
            if v.kind == "num":
                return Node(kind: "lit", value: v)

            return Node(kind: "lit", value: err_val("#NUM!"))

        if t.kind == "str":
            return Node(kind: "lit", value: text_val(t.text.clone()))
        if t.kind == "err":
            return Node(kind: "lit", value: err_val("#REF!"))

        if t.kind == "ref":
            let r = parse_ref(t.text)
            return Node(kind: "ref", valid: r.valid, c1: r.col, r1: r.row)

        if t.kind == "range":
            let parts = t.text.split(":")
            let a = parse_ref(parts[0])
            let b = parse_ref(parts[1])
            return Node(
                kind: "rng", valid: a.valid and b.valid, c1: imin(a.col, b.col),
                r1: imin(a.row, b.row), c2: imax(a.col, b.col), r2: imax(a.row, b.row)
            )

        if t.kind == "name":
            let up = t.text.upper()

            if self.peek_op() == "(":
                self.pos += 1

                let callargs = self.args()
                return Node(kind: "call", name: up, args: callargs)

            if up == "TRUE" or up == "FALSE":
                return Node(kind: "lit", value: bool_val(up == "TRUE"))

            return Node(kind: "name", name: t.text.clone())

        if t.kind == "op" and t.text == "(":
            let e = self.binary(0)
            if self.take_any([")"]) == "":
                self.fail()
            return e

        self.fail()
        return bad_node()

def parse_formula(src: String) -> Node:
    let lx = lex(src)
    if not lx.ok:
        return bad_node()

    var p = Parser(toks: lx.toks.clone())
    let e = p.binary(0)
    if p.bad or p.pos != p.toks.length():
        return bad_node()

    return e

# Precedent keys of a formula; ROW and COLUMN arguments create no dependency.
def refs_of(n: Node) -> List[Int]:
    var out = List[Int]()
    if n.kind == "call" and (n.name == "ROW" or n.name == "COLUMN"):
        return out

    if n.kind == "ref" and n.valid:
        out.append(key_of(n.c1, n.r1))
    if n.kind == "rng" and n.valid:
        for r in n.r1..n.r2 + 1:
            for c in n.c1..n.c2 + 1:
                out.append(key_of(c, r))
    for a in n.args:
        for k in refs_of(a):
            out.append(k)
    return out

def unique_keys(keys: List[Int]) -> List[Int]:
    var seen = Set[Int]()
    var out = List[Int]()

    for k in keys:
        if not seen.contains(k):
            seen.add(k)
            out.append(k)

    return out

# Classifies the trimmed VALUE of a non-formula cell.
def classify(raw: String) -> Val:
    if raw.starts_with("'"):
        return text_val(raw.slice(1, raw.length()).get())

    let nv = num_from_text(raw)
    if nv.kind == "num":
        return nv

    let u = raw.upper()
    if u == "TRUE":
        return bool_val(True)
    if u == "FALSE":
        return bool_val(False)

    return text_val(raw)

# ---------------------------------------------------------------- CSV

# Splits CSV text into non-blank records of fields, interpreting the rules
# of the import command.
def csv_records(text: String) -> List[List[String]]:
    let cs = text.chars()
    let n = cs.length()
    var recs = List[List[String]]()
    var fields = List[String]()
    var field = ""
    var quoted = False
    var used = 0
    var i = 0

    while i < n:
        let ch = cs[i]
        i += 1

        if quoted and ch == "\"" and i < n and cs[i] == "\"":
            field += "\""
            i += 1
            used += 2
        elif quoted and ch == "\"":
            quoted = False
            used += 1
        elif quoted:
            field += ch
            used += 1
        elif ch == "\"":
            quoted = True
            used += 1
        elif ch == ",":
            fields.append(field)
            field = ""
            used += 1
        elif ch == "\n":
            if used > 0:
                fields.append(field)
                recs.append(fields)

            fields = List[String]()
            field = ""
            used = 0
        elif ch != "\r":
            field += ch
            used += 1

    if used > 0:
        fields.append(field)
        recs.append(fields)

    return recs

def csv_field(s: String) -> String:
    let needs = (
        s.contains(",")
        or s.contains("\"")
        or s.contains("\n")
        or s.contains("\r")
        or s.starts_with(" ")
        or s.ends_with(" ")
    )
    if needs:
        return "\"" + s.replace("\"", "\"\"") + "\""

    return s

# ---------------------------------------------------------------- functions

def arity(n: Node, lo: Int, hi: Int) -> Bool:
    return n.args.length() >= lo and n.args.length() <= hi

impl Sheet:
    def scalar(n: Node) -> Val:
        if n.kind == "rng":
            return err_val("#VALUE!")

        return self.eval(n)

    # Scalar argument as text: an error stays an error.
    def text_arg(n: Node, i: Int) -> Val:
        let v = self.scalar(n.args[i])
        if v.kind == "err":
            return v

        return text_val(display(v))

    def gather(args: List[Node]) -> List[Item]:
        var out = List[Item]()

        for a in args:
            if a.kind == "rng":
                if not a.valid:
                    out.append(Item(v: err_val("#REF!"), ranged: False))
                else:
                    for r in a.r1..a.r2 + 1:
                        for c in a.c1..a.c2 + 1:
                            out.append(
                                Item(
                                    v: self.vals.get_or(
                                        key_of(
                                            c, r
                                        ),
                                        Val()
                                    ),
                                    ranged: True
                                )
                            )
            else:
                out.append(Item(v: self.eval(a.clone()), ranged: False))

        return out

    def numeric(n: Node) -> Val:
        if n.args.length() == 0:
            return err_val("#VALUE!")

        var nums = List[Float]()

        for it in self.gather(n.args):
            if it.v.kind == "err":
                return it.v.clone()

            if it.ranged:
                if it.v.kind == "num":
                    nums.append(it.v.num)
            else:
                let c = to_num(it.v.clone())
                if c.kind == "err":
                    return c

                nums.append(c.num)

        let name = n.name

        if name == "SUM":
            var total = 0.0
            for x in nums.clone():
                total += x
            return finite(total)

        if name == "AVERAGE":
            if nums.length() == 0:
                return err_val("#DIV/0!")

            var total = 0.0
            for x in nums.clone():
                total += x
            return finite(total / nums.length().to_float())

        if name == "PRODUCT":
            if nums.length() == 0:
                return num_val(0.0)

            var prod = 1.0
            for x in nums.clone():
                prod *= x
            return finite(prod)

        if name == "MIN" or name == "MAX":
            if nums.length() == 0:
                return num_val(0.0)

            var best = nums[0] + 0.0

            for x in nums.clone():
                if name == "MIN" and x < best:
                    best = x
                if name == "MAX" and x > best:
                    best = x

            return num_val(best)

        if nums.length() == 0:
            return err_val("#NUM!")

        let s = nums.sorted()
        let m = s.length()
        if m % 2 == 1:
            return num_val(s[m / 2])

        return finite((s[m / 2 - 1] + s[m / 2]) / 2.0)

    def countif(a: Node, crit: Val) -> Val:
        if a.kind != "rng":
            return err_val("#VALUE!")
        if not a.valid:
            return err_val("#REF!")

        var op = "="
        var operand = crit.clone()

        if crit.kind == "text":
            var rest = crit.text.clone()
            var found = False

            for o in [">=", "<=", "<>", ">", "<", "="]:
                if not found and rest.starts_with(o):
                    found = True
                    op = o.clone()
                    rest = rest.slice(o.length(), rest.length()).get()

            let nv = num_from_text(rest)

            operand = nv if nv.kind == "num" else text_val(rest)

        var count = 0

        for r in a.r1..a.r2 + 1:
            for c in a.c1..a.c2 + 1:
                let v = self.vals.get_or(key_of(c, r), Val())

                if v.kind == operand.kind:
                    if cmp_op(op, compare_vals(v.clone(), operand.clone())):
                        count += 1
                elif op == "<>" and v.kind != "empty":
                    count += 1

        return num_val(count.to_float())

    def call(n: Node) -> Val:
        let name = n.name
        let k = n.args.length()
        if (
            name == "SUM"
            or name == "AVERAGE"
            or name == "MIN"
            or name == "MAX"
            or name == "PRODUCT"
            or name == "MEDIAN"
        ):
            return self.numeric(n)

        if name == "COUNT" or name == "COUNTA":
            if k == 0:
                return err_val("#VALUE!")

            var count = 0

            for it in self.gather(n.args):
                if name == "COUNT" and it.v.kind == "num":
                    count += 1
                if name == "COUNTA" and it.v.kind != "empty":
                    count += 1

            return num_val(count.to_float())

        if name == "AND" or name == "OR":
            if k == 0:
                return err_val("#VALUE!")

            var took = False
            var acc = name == "AND"

            for it in self.gather(n.args):
                if it.v.kind == "err":
                    return it.v.clone()
                if it.ranged and (it.v.kind == "text" or it.v.kind == "empty"):
                    continue

                let b = to_bool(it.v.clone())
                if b.kind == "err":
                    return b

                took = True

                if name == "AND":
                    acc = acc and b.flag
                else:
                    acc = acc or b.flag

            if not took:
                return err_val("#VALUE!")

            return bool_val(acc)

        if name == "CONCAT":
            if k == 0:
                return err_val("#VALUE!")

            var out = ""

            for it in self.gather(n.args):
                if it.v.kind == "err":
                    return it.v.clone()

                out += display(it.v)

            return text_val(out)

        if name == "IF":
            if not arity(n, 2, 3):
                return err_val("#VALUE!")

            let c = self.scalar(n.args[0])
            if c.kind == "err":
                return c

            let b = to_bool(c)
            if b.kind == "err":
                return b
            if b.flag:
                return self.scalar(n.args[1])
            if k == 3:
                return self.scalar(n.args[2])

            return bool_val(False)

        if name == "IFERROR":
            if not arity(n, 2, 2):
                return err_val("#VALUE!")

            let a = self.scalar(n.args[0])
            if a.kind == "err":
                return self.scalar(n.args[1])

            return a

        if name == "CHOOSE":
            if k < 2:
                return err_val("#VALUE!")

            let iv = to_num(self.scalar(n.args[0]))
            if iv.kind == "err":
                return iv

            let idx = floor(iv.num)
            if idx < 1.0 or idx > (k - 1).to_float():
                return err_val("#VALUE!")

            return self.scalar(n.args[to_int(idx)])

        if name == "COUNTIF":
            if not arity(n, 2, 2):
                return err_val("#VALUE!")
            if n.args[0].kind != "rng":
                return err_val("#VALUE!")

            let crit = self.scalar(n.args[1])
            if crit.kind == "err":
                return crit

            return self.countif(n.args[0], crit)

        if name == "INDEX":
            if not arity(n, 2, 3):
                return err_val("#VALUE!")

            let a = n.args[0]
            if a.kind != "rng":
                return err_val("#VALUE!")
            if not a.valid:
                return err_val("#REF!")

            let rows = a.r2 - a.r1 + 1
            let cols = a.c2 - a.c1 + 1
            let x = to_num(self.scalar(n.args[1]))
            if x.kind == "err":
                return x

            var rf = 1.0
            var cf = 1.0

            if k == 3:
                let y = to_num(self.scalar(n.args[2]))
                if y.kind == "err":
                    return y

                rf = floor(x.num)
                cf = floor(y.num)
            elif rows == 1:
                cf = floor(x.num)
            else:
                rf = floor(x.num)

            if rf < 1.0 or rf > rows.to_float() or cf < 1.0 or cf > cols.to_float():
                return err_val("#REF!")

            return self.vals.get_or(
                key_of(a.c1 + to_int(cf) - 1, a.r1 + to_int(rf) - 1), Val()
            )

        if name == "ROW" or name == "COLUMN":
            if not arity(n, 1, 1):
                return err_val("#VALUE!")

            let a = n.args[0]
            if a.kind != "ref" and a.kind != "rng":
                return err_val("#VALUE!")
            if not a.valid:
                return err_val("#REF!")
            if name == "ROW":
                return num_val(a.r1.to_float())

            return num_val((a.c1 + 1).to_float())

        return self.scalar_call(n)

    def scalar_call(n: Node) -> Val:
        let name = n.name
        let k = n.args.length()

        if name == "NOT":
            if not arity(n, 1, 1):
                return err_val("#VALUE!")

            let b = to_bool(self.scalar(n.args[0]))
            if b.kind == "err":
                return b

            return bool_val(not b.flag)

        if name == "ABS" or name == "INT" or name == "SQRT":
            if not arity(n, 1, 1):
                return err_val("#VALUE!")

            let x = to_num(self.scalar(n.args[0]))
            if x.kind == "err":
                return x
            if name == "ABS":
                return finite(x.num.abs())
            if name == "INT":
                return finite(floor(x.num))
            if x.num < 0.0:
                return err_val("#NUM!")

            return finite(sqrt(x.num))

        if name == "POW":
            if not arity(n, 2, 2):
                return err_val("#VALUE!")

            return arith("^", self.scalar(n.args[0]), self.scalar(n.args[1]))

        if name == "MOD":
            if not arity(n, 2, 2):
                return err_val("#VALUE!")

            let a = to_num(self.scalar(n.args[0]))
            if a.kind == "err":
                return a

            let b = to_num(self.scalar(n.args[1]))
            if b.kind == "err":
                return b
            if b.num == 0.0:
                return err_val("#DIV/0!")

            return finite(a.num - b.num * floor(a.num / b.num))

        if name == "ROUND":
            if not arity(n, 1, 2):
                return err_val("#VALUE!")

            let x = to_num(self.scalar(n.args[0]))
            if x.kind == "err":
                return x

            var d = 0.0

            if k == 2:
                let dv = to_num(self.scalar(n.args[1]))
                if dv.kind == "err":
                    return dv

                d = -floor(-dv.num) if dv.num < 0.0 else floor(dv.num)

            if d.abs() > 15.0:
                return err_val("#NUM!")

            let p = pow(10.0, d)
            return finite(round_half_away(x.num * p) / p)

        if name == "LEN":
            if not arity(n, 1, 1):
                return err_val("#VALUE!")

            let s = self.text_arg(n, 0)
            if s.kind == "err":
                return s

            return num_val(s.text.length().to_float())

        if name == "UPPER" or name == "LOWER":
            if not arity(n, 1, 1):
                return err_val("#VALUE!")

            let s = self.text_arg(n, 0)
            if s.kind == "err":
                return s

            return text_val(ascii_map(s.text, name == "UPPER"))

        if name == "TRIM":
            if not arity(n, 1, 1):
                return err_val("#VALUE!")

            let s = self.text_arg(n, 0)
            if s.kind == "err":
                return s

            return text_val(collapse_spaces(s.text))

        if name == "LEFT" or name == "RIGHT":
            if not arity(n, 1, 2):
                return err_val("#VALUE!")

            let s = self.text_arg(n, 0)
            if s.kind == "err":
                return s

            var cnt = 1.0

            if k == 2:
                let c = to_num(self.scalar(n.args[1]))
                if c.kind == "err":
                    return c

                cnt = floor(c.num)

            if cnt < 0.0:
                return err_val("#VALUE!")

            let cs = s.text.chars()
            let len = cs.length()
            let m = imin(to_int(cnt), len)
            if name == "LEFT":
                return text_val(span(cs, 0, m))

            return text_val(span(cs, len - m, len))

        if name == "MID":
            if not arity(n, 3, 3):
                return err_val("#VALUE!")

            let s = self.text_arg(n, 0)
            if s.kind == "err":
                return s

            let st = to_num(self.scalar(n.args[1]))
            if st.kind == "err":
                return st

            let ln = to_num(self.scalar(n.args[2]))
            if ln.kind == "err":
                return ln

            let sf = floor(st.num)
            let lf = floor(ln.num)
            if sf < 1.0 or lf < 0.0:
                return err_val("#VALUE!")

            let cs = s.text.chars()
            let len = cs.length()
            let a = to_int(sf) - 1
            if a >= len:
                return text_val("")

            return text_val(span(cs, a, imin(len, a + to_int(lf))))

        if name == "SUBSTITUTE":
            if not arity(n, 3, 3):
                return err_val("#VALUE!")

            let s = self.text_arg(n, 0)
            if s.kind == "err":
                return s

            let old = self.text_arg(n, 1)
            if old.kind == "err":
                return old

            let nw = self.text_arg(n, 2)
            if nw.kind == "err":
                return nw
            if old.text == "":
                return s

            return text_val(s.text.replace(old.text, nw.text))

        if name == "VALUE":
            if not arity(n, 1, 1):
                return err_val("#VALUE!")

            return to_num(self.scalar(n.args[0]))

        if (
            name == "ISERROR"
            or name == "ISBLANK"
            or name == "ISNUMBER"
            or name == "ISTEXT"
        ):
            if not arity(n, 1, 1):
                return err_val("#VALUE!")

            let v = self.scalar(n.args[0])
            if name == "ISERROR":
                return bool_val(v.kind == "err")
            if name == "ISBLANK":
                return bool_val(v.kind == "empty")
            if name == "ISNUMBER":
                return bool_val(v.kind == "num")

            return bool_val(v.kind == "text")

        return err_val("#NAME?")

    def eval(n: Node) -> Val:
        if n.kind == "lit":
            return n.value.clone()

        if n.kind == "ref":
            if not n.valid:
                return err_val("#REF!")

            return self.vals.get_or(key_of(n.c1, n.r1), Val())

        if n.kind == "rng":
            return err_val("#VALUE!")
        if n.kind == "name":
            return err_val("#NAME?")
        if n.kind == "bad":
            return err_val("#PARSE!")
        if n.kind == "un":
            return unary(n.name.clone(), self.eval(n.args[0]))

        if n.kind == "bin":
            let a = self.eval(n.args[0])
            let b = self.eval(n.args[1])
            return binary(n.name.clone(), a, b)

        return self.call(n)

    def eval_formula(k: Int) -> Val:
        let v = self.eval(self.forms.get_or(k, bad_node()))
        if v.kind == "empty":
            return num_val(0.0)

        return v

    # ------------------------------------------------------ dependencies

    var def drop(k: Int) -> Unit:
        if self.precs.contains(k):
            for p in self.precs.get_or(k, List[Int]()):
                if var s = self.deps.get(p):
                    s.remove(k)
            self.precs.remove(k)

        self.forms.remove(k)
        self.raws.remove(k)
        self.vals.remove(k)

    # Stores the trimmed VALUE raw in cell k (an empty raw clears it).
    var def put(k: Int, raw: String) -> Unit:
        self.drop(k)
        if raw == "":
            return

        self.raws.add(k, raw.clone())

        if raw.starts_with("="):
            let node = parse_formula(raw.slice(1, raw.length()).get())
            let ps = unique_keys(refs_of(node))
            self.forms.add(k, node)
            self.precs.add(k, ps.clone())

            for p in ps:
                self.deps.add_default(p, Set[Int]())
                if var s = self.deps.get(p):
                    s.add(k)

            self.vals.add(k, Val())
        else:
            self.vals.add(k, classify(raw))

    # Recomputes the affected formulas after the cells in changed were assigned.
    var def recalc(changed: List[Int]) -> Int:
        var seen = Set[Int]()
        var queue = List[Int]()

        for k in changed:
            if not seen.contains(k):
                seen.add(k)
                queue.append(k)

        var i = 0

        while i < queue.length():
            let k = queue[i]
            i += 1

            if var ds = self.deps.get(k):
                for d in ds.values():
                    if not seen.contains(d):
                        seen.add(d)
                        queue.append(d)

        self.aff = Set[Int]()
        for k in queue:
            if self.forms.contains(k):
                self.aff.add(k)
        self.index = Map[Int, Int]()
        self.low = Map[Int, Int]()
        self.onstack = Set[Int]()
        self.stack = List[Int]()
        self.counter = 0
        for k in self.aff.values():
            if not self.index.contains(k):
                self.visit(k)

        let n = self.aff.length()
        self.evals += n
        return n

    # Tarjan's strongly connected components over affected formulas; each
    # component is finished once all of its precedents are.
    var def visit(v: Int) -> Unit:
        self.index.add(v, self.counter)
        self.low.add(v, self.counter)
        self.counter += 1
        self.stack.append(v)
        self.onstack.add(v)

        for w in self.precs.get_or(v, List[Int]()):
            if not self.aff.contains(w):
                continue

            if not self.index.contains(w):
                self.visit(w)
                self.low.add(v, imin(self.low.get_or(v, 0), self.low.get_or(w, 0)))
            elif self.onstack.contains(w):
                self.low.add(v, imin(self.low.get_or(v, 0), self.index.get_or(w, 0)))

        if self.low.get_or(v, 0) == self.index.get_or(v, 0):
            var comp = List[Int]()
            var fin = False

            while not fin:
                let w = self.stack.pop().get(0)
                self.onstack.remove(w)
                comp.append(w)
                if w == v:
                    fin = True

            self.finish(v, comp)

    var def finish(v: Int, comp: List[Int]) -> Unit:
        var cyclic = comp.length() > 1
        if not cyclic:
            cyclic = self.precs.get_or(v, List[Int]()).contains(v)

        if cyclic:
            for w in comp:
                self.vals.add(w, err_val("#CYCLE!"))
        else:
            self.vals.add(v, self.eval_formula(v))

    # Keys of every formula that transitively depends on k.
    def closure(k: Int) -> List[Int]:
        var seen = Set[Int]()
        var queue = List[Int]()
        queue.append(k)

        var out = List[Int]()
        var i = 0

        while i < queue.length():
            let x = queue[i]
            i += 1

            if let ds = self.deps.get(x):
                for d in ds.values():
                    if not seen.contains(d):
                        seen.add(d)
                        queue.append(d)
                        out.append(d)

        return out

    def default_rect() -> Rect:
        var maxc = 0
        var maxr = 1

        for k in self.raws.keys():
            maxc = imax(maxc, key_col(k))
            maxr = imax(maxr, key_row(k))

        return Rect(ok: True, c1: 0, r1: 1, c2: maxc, r2: maxr)

    # ------------------------------------------------------ commands

    var def cmd_set(rest: String) -> Unit:
        let c = cut(rest)

        if c.word == "":
            emit("error: usage: set CELL VALUE")
            return

        let r = parse_cell(c.word)

        if not r.ok:
            emit(f"error: bad cell reference '{c.word}'")
            return

        let k = key_of(r.c1, r.r1)
        self.put(k, c.rest.trim().clone())

        let n = self.recalc([k])
        emit(f"recalc {n}")

    var def cmd_clear(rest: String) -> Unit:
        let args = words(rest)

        if args.length() != 1:
            emit("error: usage: clear CELL")
            return

        let r = parse_cell(args[0])

        if not r.ok:
            emit(f"error: bad cell reference '{args[0]}'")
            return

        let k = key_of(r.c1, r.r1)
        self.put(k, "")

        let n = self.recalc([k])
        emit(f"recalc {n}")

    var def cmd_copy(rest: String) -> Unit:
        let args = words(rest)

        if args.length() != 2:
            emit("error: usage: copy SRC DST")
            return

        let s = parse_cell(args[0])

        if not s.ok:
            emit(f"error: bad cell reference '{args[0]}'")
            return

        let d = parse_range(args[1])

        if not d.ok:
            emit(f"error: bad range '{args[1]}'")
            return

        let raw = self.raws.get_or(key_of(s.c1, s.r1), "")
        var changed = List[Int]()

        for r in d.r1..d.r2 + 1:
            for c in d.c1..d.c2 + 1:
                var nr = raw.clone()

                if raw.starts_with("="):
                    let src = raw.slice(1, raw.length()).get()
                    nr = "=" + shift_formula(src, c - s.c1, r - s.r1)

                let k = key_of(c, r)
                self.put(k, nr)
                changed.append(k)

        let n = self.recalc(changed)
        emit(f"recalc {n}")

    var def cmd_import(rest: String, block: List[String]) -> Unit:
        let args = words(rest)

        if args.length() != 1:
            emit("error: usage: import CELL")
            return

        let r = parse_cell(args[0])

        if not r.ok:
            emit(f"error: bad cell reference '{args[0]}'")
            return

        let recs = csv_records(block.join("\n"))
        var cols = 0
        for rec in recs:
            cols = imax(cols, rec.length())

        let nrows = recs.length()

        if nrows > 0 and (r.r1 + nrows - 1 > 999 or r.c1 + cols - 1 > 25):
            emit("error: import out of range")
            return

        var changed = List[Int]()

        for ri in 0..nrows:
            let rec = recs[ri]

            for fi in 0..rec.length():
                let k = key_of(r.c1 + fi, r.r1 + ri)
                self.put(k, rec[fi].trim().clone())
                changed.append(k)

        let n = self.recalc(changed)
        emit(f"imported {nrows} rows, {cols} columns; recalc {n}")

    def cmd_print(rest: String) -> Unit:
        let args = words(rest)

        if args.length() > 1 or (args.length() == 1 and args[0] == "formulas"):
            emit("error: usage: print [RANGE]")
            return

        var rect = Rect(ok: True, c1: 0, r1: 1, c2: 0, r2: 1)

        if args.length() == 0:
            if self.raws.length() == 0:
                emit("(empty sheet)")
                return

            rect = self.default_rect()
        else:
            rect = parse_range(args[0])

            if not rect.ok:
                emit(f"error: bad range '{args[0]}'")
                return

        for r in rect.r1..rect.r2 + 1:
            var parts = List[String]()
            for c in rect.c1..rect.c2 + 1:
                parts.append(display(self.vals.get_or(key_of(c, r), Val())))
            emit(parts.join(" | "))

    def cmd_export(rest: String) -> Unit:
        let args = words(rest)
        var formulas = False
        var seen_mode = False
        var range_arg = ""
        var seen_range = False

        for w in args:
            if w == "formulas" or w == "values":
                if seen_mode:
                    emit("error: usage: export [formulas] [RANGE]")
                    return

                seen_mode = True
                formulas = w == "formulas"
            else:
                if seen_range:
                    emit("error: usage: export [formulas] [RANGE]")
                    return

                seen_range = True
                range_arg = w

        var rect = Rect(ok: True, c1: 0, r1: 1, c2: 0, r2: 1)

        if seen_range:
            rect = parse_range(range_arg)

            if not rect.ok:
                emit(f"error: bad range '{range_arg}'")
                return
        elif self.raws.length() == 0:
            emit("(empty sheet)")
            return
        else:
            rect = self.default_rect()

        for r in rect.r1..rect.r2 + 1:
            var fields = List[String]()

            for c in rect.c1..rect.c2 + 1:
                let k = key_of(c, r)
                var text = ""

                if formulas:
                    text = self.raws.get_or(k, "")
                else:
                    text = display(self.vals.get_or(k, Val()))

                fields.append(csv_field(text))

            emit(fields.join(","))

    def cmd_show(rest: String) -> Unit:
        let args = words(rest)

        if args.length() != 1:
            emit("error: usage: show CELL")
            return

        let r = parse_cell(args[0])

        if not r.ok:
            emit(f"error: bad cell reference '{args[0]}'")
            return

        let k = key_of(r.c1, r.r1)

        if not self.raws.contains(k):
            emit(f"{name_of(k)}: (empty)")
        elif self.forms.contains(k):
            emit(
                f"{name_of(k)}: {self.raws.get_or(k, "")} => {display(self.vals.get_or(k, Val()))}"
            )
        else:
            emit(f"{name_of(k)}: {self.raws.get_or(k, "")}")

    def cmd_get(rest: String) -> Unit:
        let args = words(rest)

        if args.length() != 1:
            emit("error: usage: get CELL")
            return

        let r = parse_cell(args[0])

        if not r.ok:
            emit(f"error: bad cell reference '{args[0]}'")
            return

        let k = key_of(r.c1, r.r1)

        if not self.raws.contains(k):
            emit("(empty)")
        else:
            emit(display(self.vals.get_or(k, Val())))

    def cmd_deps(rest: String, which: String) -> Unit:
        let args = words(rest)

        if args.length() != 1:
            emit(f"error: usage: {which} CELL")
            return

        let r = parse_cell(args[0])

        if not r.ok:
            emit(f"error: bad cell reference '{args[0]}'")
            return

        let k = key_of(r.c1, r.r1)
        var keys = List[Int]()

        if which == "precedents":
            keys = unique_keys(self.precs.get_or(k, List[Int]())).sorted()
        else:
            keys = self.closure(k).sorted()

        if keys.length() == 0:
            emit("(none)")
        else:
            emit(names_of(keys))

    def cmd_stats() -> Unit:
        emit(
            f"cells {self.raws.length()} formulas {self.forms.length()} evals {self.evals}"
        )

    var def command(cmd: String, rest: String) -> Unit:
        if cmd == "set":
            self.cmd_set(rest)
        elif cmd == "clear":
            self.cmd_clear(rest)
        elif cmd == "get":
            self.cmd_get(rest)
        elif cmd == "show":
            self.cmd_show(rest)
        elif cmd == "copy":
            self.cmd_copy(rest)
        elif cmd == "print":
            self.cmd_print(rest)
        elif cmd == "export":
            self.cmd_export(rest)
        elif cmd == "precedents" or cmd == "dependents":
            self.cmd_deps(rest, cmd)
        elif cmd == "stats":
            self.cmd_stats()
        else:
            emit(f"error: unknown command '{cmd}'")

def new_sheet() -> Sheet:
    return Sheet(
        raws: Map[Int, String](), vals: Map[Int, Val](), forms: Map[Int, Node](),
        precs: Map[Int, List[Int]](), deps: Map[Int, Set[Int]](), evals: 0,
        index: Map[Int, Int](), low: Map[Int, Int](), onstack: Set[Int](),
        stack: List[Int](), counter: 0, aff: Set[Int]()
    )

export def main() -> Int:
    let lines = read_lines(stdin()).get()
    var sh = new_sheet()
    var i = 0

    while i < lines.length():
        let line = lines[i].trim_end()
        i += 1

        let body = line.trim_start()
        if body == "" or body.starts_with("#"):
            continue

        emit("> " + line)

        let head = cut(body)

        if head.word == "import":
            var block = List[String]()

            while i < lines.length() and lines[i] != ".":
                block.append(lines[i].clone())
                i += 1

            i += 1
            sh.cmd_import(head.rest, block)
        else:
            sh.command(head.word, head.rest)

    return 0
