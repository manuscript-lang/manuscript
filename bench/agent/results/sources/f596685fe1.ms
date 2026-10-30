import stdout, stdin from "@std/io.ms"
import read_lines from "@std/streams.ms"
import parse_float, floor, pow, sqrt from "@std/math.ms"

# Cell ids are row * 100 + column, so numeric order is row-major (row, then column).
let LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
let LOWERS = "abcdefghijklmnopqrstuvwxyz"

type Value:
    case Blank
    case Num(n: Float)
    case Txt(s: String)
    case Flag(b: Bool)
    case Fail(code: String)

type Node:
    case Lit(v: Value)
    case Ref(valid: Bool, col: Int, row: Int)
    # Corners are kept as written; ranges act on their normalized rectangle.
    case Span(valid: Bool, c1: Int, r1: Int, c2: Int, r2: Int)
    case Neg(negate: Bool, x: Node)
    case Bin(op: String, l: Node, r: Node)
    case Call(name: String, args: List[Node])

type Tok:
    case TSpace(text: String)
    case TWord(text: String)
    case TNumber(text: String)
    case TString(text: String, value: String)
    case TRef(text: String)
    case TSpan(text: String)
    case TErrLit(text: String)
    case TSym(text: String)
    case TBad(text: String)

type Parser:
    toks: List[Tok]
    pos: Int
    bad: Bool

type Corner:
    valid: Bool
    col: Int
    row: Int
    abs_col: Bool
    abs_row: Bool

type Cell:
    raw: String
    formula: Bool
    tree: Node
    precs: Set[Int]

type Item:
    v: Value
    ranged: Bool

type Nums:
    fail: Value
    xs: List[Float]

type Crit:
    op: String
    operand: Value

type Area:
    valid: Bool
    top: Int
    left: Int
    bottom: Int
    right: Int

type Group:
    members: List[Int]
    cyclic: Bool

type Tarjan:
    index: Map[Int, Int]
    low: Map[Int, Int]
    onstack: Set[Int]
    stack: List[Int]
    selfloop: Set[Int]
    counter: Int
    groups: List[Group]

type Sheet:
    cells: Map[Int, Cell]
    vals: Map[Int, Value]
    deps: Map[Int, Set[Int]]
    evals: Int

# ---------- small helpers ----------

fn cid(row: Int, col: Int) Int:
    return row * 100 + col

fn row_of(id: Int) Int:
    return id / 100

fn col_of(id: Int) Int:
    return id % 100

fn lo(a: Int, b: Int) Int:
    if a < b:
        return a

    return b

fn hi(a: Int, b: Int) Int:
    if a > b:
        return a

    return b

fn is_digit(c: String) Bool:
    return c >= "0" and c <= "9"

fn is_alpha(c: String) Bool:
    return (c >= "A" and c <= "Z") or (c >= "a" and c <= "z")

fn is_space(c: String) Bool:
    return c == " " or c == "\t"

fn is_ws(c: String) Bool:
    return c == " " or c == "\t" or c == "\n" or c == "\r"

fn join_range(cs: List[String], a: Int, b: Int) String:
    var s = ""
    for k in a..b:
        s = s + cs[k]
    return s

fn letter_of(col: Int) String:
    return LETTERS.slice_scalars(col, col + 1).get()

fn cell_name(id: Int) String:
    return letter_of(col_of(id)) + row_of(id).to_string()

fn canon_ref(ac: Bool, col: Int, ar: Bool, row: Int) String:
    var s = ""
    if ac:
        s = "$"
    s = s + letter_of(col)
    if ar:
        s = s + "$"
    return s + row.to_string()

fn say(s: String) Unit:
    stdout().write(s + "\n").get()

fn list_of(id: Int) List[Int]:
    var out = List[Int]()
    out.append(id)
    return out

fn bad_area() Area:
    return Area(false, 0, 0, 0, 0)

# Splits on spaces and tabs, the command-word separators.
fn split_words(s: String) List[String]:
    var out = List[String]()
    var cur = ""
    var has = false

    for c in s.chars():
        if is_space(c):
            if has:
                out.append(cur)
                cur = ""
                has = false
        else:
            cur = cur + c
            has = true

    if has:
        out.append(cur)
    return out

# The text after the first `count` whitespace-separated words, trimmed.
fn skip_words(s: String, count: Int) String:
    let cs = s.chars()
    let n = cs.length()
    var i = 0
    var k = 0

    while k < count:
        while i < n and is_space(cs[i]):
            i += 1
        while i < n and not is_space(cs[i]):
            i += 1
        k += 1

    return join_range(cs, i, n).trim()

# ---------- numbers and text ----------

# Digits of a positive integral Float >= 2^53, computed exactly by halving and doubling decimal digits.
fn exact_integer(a: Float) String:
    var m = a
    var e = 0

    while m >= 9007199254740992.0:
        m = m / 2.0
        e += 1

    var digits = List[Int]()
    var v = m.truncate_to_int().get(0)

    while v > 0:
        digits.append(v % 10)
        v = v / 10

    for _s in 0..e:
        var carry = 0

        for k in 0..digits.length():
            let d = digits[k] * 2 + carry
            digits[k] = d % 10
            carry = d / 10

        if carry > 0:
            digits.append(carry)

    var s = ""
    var k = digits.length() - 1

    while k >= 0:
        s = s + digits[k].to_string()
        k -= 1

    return s

fn format_num(x: Float) String:
    var s = ""

    if x.abs() >= 1e21:
        s = exact_integer(x.abs())
        if x < 0.0:
            s = "-" + s
    else:
        s = x.to_fixed(10)

    if s.contains("."):
        while s.ends_with("0"):
            s = s.slice_scalars(0, s.scalar_length() - 1).get()
        if s.ends_with("."):
            s = s.slice_scalars(0, s.scalar_length() - 1).get()

    if s == "-0":
        return "0"

    return s

# Number grammar: [+-]?(digits[.digits]|.digits)([eE][+-]?digits)? ; finite results only.
fn number_text(s: String) Optional[Float]:
    let cs = s.chars()
    let n = cs.length()
    var i = 0
    var neg = false

    if i < n and (cs[i] == "+" or cs[i] == "-"):
        neg = cs[i] == "-"
        i += 1

    var ip = ""

    while i < n and is_digit(cs[i]):
        ip = ip + cs[i]
        i += 1

    var fp = ""

    if i < n and cs[i] == ".":
        i += 1

        while i < n and is_digit(cs[i]):
            fp = fp + cs[i]
            i += 1

    if ip == "" and fp == "":
        return none

    var ex = ""

    if i < n and (cs[i] == "e" or cs[i] == "E"):
        i += 1

        var es = ""

        if i < n and (cs[i] == "+" or cs[i] == "-"):
            es = cs[i].clone()
            i += 1

        var ed = ""

        while i < n and is_digit(cs[i]):
            ed = ed + cs[i]
            i += 1

        if ed == "":
            return none

        ex = "e" + es + ed

    if i != n:
        return none

    var mant_i = ip
    if mant_i == "":
        mant_i = "0"

    var mant_f = fp
    if mant_f == "":
        mant_f = "0"

    if let p = parse_float(mant_i + "." + mant_f + ex):
        if p.is_finite():
            if neg:
                return some(-p)

            return some(p)

    return none

# The VALUE of a set/import field, after trimming, when it is not text.
fn constant_value(raw: String) Value:
    if raw.starts_with("'"):
        return Value.Txt(raw.slice_scalars(1, raw.scalar_length()).get())
    if let x = number_text(raw):
        return Value.Num(x)

    let up = raw.upper()
    if up == "TRUE":
        return Value.Flag(true)
    if up == "FALSE":
        return Value.Flag(false)

    return Value.Txt(raw.clone())

fn map_ascii(s: String, upper: Bool) String:
    let up = LETTERS.chars()
    let low = LOWERS.chars()
    var out = ""

    for c in s.chars():
        var r = c.clone()

        for k in 0..26:
            if upper and c == low[k]:
                r = up[k].clone()
            if not upper and c == up[k]:
                r = low[k].clone()

        out = out + r

    return out

fn trim_collapse(s: String) String:
    var out = ""
    var pending = false

    for c in s.chars():
        if is_ws(c):
            if out != "":
                pending = true
        else:
            if pending:
                out = out + " "
                pending = false

            out = out + c

    return out

# ---------- values ----------

fn is_err(v: Value) Bool:
    match v:
        Fail(_):
            return true
        _:
            return false

fn is_blank(v: Value) Bool:
    match v:
        Blank:
            return true
        _:
            return false

fn is_number(v: Value) Bool:
    match v:
        Num(_):
            return true
        _:
            return false

fn is_text(v: Value) Bool:
    match v:
        Txt(_):
            return true
        _:
            return false

fn flag_part(v: Value) Bool:
    match v:
        Flag(b):
            return b
        _:
            return false

fn num_part(v: Value) Float:
    match v:
        Num(n):
            return n
        _:
            return 0.0

fn text_part(v: Value) String:
    match v:
        Txt(s):
            return s.clone()
        _:
            return ""

fn finite(x: Float) Value:
    if x.is_finite():
        return Value.Num(x)

    return Value.Fail("#NUM!")

# Number coercion: Num or the error that decides the result.
fn to_num(v: Value) Value:
    match v:
        Blank:
            return Value.Num(0.0)
        Num(n):
            return Value.Num(n)
        Flag(b):
            if b:
                return Value.Num(1.0)

            return Value.Num(0.0)
        Txt(s):
            if let x = number_text(s.trim()):
                return Value.Num(x)

            return Value.Fail("#VALUE!")
        Fail(code):
            return Value.Fail(code.clone())

# Boolean coercion: Flag or an error.
fn truth(v: Value) Value:
    match v:
        Blank:
            return Value.Flag(false)
        Num(n):
            return Value.Flag(n != 0.0)
        Flag(b):
            return Value.Flag(b)
        Txt(s):
            let up = s.upper()
            if up == "TRUE":
                return Value.Flag(true)
            if up == "FALSE":
                return Value.Flag(false)

            return Value.Fail("#VALUE!")
        Fail(code):
            return Value.Fail(code.clone())

fn display(v: Value) String:
    match v:
        Blank:
            return ""
        Num(n):
            return format_num(n)
        Txt(s):
            return s.clone()
        Flag(b):
            if b:
                return "TRUE"

            return "FALSE"
        Fail(code):
            return code.clone()

fn zero_like(v: Value) Value:
    match v:
        Num(_):
            return Value.Num(0.0)
        Txt(_):
            return Value.Txt("")
        Flag(_):
            return Value.Flag(false)
        _:
            return Value.Blank

# Type order for comparison: number < text < boolean.
fn rank(v: Value) Int:
    match v:
        Num(_):
            return 0
        Txt(_):
            return 1
        _:
            return 2

# Type identity used by COUNTIF's comparability test.
fn kind_of(v: Value) Int:
    match v:
        Blank:
            return 0
        Num(_):
            return 1
        Txt(_):
            return 2
        Flag(_):
            return 3
        _:
            return 4

fn float_cmp(p: Float, q: Float) Int:
    if p < q:
        return -1
    if p > q:
        return 1

    return 0

fn str_cmp(a: String, b: String) Int:
    if a < b:
        return -1
    if a == b:
        return 0

    return 1

fn flag_num(b: Bool) Float:
    if b:
        return 1.0

    return 0.0

# Comparison of two non-error values; an empty side takes the zero value of the other.
fn compare_values(a: Value, b: Value) Int:
    var x = a.clone()
    var y = b.clone()
    if is_blank(x) and is_blank(y):
        return 0

    if is_blank(x):
        x = zero_like(y)
    else if is_blank(y):
        y = zero_like(x)

    let rx = rank(x)
    let ry = rank(y)
    if rx < ry:
        return -1
    if rx > ry:
        return 1
    if rx == 0:
        return float_cmp(num_part(x), num_part(y))
    if rx == 1:
        return str_cmp(text_part(x), text_part(y))

    return float_cmp(flag_num(flag_part(x)), flag_num(flag_part(y)))

fn is_cmp_op(op: String) Bool:
    return op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">="

fn cmp_holds(op: String, c: Int) Bool:
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

fn binary(op: String, a: Value, b: Value) Value:
    if op == "&":
        if is_err(a):
            return a.clone()
        if is_err(b):
            return b.clone()

        return Value.Txt(display(a) + display(b))

    if is_cmp_op(op):
        if is_err(a):
            return a.clone()
        if is_err(b):
            return b.clone()

        return Value.Flag(cmp_holds(op, compare_values(a, b)))

    let x = to_num(a)
    if is_err(x):
        return x

    let y = to_num(b)
    if is_err(y):
        return y

    let p = num_part(x)
    let q = num_part(y)
    if op == "+":
        return finite(p + q)
    if op == "-":
        return finite(p - q)
    if op == "*":
        return finite(p * q)

    if op == "/":
        if q == 0.0:
            return Value.Fail("#DIV/0!")

        return finite(p / q)

    return finite(pow(p, q))

# ---------- lexer ----------

# Length of a reference shape starting at `start` (optional $, letters, optional $, digits),
# or -1 when there is none or it runs into an identifier character, `(` or `$`.
fn ref_end(cs: List[String], start: Int) Int:
    let n = cs.length()
    var i = start
    if i < n and cs[i] == "$":
        i += 1

    let l0 = i
    while i < n and is_alpha(cs[i]):
        i += 1
    if i == l0:
        return -1

    if i < n and cs[i] == "$":
        i += 1

    let d0 = i
    while i < n and is_digit(cs[i]):
        i += 1
    if i == d0:
        return -1

    if i < n:
        let c = cs[i]
        if is_alpha(c) or is_digit(c) or c == "_" or c == "." or c == "(" or c == "$":
            return -1

    return i

fn lex(src: String) List[Tok]:
    let cs = src.chars()
    let n = cs.length()
    var toks = List[Tok]()
    var i = 0

    while i < n:
        let c = cs[i]

        if is_space(c):
            var j = i
            while j < n and is_space(cs[j]):
                j += 1
            toks.append(Tok.TSpace(join_range(cs, i, j)))
            i = j
        else if c == "\"":
            var j = i + 1
            var val = ""
            var closed = false

            while j < n and not closed:
                if cs[j] == "\"":
                    if j + 1 < n and cs[j + 1] == "\"":
                        val = val + "\""
                        j += 2
                    else:
                        closed = true
                        j += 1
                else:
                    val = val + cs[j]
                    j += 1

            if closed:
                toks.append(Tok.TString(join_range(cs, i, j), val))
            else:
                toks.append(Tok.TBad(join_range(cs, i, n)))

            i = j
        else if is_digit(c) or (c == "." and i + 1 < n and is_digit(cs[i + 1])):
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

            toks.append(Tok.TNumber(join_range(cs, i, j)))
            i = j
        else if is_alpha(c) or c == "_" or c == "$":
            let e1 = ref_end(cs, i)
            var e2 = -1
            if e1 > 0 and e1 < n and cs[e1] == ":":
                e2 = ref_end(cs, e1 + 1)

            if e2 > 0:
                toks.append(Tok.TSpan(join_range(cs, i, e2)))
                i = e2
            else if e1 > 0:
                toks.append(Tok.TRef(join_range(cs, i, e1)))
                i = e1
            else if c == "$":
                toks.append(Tok.TBad(c.clone()))
                i += 1
            else:
                var j = i
                while (
                    j < n
                    and (
                        is_alpha(cs[j])
                        or is_digit(cs[j])
                        or cs[j] == "_"
                        or cs[j] == "."
                    )
                ):
                    j += 1
                toks.append(Tok.TWord(join_range(cs, i, j)))
                i = j
        else if c == "#":
            if i + 5 <= n and join_range(cs, i, i + 5) == "#REF!":
                toks.append(Tok.TErrLit("#REF!"))
                i += 5
            else:
                toks.append(Tok.TBad(c.clone()))
                i += 1
        else if c == "<" or c == ">":
            if i + 1 < n and (cs[i + 1] == "=" or (c == "<" and cs[i + 1] == ">")):
                toks.append(Tok.TSym(c + cs[i + 1]))
                i += 2
            else:
                toks.append(Tok.TSym(c.clone()))
                i += 1
        else if "+-*/^&=(),".contains(c):
            toks.append(Tok.TSym(c.clone()))
            i += 1
        else:
            toks.append(Tok.TBad(c.clone()))
            i += 1

    return toks

fn tok_text(t: Tok) String:
    match t:
        TSpace(s):
            return s.clone()
        TWord(s):
            return s.clone()
        TNumber(s):
            return s.clone()
        TString(s, _):
            return s.clone()
        TRef(s):
            return s.clone()
        TSpan(s):
            return s.clone()
        TErrLit(s):
            return s.clone()
        TSym(s):
            return s.clone()
        TBad(s):
            return s.clone()

# A reference token: optional $, one or more letters, optional $, digits. Valid only when it names a real cell.
fn parse_corner(t: String) Corner:
    let cs = t.chars()
    let n = cs.length()
    var i = 0
    var ac = false

    if i < n and cs[i] == "$":
        ac = true
        i += 1

    var letters = 0
    var col = 0

    while i < n and is_alpha(cs[i]):
        let k = cs[i].scalar_at(0)

        if k >= 97:
            col = k - 97
        else:
            col = k - 65

        letters += 1
        i += 1

    var ar = false

    if i < n and cs[i] == "$":
        ar = true
        i += 1

    var digits = 0
    var row = 0
    var lead_zero = false

    while i < n and is_digit(cs[i]):
        if digits == 0 and cs[i] == "0":
            lead_zero = true
        row = row * 10 + (cs[i].scalar_at(0) - 48)
        digits += 1
        i += 1

    let ok = (
        i == n
        and letters == 1
        and digits >= 1
        and digits <= 3
        and not lead_zero
        and row >= 1
        and row <= 999
    )
    return Corner(ok, col, row, ac, ar)

# ---------- parser ----------

fn parse_formula(src: String) Node:
    var toks = List[Tok]()

    for t in lex(src):
        match t:
            TSpace(_):
                continue
            TBad(_):
                return Node.Lit(Value.Fail("#PARSE!"))
            _:
                toks.append(t.clone())

    var p = Parser(toks, 0, false)
    let tree = p.expr()
    if p.bad or p.pos != p.toks.length():
        return Node.Lit(Value.Fail("#PARSE!"))

    return tree

impl Parser:
    fn cur() String:
        if self.pos >= self.toks.length():
            return ""

        match self.toks[self.pos]:
            TSym(s):
                return s.clone()
            _:
                return ""

    var fn expr() Node:
        var left = self.concat_expr()

        while is_cmp_op(self.cur()):
            let op = self.cur()
            self.pos += 1

            let right = self.concat_expr()
            left = Node.Bin(op, left, right)

        return left

    var fn concat_expr() Node:
        var left = self.additive()

        while self.cur() == "&":
            self.pos += 1

            let right = self.additive()
            left = Node.Bin("&", left, right)

        return left

    var fn additive() Node:
        var left = self.mult()

        while self.cur() == "+" or self.cur() == "-":
            let op = self.cur()
            self.pos += 1

            let right = self.mult()
            left = Node.Bin(op, left, right)

        return left

    var fn mult() Node:
        var left = self.unary()

        while self.cur() == "*" or self.cur() == "/":
            let op = self.cur()
            self.pos += 1

            let right = self.unary()
            left = Node.Bin(op, left, right)

        return left

    var fn unary() Node:
        let c = self.cur()

        if c == "+" or c == "-":
            self.pos += 1

            let x = self.unary()
            return Node.Neg(c == "-", x)

        return self.power()

    var fn power() Node:
        let base = self.primary()

        if self.cur() == "^":
            self.pos += 1

            let e = self.signed_power()
            return Node.Bin("^", base, e)

        return base

    var fn signed_power() Node:
        let c = self.cur()

        if c == "+" or c == "-":
            self.pos += 1

            let x = self.signed_power()
            return Node.Neg(c == "-", x)

        return self.power()

    var fn primary() Node:
        if self.pos >= self.toks.length():
            self.bad = true
            return Node.Lit(Value.Fail("#PARSE!"))

        let t = self.toks[self.pos].clone()
        self.pos += 1

        match t:
            TNumber(text):
                if let x = number_text(text):
                    return Node.Lit(Value.Num(x))

                return Node.Lit(Value.Fail("#NUM!"))
            TString(_, value):
                return Node.Lit(Value.Txt(value.clone()))
            TRef(text):
                let c = parse_corner(text)
                return Node.Ref(c.valid, c.col, c.row)
            TSpan(text):
                let parts = text.split(":")
                let a = parse_corner(parts[0].clone())
                let b = parse_corner(parts[1].clone())
                return Node.Span(a.valid and b.valid, a.col, a.row, b.col, b.row)
            TErrLit(_):
                return Node.Lit(Value.Fail("#REF!"))
            TWord(name):
                if self.cur() == "(":
                    self.pos += 1
                    return self.call(name.clone())

                let up = name.upper()
                if up == "TRUE":
                    return Node.Lit(Value.Flag(true))
                if up == "FALSE":
                    return Node.Lit(Value.Flag(false))

                return Node.Lit(Value.Fail("#NAME?"))
            TSym(s):
                if s == "(":
                    let e = self.expr()

                    if self.cur() == ")":
                        self.pos += 1
                    else:
                        self.bad = true

                    return e

                self.bad = true
                return Node.Lit(Value.Fail("#PARSE!"))
            _:
                self.bad = true
                return Node.Lit(Value.Fail("#PARSE!"))

    var fn call(name: String) Node:
        var args = List[Node]()

        if self.cur() == ")":
            self.pos += 1
            return Node.Call(name.clone(), args)

        var done = false

        while not done:
            args.append(self.expr())

            let c = self.cur()

            if c == ",":
                self.pos += 1
            else if c == ")":
                self.pos += 1
                done = true
            else:
                self.bad = true
                done = true

        return Node.Call(name.clone(), args)

# ---------- precedents ----------

fn collect(n: Node, var acc: Set[Int]) Unit:
    match n:
        Ref(valid, col, row):
            if valid:
                acc.add(cid(row, col))
        Span(valid, c1, r1, c2, r2):
            if valid:
                for r in lo(r1, r2)..hi(r1, r2) + 1:
                    for c in lo(c1, c2)..hi(c1, c2) + 1:
                        acc.add(cid(r, c))
        Neg(_, x):
            collect(x, var acc)
        Bin(_, l, r):
            collect(l, var acc)
            collect(r, var acc)
        Call(name, args):
            let f = name.upper()
            if f != "ROW" and f != "COLUMN":
                for a in args:
                    collect(a, var acc)
        _:
            return

    return

fn precs_of(tree: Node) Set[Int]:
    var acc = Set[Int]()
    collect(tree, var acc)
    return acc

# ---------- evaluation ----------

# A rectangle of cells named by a range argument, or a flag that the argument is not a range.
type Rect:
    is_span: Bool
    valid: Bool
    top: Int
    left: Int
    bottom: Int
    right: Int
    first_row: Int
    first_col: Int

fn rect_of(n: Node) Rect:
    match n:
        Span(valid, c1, r1, c2, r2):
            return Rect(
                true, valid, lo(r1, r2), lo(c1, c2), hi(r1, r2), hi(c1, c2), r1, c1
            )
        _:
            return Rect(false, false, 0, 0, 0, 0, 0, 0)

# Items of the aggregate arguments: range cells in row-major order, or single values.
fn items_of(vals: Map[Int, Value], args: List[Node]) List[Item]:
    var out = List[Item]()

    for a in args:
        let rc = rect_of(a)

        if rc.is_span:
            if not rc.valid:
                out.append(Item(Value.Fail("#REF!"), false))
            else:
                for r in rc.top..rc.bottom + 1:
                    for c in rc.left..rc.right + 1:
                        out.append(Item(vals.get_or(cid(r, c), Value.Blank), true))
        else:
            out.append(Item(eval(vals, a), false))

    return out

fn gather(items: List[Item]) Nums:
    var xs = List[Float]()

    for it in items:
        if is_err(it.v):
            return Nums(it.v.clone(), xs)

        if it.ranged:
            if is_number(it.v):
                xs.append(num_part(it.v))
        else:
            let x = to_num(it.v)
            if is_err(x):
                return Nums(x, xs)

            xs.append(num_part(x))

    return Nums(Value.Blank, xs)

fn stat_fn(vals: Map[Int, Value], f: String, args: List[Node]) Value:
    if args.length() == 0:
        return Value.Fail("#VALUE!")

    let g = gather(items_of(vals, args))
    if is_err(g.fail):
        return g.fail.clone()

    let xs = g.xs.clone()
    let n = xs.length()

    if f == "SUM" or f == "AVERAGE":
        var total = 0.0
        for x in xs:
            total += x
        if f == "SUM":
            return finite(total)
        if n == 0:
            return Value.Fail("#DIV/0!")

        return finite(total / n.to_float())

    if f == "MIN" or f == "MAX":
        if n == 0:
            return Value.Num(0.0)

        let first = xs[0]
        var best = first

        for x in xs:
            if f == "MIN" and x < best:
                best = x
            if f == "MAX" and x > best:
                best = x

        return Value.Num(best)

    if f == "PRODUCT":
        if n == 0:
            return Value.Num(0.0)

        var p = 1.0
        for x in xs:
            p *= x
        return finite(p)

    if n == 0:
        return Value.Fail("#NUM!")

    let s = xs.sorted()
    if n % 2 == 1:
        return Value.Num(s[n / 2])

    return finite((s[n / 2 - 1] + s[n / 2]) / 2.0)

fn count_fn(vals: Map[Int, Value], args: List[Node], numeric: Bool) Value:
    if args.length() == 0:
        return Value.Fail("#VALUE!")

    var c = 0

    for it in items_of(vals, args):
        if numeric:
            if is_number(it.v):
                c += 1
        else if not is_blank(it.v):
            c += 1

    return Value.Num(c.to_float())

fn if_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() < 2 or args.length() > 3:
        return Value.Fail("#VALUE!")

    let t = truth(eval(vals, args[0]))
    if is_err(t):
        return t
    if flag_part(t):
        return eval(vals, args[1])
    if args.length() == 3:
        return eval(vals, args[2])

    return Value.Flag(false)

fn iferror_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() != 2:
        return Value.Fail("#VALUE!")

    let a = eval(vals, args[0])
    if is_err(a):
        return eval(vals, args[1])

    return a

fn choose_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() < 2:
        return Value.Fail("#VALUE!")

    let iv = to_num(eval(vals, args[0]))
    if is_err(iv):
        return iv

    let k = floor(num_part(iv))
    if k < 1.0 or k > (args.length() - 1).to_float():
        return Value.Fail("#VALUE!")

    return eval(vals, args[k.truncate_to_int().get(1)])

fn logic_fn(vals: Map[Int, Value], args: List[Node], is_and: Bool) Value:
    if args.length() == 0:
        return Value.Fail("#VALUE!")

    var seen = 0
    var all_true = true
    var any_true = false

    for it in items_of(vals, args):
        if is_err(it.v):
            return it.v.clone()
        if it.ranged and (is_blank(it.v) or is_text(it.v)):
            continue

        let t = truth(it.v)
        if is_err(t):
            return t

        seen += 1

        if flag_part(t):
            any_true = true
        else:
            all_true = false

    if seen == 0:
        return Value.Fail("#VALUE!")
    if is_and:
        return Value.Flag(all_true)

    return Value.Flag(any_true)

fn not_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() != 1:
        return Value.Fail("#VALUE!")

    let t = truth(eval(vals, args[0]))
    if is_err(t):
        return t

    return Value.Flag(not flag_part(t))

fn unary_num(vals: Map[Int, Value], args: List[Node], f: String) Value:
    if args.length() != 1:
        return Value.Fail("#VALUE!")

    let x = to_num(eval(vals, args[0]))
    if is_err(x):
        return x

    let p = num_part(x)
    if f == "ABS":
        return finite(p.abs())
    if f == "INT":
        return finite(floor(p))
    if p < 0.0:
        return Value.Fail("#NUM!")

    return finite(sqrt(p))

fn two_nums(vals: Map[Int, Value], args: List[Node]) Nums:
    let a = to_num(eval(vals, args[0]))
    if is_err(a):
        return Nums(a, List[Float]())

    let b = to_num(eval(vals, args[1]))
    if is_err(b):
        return Nums(b, List[Float]())

    var xs = List[Float]()
    xs.append(num_part(a))
    xs.append(num_part(b))
    return Nums(Value.Blank, xs)

fn mod_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() != 2:
        return Value.Fail("#VALUE!")

    let g = two_nums(vals, args)
    if is_err(g.fail):
        return g.fail.clone()

    let p = g.xs[0]
    let q = g.xs[1]
    if q == 0.0:
        return Value.Fail("#DIV/0!")

    return finite(p - q * floor(p / q))

fn round_half_away(y: Float) Float:
    let a = y.abs()
    let f = floor(a)
    var r = f
    if a - f >= 0.5:
        r = f + 1.0
    if y < 0.0:
        return -r

    return r

fn round_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() < 1 or args.length() > 2:
        return Value.Fail("#VALUE!")

    let xv = to_num(eval(vals, args[0]))
    if is_err(xv):
        return xv

    var dk = 0

    if args.length() == 2:
        let dv = to_num(eval(vals, args[1]))
        if is_err(dv):
            return dv

        dk = num_part(dv).truncate_to_int().get(100)

    if dk > 15 or dk < -15:
        return Value.Fail("#NUM!")

    let p = pow(10.0, dk.to_float())
    let y = num_part(xv) * p
    if not y.is_finite():
        return Value.Fail("#NUM!")

    return finite(round_half_away(y) / p)

fn len_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() != 1:
        return Value.Fail("#VALUE!")

    let v = eval(vals, args[0])
    if is_err(v):
        return v

    return Value.Num(display(v).scalar_length().to_float())

fn case_fn(vals: Map[Int, Value], args: List[Node], upper: Bool) Value:
    if args.length() != 1:
        return Value.Fail("#VALUE!")

    let v = eval(vals, args[0])
    if is_err(v):
        return v

    return Value.Txt(map_ascii(display(v), upper))

fn trim_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() != 1:
        return Value.Fail("#VALUE!")

    let v = eval(vals, args[0])
    if is_err(v):
        return v

    return Value.Txt(trim_collapse(display(v)))

fn left_right(vals: Map[Int, Value], args: List[Node], from_left: Bool) Value:
    if args.length() < 1 or args.length() > 2:
        return Value.Fail("#VALUE!")

    let sv = eval(vals, args[0])
    if is_err(sv):
        return sv

    var k = 1.0

    if args.length() == 2:
        let nv = to_num(eval(vals, args[1]))
        if is_err(nv):
            return nv

        k = floor(num_part(nv))

    if k < 0.0:
        return Value.Fail("#VALUE!")

    let cs = display(sv).chars()
    let len = cs.length()
    var take = len
    if k < len.to_float():
        take = k.truncate_to_int().get(0)
    if from_left:
        return Value.Txt(join_range(cs, 0, take))

    return Value.Txt(join_range(cs, len - take, len))

fn mid_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() != 3:
        return Value.Fail("#VALUE!")

    let sv = eval(vals, args[0])
    if is_err(sv):
        return sv

    let stv = to_num(eval(vals, args[1]))
    if is_err(stv):
        return stv

    let lnv = to_num(eval(vals, args[2]))
    if is_err(lnv):
        return lnv

    let st = floor(num_part(stv))
    let ln = floor(num_part(lnv))
    if st < 1.0 or ln < 0.0:
        return Value.Fail("#VALUE!")

    let cs = display(sv).chars()
    let n = cs.length()
    if st > n.to_float():
        return Value.Txt("")

    let s0 = st.truncate_to_int().get(1) - 1
    var cnt = n - s0
    if ln < cnt.to_float():
        cnt = ln.truncate_to_int().get(0)
    return Value.Txt(join_range(cs, s0, s0 + cnt))

fn concat_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() == 0:
        return Value.Fail("#VALUE!")

    var out = ""

    for it in items_of(vals, args):
        if is_err(it.v):
            return it.v.clone()

        out = out + display(it.v)

    return Value.Txt(out)

fn substitute_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() != 3:
        return Value.Fail("#VALUE!")

    let sv = eval(vals, args[0])
    if is_err(sv):
        return sv

    let ov = eval(vals, args[1])
    if is_err(ov):
        return ov

    let nv = eval(vals, args[2])
    if is_err(nv):
        return nv

    let so = display(sv)
    let oo = display(ov)
    if oo == "":
        return Value.Txt(so)

    return Value.Txt(so.replace(oo, display(nv)))

fn value_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() != 1:
        return Value.Fail("#VALUE!")

    return to_num(eval(vals, args[0]))

fn is_fn(vals: Map[Int, Value], args: List[Node], f: String) Value:
    if args.length() != 1:
        return Value.Fail("#VALUE!")

    let v = eval(vals, args[0])
    if f == "ISERROR":
        return Value.Flag(is_err(v))
    if f == "ISBLANK":
        return Value.Flag(is_blank(v))
    if f == "ISNUMBER":
        return Value.Flag(is_number(v))

    return Value.Flag(is_text(v))

fn row_col(args: List[Node], want_row: Bool) Value:
    if args.length() != 1:
        return Value.Fail("#VALUE!")

    match args[0]:
        Ref(valid, col, row):
            if not valid:
                return Value.Fail("#REF!")
            if want_row:
                return Value.Num(row.to_float())

            return Value.Num((col + 1).to_float())
        Span(valid, c1, r1, c2, r2):
            if not valid:
                return Value.Fail("#REF!")
            if want_row:
                return Value.Num(lo(r1, r2).to_float())

            return Value.Num((lo(c1, c2) + 1).to_float())
        _:
            return Value.Fail("#VALUE!")

fn index_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() < 2 or args.length() > 3:
        return Value.Fail("#VALUE!")

    let rc = rect_of(args[0])
    if not rc.is_span:
        return Value.Fail("#VALUE!")
    if not rc.valid:
        return Value.Fail("#REF!")

    let rv = to_num(eval(vals, args[1]))
    if is_err(rv):
        return rv

    let height = (rc.bottom - rc.top + 1).to_float()
    let width = (rc.right - rc.left + 1).to_float()
    var ri = 1.0
    var ci = 1.0

    if args.length() == 2:
        if height == 1.0:
            ci = floor(num_part(rv))
        else:
            ri = floor(num_part(rv))
    else:
        let cv = to_num(eval(vals, args[2]))
        if is_err(cv):
            return cv

        ri = floor(num_part(rv))
        ci = floor(num_part(cv))

    if ri < 1.0 or ri > height or ci < 1.0 or ci > width:
        return Value.Fail("#REF!")

    let r = rc.top + ri.truncate_to_int().get(1) - 1
    let c = rc.left + ci.truncate_to_int().get(1) - 1
    return vals.get_or(cid(r, c), Value.Blank)

fn make_crit(s: String) Crit:
    var op = "="
    var rest = s.clone()
    let n = s.scalar_length()

    if s.starts_with(">="):
        op = ">="
        rest = s.slice_scalars(2, n).get()
    else if s.starts_with("<="):
        op = "<="
        rest = s.slice_scalars(2, n).get()
    else if s.starts_with("<>"):
        op = "<>"
        rest = s.slice_scalars(2, n).get()
    else if s.starts_with(">"):
        op = ">"
        rest = s.slice_scalars(1, n).get()
    else if s.starts_with("<"):
        op = "<"
        rest = s.slice_scalars(1, n).get()
    else if s.starts_with("="):
        op = "="
        rest = s.slice_scalars(1, n).get()

    if let x = number_text(rest):
        return Crit(op, Value.Num(x))

    return Crit(op, Value.Txt(rest))

fn countif_fn(vals: Map[Int, Value], args: List[Node]) Value:
    if args.length() != 2:
        return Value.Fail("#VALUE!")

    let rc = rect_of(args[0])
    if not rc.is_span:
        return Value.Fail("#VALUE!")
    if not rc.valid:
        return Value.Fail("#REF!")

    let crit = eval(vals, args[1])
    if is_err(crit):
        return crit

    var cr = Crit("=", crit.clone())

    match crit:
        Txt(s):
            cr = make_crit(s)
        _:
            cr = Crit("=", crit.clone())

    var count = 0

    for r in rc.top..rc.bottom + 1:
        for c in rc.left..rc.right + 1:
            let v = vals.get_or(cid(r, c), Value.Blank)

            if kind_of(v) == kind_of(cr.operand):
                if cmp_holds(cr.op, compare_values(v, cr.operand)):
                    count += 1
            else if cr.op == "<>" and not is_blank(v):
                count += 1

    return Value.Num(count.to_float())

fn call_fn(vals: Map[Int, Value], name: String, args: List[Node]) Value:
    let f = name.upper()
    if (
        f == "SUM"
        or f == "AVERAGE"
        or f == "MIN"
        or f == "MAX"
        or f == "PRODUCT"
        or f == "MEDIAN"
    ):
        return stat_fn(vals, f, args)
    if f == "COUNT":
        return count_fn(vals, args, true)
    if f == "COUNTA":
        return count_fn(vals, args, false)
    if f == "IF":
        return if_fn(vals, args)
    if f == "IFERROR":
        return iferror_fn(vals, args)
    if f == "CHOOSE":
        return choose_fn(vals, args)
    if f == "AND":
        return logic_fn(vals, args, true)
    if f == "OR":
        return logic_fn(vals, args, false)
    if f == "NOT":
        return not_fn(vals, args)
    if f == "ABS" or f == "INT" or f == "SQRT":
        return unary_num(vals, args, f)

    if f == "POW":
        if args.length() != 2:
            return Value.Fail("#VALUE!")

        return binary("^", eval(vals, args[0]), eval(vals, args[1]))

    if f == "MOD":
        return mod_fn(vals, args)
    if f == "ROUND":
        return round_fn(vals, args)
    if f == "LEN":
        return len_fn(vals, args)
    if f == "UPPER" or f == "LOWER":
        return case_fn(vals, args, f == "UPPER")
    if f == "TRIM":
        return trim_fn(vals, args)
    if f == "LEFT" or f == "RIGHT":
        return left_right(vals, args, f == "LEFT")
    if f == "MID":
        return mid_fn(vals, args)
    if f == "CONCAT":
        return concat_fn(vals, args)
    if f == "SUBSTITUTE":
        return substitute_fn(vals, args)
    if f == "VALUE":
        return value_fn(vals, args)
    if f == "ISERROR" or f == "ISBLANK" or f == "ISNUMBER" or f == "ISTEXT":
        return is_fn(vals, args, f)
    if f == "ROW":
        return row_col(args, true)
    if f == "COLUMN":
        return row_col(args, false)
    if f == "INDEX":
        return index_fn(vals, args)
    if f == "COUNTIF":
        return countif_fn(vals, args)

    return Value.Fail("#NAME?")

fn eval(vals: Map[Int, Value], n: Node) Value:
    match n:
        Lit(v):
            return v.clone()
        Ref(valid, col, row):
            if not valid:
                return Value.Fail("#REF!")

            return vals.get_or(cid(row, col), Value.Blank)
        Span(_, _, _, _, _):
            return Value.Fail("#VALUE!")
        Neg(negate, x):
            let v = to_num(eval(vals, x))
            if not negate:
                return v
            if is_err(v):
                return v

            return Value.Num(-num_part(v))
        Bin(op, l, r):
            let a = eval(vals, l)
            let b = eval(vals, r)
            return binary(op, a, b)
        Call(name, args):
            return call_fn(vals, name, args)

# ---------- formula text shifting (copy) ----------

fn shift_corner(t: String, dc: Int, dr: Int) Optional[String]:
    var c = parse_corner(t)
    if not c.valid:
        return some(t.clone())

    var col = c.col
    var row = c.row
    if not c.abs_col:
        col = col + dc
    if not c.abs_row:
        row = row + dr
    if col < 0 or col > 25 or row < 1 or row > 999:
        return none

    return some(canon_ref(c.abs_col, col, c.abs_row, row))

fn shift_formula(src: String, dc: Int, dr: Int) String:
    let toks = lex(src)

    for t in toks:
        match t:
            TBad(_):
                return src.clone()
            _:
                continue

    var out = ""

    for t in toks:
        match t:
            TRef(text):
                if let s = shift_corner(text, dc, dr):
                    out = out + s
                else:
                    out = out + "#REF!"
            TSpan(text):
                let parts = text.split(":")
                let a = shift_corner(parts[0].clone(), dc, dr)
                let b = shift_corner(parts[1].clone(), dc, dr)

                if let x = a:
                    if let y = b:
                        out = out + x + ":" + y
                    else:
                        out = out + "#REF!"
                else:
                    out = out + "#REF!"
            _:
                out = out + tok_text(t)

    return out

# ---------- CSV ----------

# Records of an import block: quoted sections span lines, blank records are skipped.
fn csv_records(block: List[String]) List[List[String]]:
    var recs = List[List[String]]()
    var fields = List[String]()
    var field = ""
    var inq = false
    var used = false

    for line in block:
        let cs = line.chars()
        let n = cs.length()
        var k = 0

        while k < n:
            let c = cs[k]

            if inq:
                if c == "\"":
                    if k + 1 < n and cs[k + 1] == "\"":
                        field = field + "\""
                        k += 2
                    else:
                        inq = false
                        k += 1
                else:
                    field = field + c
                    k += 1
            else if c == "\"":
                inq = true
                used = true
                k += 1
            else if c == ",":
                fields.append(field)
                field = ""
                used = true
                k += 1
            else if c == "\r":
                k += 1
            else:
                field = field + c
                used = true
                k += 1

        if inq:
            field = field + "\n"
        else:
            if used:
                fields.append(field)
                recs.append(fields)

            fields = List[String]()
            field = ""
            used = false

    if used:
        fields.append(field)
        recs.append(fields)

    return recs

fn csv_field(s: String) String:
    if (
        s.contains(",")
        or s.contains("\"")
        or s.contains("\n")
        or s.contains("\r")
        or s.starts_with(" ")
        or s.ends_with(" ")
    ):
        return "\"" + s.replace("\"", "\"\"") + "\""

    return s

# ---------- ranges given on the command line ----------

fn cell_arg(s: String) Int:
    if s.contains("$"):
        return -1

    let c = parse_corner(s)
    if not c.valid:
        return -1

    return cid(c.row, c.col)

fn area_arg(s: String) Area:
    if s.contains("$"):
        return bad_area()

    let parts = s.split(":")
    if parts.length() > 2:
        return bad_area()

    let a = cell_arg(parts[0].clone())
    if a < 0:
        return bad_area()

    var b = a

    if parts.length() == 2:
        b = cell_arg(parts[1].clone())
        if b < 0:
            return bad_area()

    return Area(
        true, lo(row_of(a), row_of(b)), lo(col_of(a), col_of(b)),
        hi(row_of(a), row_of(b)), hi(col_of(a), col_of(b))
    )

fn names_line(ids: List[Int]) String:
    if ids.length() == 0:
        return "(none)"

    var s = ""

    for k in 0..ids.length():
        if k > 0:
            s = s + " "
        s = s + cell_name(ids[k])

    return s

# ---------- the sheet ----------

impl Sheet:
    fn is_formula(id: Int) Bool:
        if let c = self.cells.get(id):
            return c.formula

        return false

    fn eval_cell(id: Int) Value:
        if let c = self.cells.get(id):
            let v = eval(self.vals, c.tree)
            if is_blank(v):
                return Value.Num(0.0)

            return v

        return Value.Blank

    var fn detach(id: Int) Unit:
        if let old = self.cells.get(id):
            if old.formula:
                for p in old.precs:
                    if var s = self.deps.get(p):
                        s.remove(id)

    var fn attach(id: Int, p: Int) Unit:
        if not self.deps.contains(p):
            self.deps.add(p, Set[Int]())
        if var s = self.deps.get(p):
            s.add(id)

    # Stores the content of a cell from its raw text (empty clears it).
    var fn assign(id: Int, raw: String) Unit:
        self.detach(id)
        self.cells.remove(id)
        self.vals.remove(id)
        if raw == "":
            return

        if raw.starts_with("="):
            let tree = parse_formula(raw.slice_scalars(1, raw.scalar_length()).get())
            let precs = precs_of(tree)
            for p in precs:
                self.attach(id, p)
            self.cells.add(id, Cell(raw.clone(), true, tree, precs))
            return

        self.cells.add(id, Cell(raw.clone(), false, Node.Lit(Value.Blank), Set[Int]()))
        self.vals.add(id, constant_value(raw))

    # Recalculates the changed cells and everything that depends on them. Returns the affected count.
    var fn recalc(changed: List[Int]) Int:
        var reach = Set[Int]()
        var queue = List[Int]()

        for c in changed:
            if self.is_formula(c):
                reach.add(c)
            queue.append(c)

        var head = 0

        while head < queue.length():
            let u = queue[head]
            head += 1

            if let ds = self.deps.get(u):
                for v in ds:
                    if not reach.contains(v):
                        reach.add(v)
                        queue.append(v)

        var tj = Tarjan(
            Map[Int, Int](), Map[Int, Int](), Set[Int](), List[Int](), Set[Int](), 0,
            List[Group]()
        )
        for v in reach:
            if not tj.index.contains(v):
                tj.visit(v, self.cells, reach)

        for g in tj.groups:
            if g.cyclic:
                for m in g.members:
                    self.vals.add(m, Value.Fail("#CYCLE!"))
            else:
                let v = self.eval_cell(g.members[0])
                self.vals.add(g.members[0], v)

        let n = reach.length()
        self.evals += n
        return n

    fn used_area() Area:
        var maxr = 1
        var maxc = 0

        for k in self.cells.keys():
            if row_of(k) > maxr:
                maxr = row_of(k)
            if col_of(k) > maxc:
                maxc = col_of(k)

        return Area(true, 1, 0, maxr, maxc)

    fn dependents_of(id: Int) List[Int]:
        var seen = Set[Int]()
        var queue = List[Int]()
        queue.append(id)

        var head = 0

        while head < queue.length():
            let u = queue[head]
            head += 1

            if let ds = self.deps.get(u):
                for v in ds:
                    if not seen.contains(v):
                        seen.add(v)
                        queue.append(v)

        var out = List[Int]()
        for v in seen:
            out.append(v)
        return out.sorted()

    var fn cmd_set(line: String, words: List[String]) Unit:
        if words.length() == 1:
            say("error: usage: set CELL VALUE")
            return

        let id = cell_arg(words[1])

        if id < 0:
            say("error: bad cell reference '" + words[1] + "'")
            return

        self.assign(id, skip_words(line, 2))

        let n = self.recalc(list_of(id))
        say("recalc " + n.to_string())

    var fn cmd_clear(words: List[String]) Unit:
        if words.length() != 2:
            say("error: usage: clear CELL")
            return

        let id = cell_arg(words[1])

        if id < 0:
            say("error: bad cell reference '" + words[1] + "'")
            return

        self.assign(id, "")

        let n = self.recalc(list_of(id))
        say("recalc " + n.to_string())

    var fn cmd_get(words: List[String]) Unit:
        if words.length() != 2:
            say("error: usage: get CELL")
            return

        let id = cell_arg(words[1])

        if id < 0:
            say("error: bad cell reference '" + words[1] + "'")
            return

        if not self.cells.contains(id):
            say("(empty)")
            return

        say(display(self.vals.get_or(id, Value.Blank)))

    var fn cmd_show(words: List[String]) Unit:
        if words.length() != 2:
            say("error: usage: show CELL")
            return

        let id = cell_arg(words[1])

        if id < 0:
            say("error: bad cell reference '" + words[1] + "'")
            return

        let name = cell_name(id)

        if let c = self.cells.get(id):
            if c.formula:
                say(
                    name + ": " + c.raw + " => " + display(
                        self.vals.get_or(id, Value.Blank)
                    )
                )
            else:
                say(name + ": " + c.raw)
        else:
            say(name + ": (empty)")

    var fn cmd_relations(words: List[String], precedents: Bool) Unit:
        if words.length() != 2:
            if precedents:
                say("error: usage: precedents CELL")
            else:
                say("error: usage: dependents CELL")

            return

        let id = cell_arg(words[1])

        if id < 0:
            say("error: bad cell reference '" + words[1] + "'")
            return

        if precedents:
            var out = List[Int]()
            if let c = self.cells.get(id):
                if c.formula:
                    for p in c.precs:
                        out.append(p)
            say(names_line(out.sorted()))
        else:
            say(names_line(self.dependents_of(id)))

    var fn cmd_print(words: List[String]) Unit:
        if words.length() > 2 or (words.length() == 2 and words[1] == "formulas"):
            say("error: usage: print [RANGE]")
            return

        var a = self.used_area()

        if words.length() == 2:
            a = area_arg(words[1])

            if not a.valid:
                say("error: bad range '" + words[1] + "'")
                return
        else if self.cells.length() == 0:
            say("(empty sheet)")
            return

        for r in a.top..a.bottom + 1:
            var line = ""

            for c in a.left..a.right + 1:
                if c > a.left:
                    line = line + " | "
                line = line + display(self.vals.get_or(cid(r, c), Value.Blank))

            say(line)

    var fn cmd_export(words: List[String]) Unit:
        var formulas = false
        var modes = 0
        var ranges = 0
        var range_word = ""
        var k = 1

        while k < words.length():
            let w = words[k]

            if w == "formulas" or w == "values":
                modes += 1
                formulas = w == "formulas"
            else:
                ranges += 1
                range_word = w.clone()

            k += 1

        if words.length() > 3 or modes > 1 or ranges > 1:
            say("error: usage: export [formulas] [RANGE]")
            return

        var a = self.used_area()

        if ranges == 1:
            a = area_arg(range_word)

            if not a.valid:
                say("error: bad range '" + range_word + "'")
                return
        else if self.cells.length() == 0:
            say("(empty sheet)")
            return

        for r in a.top..a.bottom + 1:
            var line = ""

            for c in a.left..a.right + 1:
                if c > a.left:
                    line = line + ","

                let id = cid(r, c)
                var text = ""

                if formulas:
                    if let cell = self.cells.get(id):
                        text = cell.raw.clone()
                else:
                    text = display(self.vals.get_or(id, Value.Blank))

                line = line + csv_field(text)

            say(line)

    var fn cmd_copy(words: List[String]) Unit:
        if words.length() != 3:
            say("error: usage: copy SRC DST")
            return

        let src = cell_arg(words[1])

        if src < 0:
            say("error: bad cell reference '" + words[1] + "'")
            return

        let dst = area_arg(words[2])

        if not dst.valid:
            say("error: bad range '" + words[2] + "'")
            return

        var raw = ""
        var is_f = false

        if let c = self.cells.get(src):
            raw = c.raw.clone()
            is_f = c.formula

        var body = ""
        if is_f:
            body = raw.slice_scalars(1, raw.scalar_length()).get()

        var ids = List[Int]()

        for r in dst.top..dst.bottom + 1:
            for c in dst.left..dst.right + 1:
                let target = cid(r, c)
                var nr = raw.clone()
                if is_f:
                    nr = (
                        "="
                        + shift_formula(
                            body.clone(), c - col_of(src), r - row_of(src)
                        )
                    )
                self.assign(target, nr)
                ids.append(target)

        let n = self.recalc(ids)
        say("recalc " + n.to_string())

    var fn cmd_import(words: List[String], block: List[String]) Unit:
        if words.length() != 2:
            say("error: usage: import CELL")
            return

        let id = cell_arg(words[1])

        if id < 0:
            say("error: bad cell reference '" + words[1] + "'")
            return

        let recs = csv_records(block)
        let rows = recs.length()
        var cols = 0
        for rec in recs:
            if rec.length() > cols:
                cols = rec.length()

        let r0 = row_of(id)
        let c0 = col_of(id)

        if r0 + rows - 1 > 999 or c0 + cols - 1 > 25:
            say("error: import out of range")
            return

        var changed = List[Int]()

        for i in 0..rows:
            for j in 0..recs[i].length():
                let target = cid(r0 + i, c0 + j)
                self.assign(target, recs[i][j].trim())
                changed.append(target)

        let n = self.recalc(changed)
        say(
            "imported "
            + rows.to_string()
            + " rows, "
            + cols.to_string()
            + " columns; recalc "
            + n.to_string()
        )

    var fn command(line: String, words: List[String], block: List[String]) Unit:
        let cmd = words[0]

        if cmd == "set":
            self.cmd_set(line, words)
        else if cmd == "clear":
            self.cmd_clear(words)
        else if cmd == "get":
            self.cmd_get(words)
        else if cmd == "show":
            self.cmd_show(words)
        else if cmd == "print":
            self.cmd_print(words)
        else if cmd == "export":
            self.cmd_export(words)
        else if cmd == "import":
            self.cmd_import(words, block)
        else if cmd == "copy":
            self.cmd_copy(words)
        else if cmd == "precedents":
            self.cmd_relations(words, true)
        else if cmd == "dependents":
            self.cmd_relations(words, false)
        else if cmd == "stats":
            var formulas = 0
            for k in self.cells.keys():
                if self.is_formula(k):
                    formulas += 1
            say(
                "cells "
                + self.cells.length().to_string()
                + " formulas "
                + formulas.to_string()
                + " evals "
                + self.evals.to_string()
            )
        else:
            say("error: unknown command '" + cmd + "'")

impl Tarjan:
    var fn visit(v: Int, cells: Map[Int, Cell], reach: Set[Int]) Unit:
        self.index.add(v, self.counter)
        self.low.add(v, self.counter)
        self.counter += 1
        self.stack.append(v)
        self.onstack.add(v)

        if let c = cells.get(v):
            for w in c.precs:
                if not reach.contains(w):
                    continue

                if w == v:
                    self.selfloop.add(v)

                if not self.index.contains(w):
                    self.visit(w, cells, reach)

                    let lw = self.low.get_or(w, 0)
                    if lw < self.low.get_or(v, 0):
                        self.low.add(v, lw)
                else if self.onstack.contains(w):
                    let iw = self.index.get_or(w, 0)
                    if iw < self.low.get_or(v, 0):
                        self.low.add(v, iw)

        if self.low.get_or(v, 0) == self.index.get_or(v, 0):
            var members = List[Int]()
            var done = false

            while not done:
                let top = self.stack.pop().get(v)
                self.onstack.remove(top)
                members.append(top)
                if top == v:
                    done = true

            let cyc = members.length() > 1 or self.selfloop.contains(v)
            self.groups.append(Group(members, cyc))

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var sheet = Sheet(Map[Int, Cell](), Map[Int, Value](), Map[Int, Set[Int]](), 0)
    var i = 0

    while i < lines.length():
        let line = lines[i].trim_end()
        i += 1

        let words = split_words(line)
        if words.length() == 0 or words[0].starts_with("#"):
            continue

        say("> " + line)

        var block = List[String]()

        if words[0] == "import":
            while i < lines.length() and lines[i] != ".":
                block.append(lines[i].clone())
                i += 1

            if i < lines.length():
                i += 1

        sheet.command(line, words, block)

    return 0
