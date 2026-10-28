from "@std/io.ms" import read_all, stdin, stdout
from "@std/string.ms" import from_scalars

# Backtracking regular-expression engine and the line-oriented command driver from TASK.md.
# Patterns and subjects are byte lists (values 0-255), so raw bytes are handled exactly.

let NL = 10
let TAB = 9
let CR = 13
let QUOTE = 34
let DOT = 46
let DOLLAR = 36
let LPAREN = 40
let RPAREN = 41
let STAR = 42
let PLUS = 43
let COMMA = 44
let DASH = 45
let LT = 60
let GT = 62
let QUESTION = 63
let LBRACKET = 91
let BACKSLASH = 92
let RBRACKET = 93
let CARET = 94
let LBRACE = 123
let BAR = 124
let RBRACE = 125
# Anchor kinds
let BOL = 0
let EOL = 1
let WORDB = 2
let NOTWORDB = 3
let MBOL = 4
let MEOL = 5
# Class members at or above SHORT_BASE stand for the shorthand classes \d \D \w \W \s \S
let SHORT_BASE = 256

def ch(s: String) -> Int:
    return s.scalar_at(0)

def as_list(s: String) -> List[Int]:
    var out = List[Int]()
    for i in 0..s.length():
        out.append(s.scalar_at(i))
    return out

def text_of(data: List[Int]) -> String:
    return from_scalars(data).get()

def is_digit(c: Int) -> Bool:
    return c >= 48 and c <= 57

def is_alpha(c: Int) -> Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

def is_alnum(c: Int) -> Bool:
    return is_alpha(c) or is_digit(c)

def is_word(c: Int) -> Bool:
    return is_alnum(c) or c == 95

def is_flag(c: Int) -> Bool:
    return c == ch("i") or c == ch("m") or c == ch("s")

def hex_value(c: Int) -> Int:
    if is_digit(c):
        return c - 48
    if c >= 97 and c <= 102:
        return c - 87
    if c >= 65 and c <= 70:
        return c - 55

    return -1

def hex_digit(v: Int) -> Int:
    if v < 10:
        return v + 48

    return v + 87

def fold(c: Int) -> Int:
    if c >= 65 and c <= 90:
        return c + 32

    return c

def other_case(c: Int) -> Int:
    if c >= 65 and c <= 90:
        return c + 32
    if c >= 97 and c <= 122:
        return c - 32

    return c

def same(a: List[Int], b: List[Int]) -> Bool:
    if a.length() != b.length():
        return False

    for i in 0..a.length():
        if a[i] != b[i]:
            return False
    return True

def span_of(data: List[Int], start: Int, end: Int) -> List[Int]:
    var out = List[Int]()
    for i in start..end:
        out.append(data[i])
    return out

def empty_bits() -> List[Bool]:
    var bits = List[Bool]()
    for _i in 0..256:
        bits.append(False)
    return bits

# Index into \d \D \w \W \s \S, or -1 for any other escape letter
def shorthand_index(e: Int) -> Int:
    if e == ch("d"):
        return 0
    if e == ch("D"):
        return 1
    if e == ch("w"):
        return 2
    if e == ch("W"):
        return 3
    if e == ch("s"):
        return 4
    if e == ch("S"):
        return 5

    return -1

def shorthand_bits(which: Int) -> List[Bool]:
    var bits = empty_bits()
    let family = which / 2
    let negated = which % 2 == 1

    for c in 0..256:
        var on = False

        if family == 0:
            on = is_digit(c)
        elif family == 1:
            on = is_word(c)
        else:
            on = c == 32 or (c >= 9 and c <= 13)

        bits[c] = on != negated

    return bits

type Problem:
    text: String

impl Error for Problem:
    def message() -> String:
        return self.text.clone()

type Node:
    case Chars(bits: List[Bool])
    case Concat(items: List[Node])
    case Choice(branches: List[Node])
    case Repeat(body: Node, low: Int, high: Int, lazy: Bool)
    case Capture(index: Int, body: Node)
    case Backref(index: Int, name: List[Int], icase: Bool)
    case Look(body: Node, negate: Bool)
    case Anchor(kind: Int)

def repeatable(n: Node) -> Bool:
    match n:
        case Anchor(_kind):
            return False
        case Look(_body, _negate):
            return False
        case _:
            return True

type Parser:
    pat: List[Int]
    pos: Int
    groups: Int
    names: List[List[Int]]
    refs: List[Int]
    ref_names: List[List[Int]]
    icase: Bool
    multiline: Bool
    dotall: Bool

impl Parser:
    def cur() -> Int:
        return self.byte_at(self.pos)

    def byte_at(i: Int) -> Int:
        if i < self.pat.length():
            return self.pat[i]

        return -1

    def single(c: Int) -> List[Bool]:
        var bits = empty_bits()
        bits[c] = True
        if self.icase:
            bits[other_case(c)] = True
        return bits

    def dot_bits() -> List[Bool]:
        var bits = empty_bits()
        for c in 0..256:
            bits[c] = self.dotall or c != NL
        return bits

    # Length of a {n}, {n,} or {n,m} token at pos, or 0 when the brace does not form one
    def brace_length() -> Int:
        if self.cur() != LBRACE:
            return 0

        var i = self.pos + 1
        let digits_start = i
        while is_digit(self.byte_at(i)):
            i += 1
        if i == digits_start:
            return 0
        if self.byte_at(i) == RBRACE:
            return i + 1 - self.pos
        if self.byte_at(i) != COMMA:
            return 0

        i += 1
        while is_digit(self.byte_at(i)):
            i += 1
        if self.byte_at(i) == RBRACE:
            return i + 1 - self.pos

        return 0

    def is_quantifier() -> Bool:
        let c = self.cur()
        return c == STAR or c == PLUS or c == QUESTION or self.brace_length() > 0

    # Reads decimal digits, saturating so that any value above 1000 stays detectable
    var def number() -> Int:
        var v = 0

        while is_digit(self.cur()):
            if v < 100000:
                v = v * 10 + self.cur() - 48
            self.pos += 1

        return v

    var def quantify(atom: Node) -> Result[Node, Problem]:
        var low = 0
        var high = -1
        let c = self.cur()

        if c == STAR:
            self.pos += 1
        elif c == PLUS:
            low = 1
            self.pos += 1
        elif c == QUESTION:
            high = 1
            self.pos += 1
        else:
            self.pos += 1
            low = self.number()
            high = low

            if self.cur() == COMMA:
                self.pos += 1
                high = -1
                if is_digit(self.cur()):
                    high = self.number()

            self.pos += 1

        var lazy = False

        if self.cur() == QUESTION:
            lazy = True
            self.pos += 1

        if low > 1000 or high > 1000 or (high >= 0 and low > high):
            return error(Problem("bad repeat"))

        return ok(Repeat(atom, low, high, lazy))

    # Reads a group or backreference name followed by `>`; err is reported on any malformed name
    var def name(err: String) -> Result[List[Int], Problem]:
        if not (is_alpha(self.cur()) or self.cur() == 95):
            return error(Problem(err))

        let start = self.pos
        while is_word(self.cur()):
            self.pos += 1

        var nm = List[Int]()
        for i in start..self.pos:
            nm.append(self.pat[i])
        if self.cur() != GT:
            return error(Problem(err))

        self.pos += 1
        return ok(nm)

    var def char_escape(e: Int) -> Result[Int, Problem]:
        if e == ch("n"):
            return ok(NL)
        if e == ch("t"):
            return ok(TAB)
        if e == ch("r"):
            return ok(CR)

        if e == ch("x"):
            let hi = hex_value(self.cur())
            let lo = hex_value(self.byte_at(self.pos + 1))
            if hi < 0 or lo < 0:
                return error(Problem("bad escape"))

            self.pos += 2
            return ok(hi * 16 + lo)

        if e >= 0 and e < 128 and not is_alnum(e):
            return ok(e)

        return error(Problem("bad escape"))

    var def escape() -> Result[Node, Problem]:
        if self.pos >= self.pat.length():
            return error(Problem("bad escape"))

        let e = self.cur()
        self.pos += 1

        let i = shorthand_index(e)
        if i >= 0:
            return ok(Chars(shorthand_bits(i)))
        if e == ch("b"):
            return ok(Anchor(WORDB))
        if e == ch("B"):
            return ok(Anchor(NOTWORDB))

        if e >= ch("1") and e <= ch("9"):
            self.refs.append(e - 48)
            return ok(Backref(e - 48, List[Int](), self.icase))

        if e == ch("k"):
            if self.cur() != LT:
                return error(Problem("bad escape"))

            self.pos += 1

            let nm = try self.name("bad escape")
            self.ref_names.append(nm.clone())
            return ok(Backref(0, nm, self.icase))

        let c = try self.char_escape(e)
        return ok(Chars(self.single(c)))

    # One class member: a byte, or SHORT_BASE + index for a shorthand class
    var def class_member() -> Result[Int, Problem]:
        let c = self.cur()
        self.pos += 1
        if c != BACKSLASH:
            return ok(c)
        if self.pos >= self.pat.length():
            return error(Problem("bad escape"))

        let e = self.cur()
        self.pos += 1

        let i = shorthand_index(e)
        if i >= 0:
            return ok(SHORT_BASE + i)

        return self.char_escape(e)

    # True when a range dash follows the current member (and is not the closing bracket's neighbour)
    def dash_follows() -> Bool:
        return (
            self.cur() == DASH
            and self.byte_at(self.pos + 1) != -1
            and self.byte_at(self.pos + 1) != RBRACKET
        )

    var def class_set() -> Result[Node, Problem]:
        var negate = False

        if self.cur() == CARET:
            negate = True
            self.pos += 1

        var bits = empty_bits()
        var first = True
        var closed = False

        while self.pos < self.pat.length():
            if self.cur() == RBRACKET and not first:
                self.pos += 1
                closed = True
                break

            let a = try self.class_member()

            if a >= SHORT_BASE:
                let extra = shorthand_bits(a - SHORT_BASE)
                for x in 0..256:
                    if extra[x]:
                        bits[x] = True
                if self.dash_follows():
                    return error(Problem("bad range"))
            elif self.dash_follows():
                self.pos += 1

                let b = try self.class_member()
                if b >= SHORT_BASE or b < a:
                    return error(Problem("bad range"))

                for x in a..b + 1:
                    bits[x] = True
            else:
                bits[a] = True

            first = False

        if not closed:
            return error(Problem("unterminated class"))

        if self.icase:
            for x in 65..91:
                if bits[x] or bits[x + 32]:
                    bits[x] = True
                    bits[x + 32] = True

        if negate:
            for x in 0..256:
                bits[x] = not bits[x]
        return ok(Chars(bits))

    # Parses the body of a group up to and including its closing parenthesis
    var def group_body() -> Result[Node, Problem]:
        let body = try self.alt()
        if self.cur() != RPAREN:
            return error(Problem("unmatched ("))

        self.pos += 1
        return ok(body)

    var def group() -> Result[Node, Problem]:
        if self.cur() == QUESTION:
            let k = self.byte_at(self.pos + 1)

            if k == ch(":"):
                self.pos += 2
                return self.group_body()

            if k == ch("=") or k == ch("!"):
                self.pos += 2

                let body = try self.group_body()
                return ok(Look(body, k == ch("!")))

            if k == LT:
                let op = self.byte_at(self.pos + 2)
                if op == ch("=") or op == ch("!"):
                    return error(Problem("bad group"))

                self.pos += 2

                let nm = try self.name("bad group")
                for other in self.names:
                    if same(other, nm):
                        return error(Problem("duplicate group name"))
                self.groups += 1

                let g = self.groups
                self.names.append(nm)

                let body = try self.group_body()
                return ok(Capture(g, body))

            return error(Problem("bad group"))

        self.groups += 1

        let g = self.groups
        self.names.append(List[Int]())

        let body = try self.group_body()
        return ok(Capture(g, body))

    var def atom() -> Result[Node, Problem]:
        let c = self.cur()
        self.pos += 1
        if c == LPAREN:
            return self.group()
        if c == LBRACKET:
            return self.class_set()
        if c == DOT:
            return ok(Chars(self.dot_bits()))
        if c == CARET:
            return ok(Anchor(MBOL if self.multiline else BOL))
        if c == DOLLAR:
            return ok(Anchor(MEOL if self.multiline else EOL))
        if c == BACKSLASH:
            return self.escape()

        return ok(Chars(self.single(c)))

    var def seq() -> Result[Node, Problem]:
        var items = List[Node]()

        while (
            self.pos < self.pat.length()
            and self.cur() != BAR
            and self.cur() != RPAREN
        ):
            let c = self.cur()
            if c == STAR or c == PLUS or c == QUESTION:
                return error(Problem("nothing to repeat"))

            var atom = try self.atom()
            var quantified = False

            while self.is_quantifier():
                if quantified or not repeatable(atom):
                    return error(Problem("nothing to repeat"))

                atom = try self.quantify(atom)
                quantified = True

            items.append(atom)

        return ok(Concat(items))

    var def alt() -> Result[Node, Problem]:
        var branches = List[Node]()
        branches.append(try self.seq())

        while self.cur() == BAR:
            self.pos += 1
            branches.append(try self.seq())

        return ok(Choice(branches))

type Regex:
    root: Node
    groups: Int
    names: List[List[Int]]

def compile(pat: List[Int]) -> Result[Regex, Problem]:
    var names = List[List[Int]]()
    names.append(List[Int]())

    var p = Parser(
        pat: pat.clone(), pos: 0, groups: 0, names: names, refs: List[Int](),
        ref_names: List[List[Int]](), icase: False, multiline: False, dotall: False
    )

    if p.byte_at(0) == LPAREN and p.byte_at(1) == QUESTION and is_flag(p.byte_at(2)):
        p.pos = 2

        while is_flag(p.cur()):
            if p.cur() == ch("i"):
                p.icase = True
            elif p.cur() == ch("m"):
                p.multiline = True
            else:
                p.dotall = True

            p.pos += 1

        if p.cur() != RPAREN:
            return error(Problem("bad group"))

        p.pos += 1

    let root = try p.alt()
    if p.pos < pat.length():
        return error(Problem("unmatched )"))

    for n in p.refs:
        if n > p.groups:
            return error(Problem("bad backreference"))
    for nm in p.ref_names:
        if group_of(p.names, nm) < 0:
            return error(Problem("bad backreference"))
    return ok(Regex(root: root, groups: p.groups, names: p.names.clone()))

def group_of(names: List[List[Int]], nm: List[Int]) -> Int:
    if nm.length() == 0:
        return -1

    for g in 1..names.length():
        if same(names[g], nm):
            return g
    return -1

# ---- matching ----

type Subject:
    text: List[Int]
    names: List[List[Int]]

def anchor_ok(kind: Int, text: List[Int], pos: Int) -> Bool:
    let n = text.length()
    if kind == BOL:
        return pos == 0
    if kind == EOL:
        return pos == n
    if kind == MBOL:
        return pos == 0 or text[pos - 1] == NL
    if kind == MEOL:
        return pos == n or text[pos] == NL

    let left = pos > 0 and is_word(text[pos - 1])
    let right = pos < n and is_word(text[pos])
    if kind == WORDB:
        return left != right

    return left == right

def same_byte(a: Int, b: Int, icase: Bool) -> Bool:
    if icase:
        return fold(a) == fold(b)

    return a == b

# Continuation-passing backtracking: k receives the end position and the captures so far
# and returns the final captures on overall success, or none to make the caller backtrack.
def run(
    n: Node,
    sub: Subject,
    pos: Int,
    caps: List[Int],
    k: Callable[[Int, List[Int]], Optional[List[Int]]]
) -> Optional[List[Int]]:
    match n:
        case Chars(bits):
            if pos < sub.text.length() and bits[sub.text[pos]]:
                return k(pos + 1, caps)

            return none
        case Concat(items):
            return run_from(items, 0, sub, pos, caps, k)
        case Choice(branches):
            for branch in branches:
                if let r = run(branch, sub, pos, caps, k):
                    return r
            return none
        case Repeat(body, low, high, lazy):
            return step(body, low, high, lazy, 0, sub, pos, caps, k)
        case Capture(index, body):
            return run(
                body, sub, pos, caps, lambda p, c: k(p, span_set(c, index, pos, p))
            )
        case Backref(index, name, icase):
            var g = index
            if name.length() > 0:
                g = group_of(sub.names, name)

            let st = caps[2 * g]
            let en = caps[2 * g + 1]
            if st < 0 or en < 0:
                return none

            let width = en - st
            if pos + width > sub.text.length():
                return none

            for i in 0..width:
                if not same_byte(sub.text[st + i], sub.text[pos + i], icase):
                    return none
            return k(pos + width, caps)
        case Look(body, negate):
            let r = run(body, sub, pos, caps, lambda _p, c: c)

            if negate:
                if let _r = r:
                    return none

                return k(pos, caps)

            if let c = r:
                return k(pos, c)

            return none
        case Anchor(kind):
            if anchor_ok(kind, sub.text, pos):
                return k(pos, caps)

            return none

def run_from(
    items: List[Node],
    i: Int,
    sub: Subject,
    pos: Int,
    caps: List[Int],
    k: Callable[[Int, List[Int]], Optional[List[Int]]]
) -> Optional[List[Int]]:
    if i == items.length():
        return k(pos, caps)

    return run(
        items[i], sub, pos, caps, lambda p, c: run_from(items, i + 1, sub, p, c, k)
    )

def span_set(caps: List[Int], g: Int, start: Int, end: Int) -> List[Int]:
    var out = caps.clone()
    out[2 * g] = start
    out[2 * g + 1] = end
    return out

# Repetition: `count` iterations are done and the next one would start at pos
def step(
    body: Node,
    low: Int,
    high: Int,
    lazy: Bool,
    count: Int,
    sub: Subject,
    pos: Int,
    caps: List[Int],
    k: Callable[[Int, List[Int]], Optional[List[Int]]]
) -> Optional[List[Int]]:
    if count < low:
        return iterate(body, low, high, lazy, count, sub, pos, caps, k)

    if lazy:
        if let r = k(pos, caps):
            return r

        return iterate(body, low, high, lazy, count, sub, pos, caps, k)

    if let r = iterate(body, low, high, lazy, count, sub, pos, caps, k):
        return r

    return k(pos, caps)

def iterate(
    body: Node,
    low: Int,
    high: Int,
    lazy: Bool,
    count: Int,
    sub: Subject,
    pos: Int,
    caps: List[Int],
    k: Callable[[Int, List[Int]], Optional[List[Int]]]
) -> Optional[List[Int]]:
    if high >= 0 and count >= high:
        return none

    return run(
        body, sub, pos, caps, lambda p,
        c: after_iteration(body, low, high, lazy, count + 1, pos, sub, p, c, k)
    )

def after_iteration(
    body: Node,
    low: Int,
    high: Int,
    lazy: Bool,
    count: Int,
    start: Int,
    sub: Subject,
    p: Int,
    c: List[Int],
    k: Callable[[Int, List[Int]], Optional[List[Int]]]
) -> Optional[List[Int]]:
    # Once the minimum is reached, an iteration that consumed nothing ends the loop
    if count >= low and p == start:
        return k(p, c)

    return step(body, low, high, lazy, count, sub, p, c, k)

# Tries one match starting exactly at start; full requires it to end at the end of the subject
def try_at(re: Regex, text: List[Int], start: Int, full: Bool) -> Optional[List[Int]]:
    var caps = List[Int]()
    for _i in 0..2 * (re.groups + 1):
        caps.append(-1)

    let sub = Subject(text: text.clone(), names: re.names.clone())
    let end = text.length()
    return run(re.root, sub, start, caps, lambda p, c: accept(p, c, start, end, full))

def accept(
    p: Int,
    c: List[Int],
    start: Int,
    end: Int,
    full: Bool
) -> Optional[List[Int]]:
    if full and p != end:
        return none

    return span_set(c, 0, start, p)

def search(re: Regex, text: List[Int], from_start: Int) -> Optional[List[Int]]:
    var start = from_start

    while start <= text.length():
        if let caps = try_at(re, text.clone(), start, False):
            return caps

        start += 1

    return none

def find_all(re: Regex, text: List[Int]) -> List[List[Int]]:
    var found = List[List[Int]]()
    var at = 0

    while at <= text.length():
        if let caps = search(re, text.clone(), at):
            found.append(caps.clone())

            at = caps[1] if caps[1] > caps[0] else caps[1] + 1
        else:
            break

    return found

# ---- output ----

def quoted(data: List[Int]) -> String:
    var out = List[Int]()
    out.append(QUOTE)

    for c in data:
        if c == QUOTE or c == BACKSLASH:
            out.append(BACKSLASH)
            out.append(c)
        elif c == NL:
            out.append(BACKSLASH)
            out.append(ch("n"))
        elif c == TAB:
            out.append(BACKSLASH)
            out.append(ch("t"))
        elif c == CR:
            out.append(BACKSLASH)
            out.append(ch("r"))
        elif c < 32 or c > 126:
            out.append(BACKSLASH)
            out.append(ch("x"))
            out.append(hex_digit(c / 16))
            out.append(hex_digit(c % 16))
        else:
            out.append(c)

    out.append(QUOTE)
    return text_of(out)

def describe(re: Regex, text: List[Int], caps: List[Int]) -> List[String]:
    var lines = List[String]()

    for g in 0..re.groups + 1:
        var label = f"{g}"
        let nm = re.names[g]
        if nm.length() > 0:
            label = f"{g} ({text_of(nm)})"

        if caps[2 * g] >= 0:
            let st = caps[2 * g]
            let en = caps[2 * g + 1]
            lines.append(f"{label}: {st}..{en} {quoted(span_of(text, st, en))}")
        else:
            lines.append(f"{label}: unset")

    return lines

def find_all_lines(text: List[Int], matches: List[List[Int]]) -> List[String]:
    var lines = List[String]()
    for caps in matches:
        lines.append(f"{caps[0]}..{caps[1]} {quoted(span_of(text, caps[0], caps[1]))}")
    lines.append(f"({matches.length()} matches)")
    return lines

def split_lines(text: List[Int], matches: List[List[Int]]) -> List[String]:
    var lines = List[String]()
    var prev = 0
    var count = 0

    for caps in matches:
        if caps[1] > caps[0]:
            lines.append(quoted(span_of(text, prev, caps[0])))
            prev = caps[1]
            count += 1

    lines.append(quoted(span_of(text, prev, text.length())))
    count += 1
    lines.append(f"({count} pieces)")
    return lines

# Expands $0-$9, $$, ${name} against one match
def expand(
    repl: List[Int],
    re: Regex,
    text: List[Int],
    caps: List[Int]
) -> Result[List[Int], Problem]:
    var out = List[Int]()
    var i = 0

    while i < repl.length():
        let c = repl[i]

        if c != DOLLAR:
            out.append(c)
            i += 1
            continue

        let d = repl[i + 1] if i + 1 < repl.length() else - 1

        if d == DOLLAR:
            out.append(DOLLAR)
            i += 2
        elif is_digit(d):
            let g = d - 48
            if g > re.groups:
                return error(Problem("bad replacement"))

            if caps[2 * g] >= 0:
                for x in span_of(text, caps[2 * g], caps[2 * g + 1]):
                    out.append(x)
            i += 2
        elif d == LBRACE:
            var j = i + 2
            while j < repl.length() and repl[j] != RBRACE:
                j += 1
            if j >= repl.length():
                return error(Problem("bad replacement"))

            let g = group_of(re.names, span_of(repl, i + 2, j))
            if g < 0:
                return error(Problem("bad replacement"))

            if caps[2 * g] >= 0:
                for x in span_of(text, caps[2 * g], caps[2 * g + 1]):
                    out.append(x)
            i = j + 1
        else:
            out.append(DOLLAR)
            i += 1

    return ok(out)

def replace_all(
    re: Regex,
    text: List[Int],
    repl: List[Int]
) -> Result[List[Int], Problem]:
    var out = List[Int]()
    var prev = 0

    for caps in find_all(re, text.clone()):
        for x in span_of(text, prev, caps[0]):
            out.append(x)
        for x in try expand(repl, re, text, caps):
            out.append(x)
        prev = caps[1]

    for x in span_of(text, prev, text.length()):
        out.append(x)
    return ok(out)

# ---- command driver ----

def unescape(s: List[Int]) -> Result[List[Int], Problem]:
    var out = List[Int]()
    var i = 0

    while i < s.length():
        let c = s[i]

        if c != BACKSLASH:
            out.append(c)
            i += 1
            continue

        if i + 1 >= s.length():
            return error(Problem("bad command"))

        let e = s[i + 1]

        if e == ch("n"):
            out.append(NL)
            i += 2
        elif e == ch("t"):
            out.append(TAB)
            i += 2
        elif e == BACKSLASH:
            out.append(BACKSLASH)
            i += 2
        elif e == ch("x"):
            if i + 3 >= s.length():
                return error(Problem("bad command"))

            let hi = hex_value(s[i + 2])
            let lo = hex_value(s[i + 3])
            if hi < 0 or lo < 0:
                return error(Problem("bad command"))

            out.append(hi * 16 + lo)
            i += 4
        else:
            return error(Problem("bad command"))

    return ok(out)

def split_tab(line: List[Int]) -> List[List[Int]]:
    var fields = List[List[Int]]()
    var cur = List[Int]()

    for c in line:
        if c == TAB:
            fields.append(cur)
            cur = List[Int]()
        else:
            cur.append(c)

    fields.append(cur)
    return fields

def execute(line: List[Int]) -> Result[List[String], Problem]:
    let fields = split_tab(line)
    let commands = ["test", "match", "full", "find-all", "split", "replace"]
    var kind = -1
    for k in 0..commands.length():
        if same(fields[0], as_list(commands[k])):
            kind = k
    if kind < 0:
        return error(Problem("bad command"))

    let arity = 4 if kind == 5 else 3

    if fields.length() != arity:
        return error(Problem("bad command"))

    let subject = try unescape(fields[2])
    var repl = List[Int]()
    if kind == 5:
        repl = try unescape(fields[3])

    let re = try compile(fields[1].clone())

    if kind == 0:
        if search(re, subject.clone(), 0).is_some():
            return ok(["true"])

        return ok(["false"])

    if kind == 1:
        if let caps = search(re, subject.clone(), 0):
            return ok(describe(re, subject, caps))

        return ok(["no match"])

    if kind == 2:
        if let caps = try_at(re, subject.clone(), 0, True):
            return ok(describe(re, subject, caps))

        return ok(["no match"])

    if kind == 3:
        return ok(find_all_lines(subject, find_all(re, subject)))
    if kind == 4:
        return ok(split_lines(subject, find_all(re, subject)))

    let replaced = try replace_all(re, subject.clone(), repl)
    return ok([quoted(replaced)])

def command(line: List[Int]) -> List[String]:
    if line.length() == 0:
        return List[String]()

    let result = execute(line)
    if result.is_error():
        return [f"error: {result.err().text}"]

    return result.get().clone()

export def main() -> Int:
    let data = read_all(stdin()).get()
    var out = List[String]()
    var line = List[Int]()

    for i in 0..data.length():
        let b = data.get(i).to_int()

        if b == NL:
            for s in command(line):
                out.append(s)
            line = List[Int]()
        else:
            line.append(b)

    for s in command(line):
        out.append(s)
    if out.length() > 0:
        stdout().write(out.join("\n") + "\n").get()
    return 0
