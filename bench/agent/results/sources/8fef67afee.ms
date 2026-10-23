import {stdout, stdin, read_all} from "@std/io.ms"
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import {range} from "@std/collections.ms"

# A parsed pattern node. Children are referenced by index into Regex.nodes.
type Node:
    case ByteSet(members: List[Bool])
    case Concat(items: List[Int])
    case Choice(options: List[Int])
    case Capture(index: Int, body: Int)
    case Repeat(body: Int, lo: Int, hi: Int, lazy: Bool)
    case LineStart(multi: Bool)
    case LineEnd(multi: Bool)
    case WordEdge(want: Bool)
    case Look(body: Int, negate: Bool)
    case BackRef(index: Int, name: Bytes)

# A compiled pattern. names[i] is the name of group i + 1, or empty.
type Regex:
    nodes: List[Node]
    root: Int
    names: List[Bytes]
    icase: Bool

type PatError:
    msg: String

impl Error for PatError:
    fn message() String:
        return self.msg

type Parser:
    pat: Bytes
    pos: Int
    nodes: List[Node]
    names: List[Bytes]
    icase: Bool
    multi: Bool
    dotall: Bool

type Atom:
    id: Int
    quant: Bool

type Quant:
    lo: Int
    hi: Int
    stop: Int

type Member:
    is_set: Bool
    byte: Int
    letter: Int

type Ctx:
    re: Regex
    text: Bytes

# ---------- byte helpers ----------
fn ch(s: String) Int:
    return s.to_bytes().get(0)

fn is_digit(b: Int) Bool:
    return b >= 48 and b <= 57

fn is_alpha(b: Int) Bool:
    return (b >= 97 and b <= 122) or (b >= 65 and b <= 90)

fn is_word(b: Int) Bool:
    return is_alpha(b) or is_digit(b) or b == 95

fn is_space(b: Int) Bool:
    return b == 32 or (b >= 9 and b <= 13)

# ASCII punctuation, control and other non-alphanumeric bytes below 128.
fn is_ascii_punct(b: Int) Bool:
    return b >= 0 and b < 128 and not is_alpha(b) and not is_digit(b)

fn hex_value(b: Int) Int:
    if b >= 48 and b <= 57:
        return b - 48
    if b >= 97 and b <= 102:
        return b - 87
    if b >= 65 and b <= 70:
        return b - 55

    return -1

# Byte at index, or -1 when outside the bytes.
fn byte_or(data: Bytes, at: Int) Int:
    if at >= 0 and at < data.length():
        return data.get(at)

    return -1

# The other ASCII case of a letter; other bytes are unchanged.
fn other_case(b: Int) Int:
    if b >= 97 and b <= 122:
        return b - 32
    if b >= 65 and b <= 90:
        return b + 32

    return b

fn lower(b: Int) Int:
    if b >= 65 and b <= 90:
        return b + 32

    return b

# Whether byte b is in the shorthand class named by letter (d D w W s S).
fn shorthand_test(letter: Int, b: Int) Bool:
    let base = lower(letter)
    var hit = false

    if base == ch("d"):
        hit = is_digit(b)
    else if base == ch("w"):
        hit = is_word(b)
    else:
        hit = is_space(b)

    if base != letter:
        return not hit

    return hit

fn is_shorthand(letter: Int) Bool:
    return (
        letter == ch("d")
        or letter == ch("D")
        or letter == ch("w")
        or letter == ch("W")
        or letter == ch("s")
        or letter == ch("S")
    )

fn empty_set() List[Bool]:
    var set: List[Bool] = []
    for i in range(0, 256):
        set.append(false)
    return set

fn single_set(b: Int, icase: Bool) List[Bool]:
    var set = empty_set()
    set.set(b, true)
    if icase:
        set.set(other_case(b), true)
    return set

fn dot_set(dotall: Bool) List[Bool]:
    var set = empty_set()
    for i in range(0, 256):
        set.set(i, dotall or i != 10)
    return set

# Adds one class member (byte or shorthand) to a set.
fn add_member(var set: List[Bool], m: Member) Unit:
    if m.is_set:
        for i in range(0, 256):
            if shorthand_test(m.letter, i):
                set.set(i, true)
    else:
        set.set(m.byte, true)

# ---------- parsing ----------
fn peek(ps: Parser, off: Int) Int:
    return byte_or(ps.pat, ps.pos + off)

fn add(var ps: Parser, node: Node) Int:
    ps.nodes.append(node)
    return ps.nodes.length() - 1

fn at_close(ps: Parser) Bool:
    return peek(ps, 0) == ch(")")

fn grow(v: Int, d: Int) Int:
    let n = v * 10 + d
    if n > 100000:
        return 100000

    return n

# Reads a quantifier starting at `at`: *, +, ?, {n}, {n,}, {n,m}. None if there is none.
fn read_quant(pat: Bytes, at: Int) Optional[Quant]:
    if at >= pat.length():
        return none

    let c = pat.get(at)
    if c == ch("*"):
        return some(Quant(lo: 0, hi: -1, stop: at + 1))
    if c == ch("+"):
        return some(Quant(lo: 1, hi: -1, stop: at + 1))
    if c == ch("?"):
        return some(Quant(lo: 0, hi: 1, stop: at + 1))
    if c != ch("\{"):
        return none

    var i = at + 1
    let lo_start = i
    var lo = 0

    while i < pat.length() and is_digit(pat.get(i)):
        lo = grow(lo, pat.get(i) - 48)
        i += 1

    if i == lo_start:
        return none

    var hi = lo

    if i < pat.length() and pat.get(i) == ch(","):
        i += 1

        let hi_start = i
        var h = 0

        while i < pat.length() and is_digit(pat.get(i)):
            h = grow(h, pat.get(i) - 48)
            i += 1

        hi = -1
        if i > hi_start:
            hi = h

    if i < pat.length() and pat.get(i) == ch("\}"):
        return some(Quant(lo: lo, hi: hi, stop: i + 1))

    return none

fn parse_alt(var ps: Parser) Result[Int, PatError]:
    var options: List[Int] = []
    let first = try parse_seq(var ps)
    options.append(first)

    while peek(ps, 0) == ch("|"):
        ps.pos += 1

        let next = try parse_seq(var ps)
        options.append(next)

    if options.length() == 1:
        return ok(first)

    return ok(add(var ps, Choice(options: options)))

fn parse_seq(var ps: Parser) Result[Int, PatError]:
    var items: List[Int] = []
    var can_repeat = false

    while (
        ps.pos < ps.pat.length()
        and peek(ps, 0) != ch("|")
        and peek(ps, 0) != ch(")")
    ):
        let q = read_quant(ps.pat, ps.pos)

        if q.is_some() and not (peek(ps, 0) == ch("\{") and items.is_empty()):
            if not can_repeat:
                return error(PatError(msg: "nothing to repeat"))

            let quant = q.get()
            if (
                quant.lo > 1000
                or quant.hi > 1000
                or (quant.hi >= 0 and quant.lo > quant.hi)
            ):
                return error(PatError(msg: "bad repeat"))

            ps.pos = quant.stop

            var lazy = false

            if peek(ps, 0) == ch("?"):
                lazy = true
                ps.pos += 1

            let last = items.length() - 1
            let rep = Repeat(
                body: items.get(last), lo: quant.lo, hi: quant.hi, lazy: lazy
            )
            items.set(last, add(var ps, rep))
            can_repeat = false
        else:
            let atom = try parse_atom(var ps)
            items.append(atom.id)
            can_repeat = atom.quant

    if items.length() == 1:
        return ok(items.get(0))

    return ok(add(var ps, Concat(items: items)))

fn parse_atom(var ps: Parser) Result[Atom, PatError]:
    let c = ps.pat.get(ps.pos)
    if c == ch("("):
        return parse_group(var ps)
    if c == ch("["):
        return parse_class(var ps)

    ps.pos += 1
    if c == ch("\\"):
        return parse_escape(var ps)

    if c == ch("."):
        let dot = ByteSet(members: dot_set(ps.dotall))
        return ok(Atom(id: add(var ps, dot), quant: true))

    if c == ch("^"):
        let start = LineStart(multi: ps.multi)
        return ok(Atom(id: add(var ps, start), quant: false))

    if c == ch("$"):
        let end = LineEnd(multi: ps.multi)
        return ok(Atom(id: add(var ps, end), quant: false))

    let lit = ByteSet(members: single_set(c, ps.icase))
    return ok(Atom(id: add(var ps, lit), quant: true))

# Parses after '(' has been consumed.
fn parse_group(var ps: Parser) Result[Atom, PatError]:
    ps.pos += 1
    if peek(ps, 0) != ch("?"):
        return capture_group(var ps, "".to_bytes())

    let kind = peek(ps, 1)

    if kind == ch(":"):
        ps.pos += 2

        let body = try parse_alt(var ps)
        if not at_close(ps):
            return error(PatError(msg: "unmatched ("))

        ps.pos += 1
        return ok(Atom(id: body, quant: true))

    if kind == ch("=") or kind == ch("!"):
        ps.pos += 2

        let body = try parse_alt(var ps)
        if not at_close(ps):
            return error(PatError(msg: "unmatched ("))

        ps.pos += 1

        let look = Look(body: body, negate: kind == ch("!"))
        return ok(Atom(id: add(var ps, look), quant: false))

    if kind == ch("<"):
        let start = ps.pos + 2
        var e = start
        while e < ps.pat.length() and is_word(ps.pat.get(e)):
            e += 1
        if (
            e >= ps.pat.length()
            or ps.pat.get(e) != ch(">")
            or e == start
            or is_digit(ps.pat.get(start))
        ):
            return error(PatError(msg: "bad group"))

        let name = ps.pat.slice(start, e).get()
        if find_name(ps.names, name) > 0:
            return error(PatError(msg: "duplicate group name"))

        ps.pos = e + 1
        return capture_group(var ps, name)

    return error(PatError(msg: "bad group"))

fn find_name(names: List[Bytes], name: Bytes) Int:
    for i in range(0, names.length()):
        if names.get(i) == name:
            return i + 1
    return 0

# Parses a capturing group body and its closing parenthesis.
fn capture_group(var ps: Parser, name: Bytes) Result[Atom, PatError]:
    ps.names.append(name)

    let index = ps.names.length()
    let body = try parse_alt(var ps)
    if not at_close(ps):
        return error(PatError(msg: "unmatched ("))

    ps.pos += 1

    let cap = Capture(index: index, body: body)
    return ok(Atom(id: add(var ps, cap), quant: true))

# Decodes the escape letter e (already consumed) as a single byte, or -1 when it is not one.
fn escape_byte(var ps: Parser, e: Int) Int:
    if e == ch("n"):
        return 10
    if e == ch("t"):
        return 9
    if e == ch("r"):
        return 13

    if e == ch("x"):
        let hi = hex_value(peek(ps, 0))
        let lo = hex_value(peek(ps, 1))
        if hi < 0 or lo < 0:
            return -1

        ps.pos += 2
        return hi * 16 + lo

    if is_ascii_punct(e):
        return e

    return -1

# Parses an escape outside a class; the backslash is already consumed.
fn parse_escape(var ps: Parser) Result[Atom, PatError]:
    if ps.pos >= ps.pat.length():
        return error(PatError(msg: "bad escape"))

    let e = ps.pat.get(ps.pos)
    ps.pos += 1

    if is_shorthand(e):
        let set = ByteSet(members: shorthand_set(e))
        return ok(Atom(id: add(var ps, set), quant: true))

    if e == ch("b") or e == ch("B"):
        let edge = WordEdge(want: e == ch("b"))
        return ok(Atom(id: add(var ps, edge), quant: false))

    if e >= 49 and e <= 57:
        let backref = BackRef(index: e - 48, name: "".to_bytes())
        return ok(Atom(id: add(var ps, backref), quant: true))

    if e == ch("k"):
        if peek(ps, 0) != ch("<"):
            return error(PatError(msg: "bad escape"))

        let start = ps.pos + 1
        var stop = start
        while stop < ps.pat.length() and is_word(ps.pat.get(stop)):
            stop += 1
        if (
            stop >= ps.pat.length()
            or ps.pat.get(stop) != ch(">")
            or stop == start
            or is_digit(ps.pat.get(start))
        ):
            return error(PatError(msg: "bad escape"))

        let name = ps.pat.slice(start, stop).get()
        ps.pos = stop + 1

        let backref = BackRef(index: 0, name: name)
        return ok(Atom(id: add(var ps, backref), quant: true))

    let b = escape_byte(var ps, e)
    if b < 0:
        return error(PatError(msg: "bad escape"))

    let lit = ByteSet(members: single_set(b, ps.icase))
    return ok(Atom(id: add(var ps, lit), quant: true))

fn shorthand_set(letter: Int) List[Bool]:
    var set = empty_set()
    for i in range(0, 256):
        set.set(i, shorthand_test(letter, i))
    return set

# One class member: a single byte, or a shorthand class.
fn class_member(var ps: Parser) Result[Member, PatError]:
    let c = ps.pat.get(ps.pos)

    if c != ch("\\"):
        ps.pos += 1
        return ok(Member(is_set: false, byte: c, letter: 0))

    ps.pos += 1
    if ps.pos >= ps.pat.length():
        return error(PatError(msg: "bad escape"))

    let e = ps.pat.get(ps.pos)
    ps.pos += 1
    if is_shorthand(e):
        return ok(Member(is_set: true, byte: 0, letter: e))

    let b = escape_byte(var ps, e)
    if b < 0:
        return error(PatError(msg: "bad escape"))

    return ok(Member(is_set: false, byte: b, letter: 0))

# Parses a character class; the '[' is still at ps.pos.
fn parse_class(var ps: Parser) Result[Atom, PatError]:
    ps.pos += 1

    var negate = false

    if peek(ps, 0) == ch("^"):
        negate = true
        ps.pos += 1

    var set = empty_set()
    var first = true

    while true:
        if ps.pos >= ps.pat.length():
            return error(PatError(msg: "unterminated class"))

        if peek(ps, 0) == ch("]") and not first:
            ps.pos += 1
            break

        first = false

        let m1 = try class_member(var ps)

        if peek(ps, 0) == ch("-") and peek(ps, 1) != -1 and peek(ps, 1) != ch("]"):
            if m1.is_set:
                return error(PatError(msg: "bad range"))

            ps.pos += 1

            let m2 = try class_member(var ps)
            if m2.is_set or m2.byte < m1.byte:
                return error(PatError(msg: "bad range"))

            for b in range(m1.byte, m2.byte + 1):
                set.set(b, true)
        else:
            add_member(var set, m1)

    if ps.icase:
        for b in range(0, 256):
            if set.get(b) and is_alpha(b):
                set.set(other_case(b), true)
    if negate:
        for b in range(0, 256):
            set.set(b, not set.get(b))

    let cls = ByteSet(members: set)
    return ok(Atom(id: add(var ps, cls), quant: true))

# Resolves named back references and checks numbered ones, once the whole pattern has parsed.
fn resolve_refs(var ps: Parser) Result[Unit, PatError]:
    for i in range(0, ps.nodes.length()):
        let node = ps.nodes.get(i).clone()

        match node:
            BackRef(index, name):
                if name.is_empty():
                    if index > ps.names.length():
                        return error(PatError(msg: "bad backreference"))
                else:
                    let g = find_name(ps.names.clone(), name.clone())
                    if g == 0:
                        return error(PatError(msg: "bad backreference"))

                    ps.nodes.set(i, BackRef(index: g, name: "".to_bytes()))
            _:
                ps.nodes.set(i, node)

    return ok(unit)

fn compile(pat: Bytes) Result[Regex, PatError]:
    var ps = Parser(
        pat: pat.clone(), pos: 0, nodes: [], names: [], icase: false, multi: false,
        dotall: false
    )

    # Leading flags such as (?ims) apply to the whole pattern.
    if (
        pat.length() >= 3
        and pat.get(0) == ch("(")
        and pat.get(1) == ch("?")
        and (
            pat.get(2) == ch("i")
            or pat.get(2) == ch("m")
            or pat.get(2) == ch("s")
        )
    ):
        ps.pos = 2

        while (
            peek(ps, 0) == ch("i")
            or peek(ps, 0) == ch("m")
            or peek(ps, 0) == ch("s")
        ):
            if peek(ps, 0) == ch("i"):
                ps.icase = true
            else if peek(ps, 0) == ch("m"):
                ps.multi = true
            else:
                ps.dotall = true

            ps.pos += 1

        if peek(ps, 0) != ch(")"):
            return error(PatError(msg: "bad group"))

        ps.pos += 1

    let root = try parse_alt(var ps)
    if ps.pos < ps.pat.length():
        return error(PatError(msg: "unmatched )"))

    try resolve_refs(var ps)
    return ok(
        Regex(
            nodes: ps.nodes.clone(), root: root, names: ps.names.clone(),
            icase: ps.icase
        )
    )

# ---------- matching ----------
# Continuation-passing backtracking matcher. The context is passed to every continuation
# rather than captured, and captures are an immutable list, so backtracking restores them.
# Result: the final captures (group 0 included), or none.
fn run(
    var c: Ctx, id: Int, pos: Int, caps: List[Int],
    k: fn(var c: Ctx, p: Int, after: List[Int]) Optional[List[Int]]
) Optional[List[Int]]:
    let n = c.text.length()

    match c.re.nodes[id]:
        ByteSet(members):
            if pos < n and members.get(c.text.get(pos)):
                return k(c, pos + 1, caps)

            return none
        Concat(items):
            let list = items.clone()
            return concat_from(var c, list, 0, pos, caps, k)
        Choice(options):
            let list = options.clone()
            return choice_from(var c, list, 0, pos, caps, k)
        Capture(index, body):
            let close = fn(var c: Ctx, p: Int, after: List[Int]) Optional[List[Int]]:
                var set = after.clone()
                set.set(2 * index, pos)
                set.set(2 * index + 1, p)
                return k(c, p, set)

            return run(var c, body, pos, caps, close)
        Repeat(body, lo, hi, lazy):
            return repeat_from(var c, body, lo, hi, lazy, 0, pos, caps, k)
        LineStart(multi):
            if pos == 0 or (multi and pos > 0 and c.text.get(pos - 1) == 10):
                return k(c, pos, caps)

            return none
        LineEnd(multi):
            if pos == n or (multi and pos < n and c.text.get(pos) == 10):
                return k(c, pos, caps)

            return none
        WordEdge(want):
            let before = pos > 0 and is_word(c.text.get(pos - 1))
            let after = pos < n and is_word(c.text.get(pos))
            if (before != after) == want:
                return k(c, pos, caps)

            return none
        Look(body, negate):
            let keep = fn(var c: Ctx, p: Int, after: List[Int]) Optional[List[Int]]:
                return some(after)
            let found = run(var c, body, pos, caps, keep)

            if negate:
                if found.is_some():
                    return none

                return k(c, pos, caps)

            if found.is_none():
                return none

            return k(c, pos, found.get())
        BackRef(index, _):
            let s = caps.get(2 * index)
            if s < 0:
                return none

            let size = caps.get(2 * index + 1) - s
            if pos + size > n:
                return none

            for j in range(0, size):
                let a = c.text.get(s + j)
                let b = c.text.get(pos + j)
                if a != b and not (c.re.icase and lower(a) == lower(b)):
                    return none

            return k(c, pos + size, caps)

fn concat_from(
    var c: Ctx, items: List[Int], i: Int, pos: Int, caps: List[Int],
    k: fn(var c: Ctx, p: Int, after: List[Int]) Optional[List[Int]]
) Optional[List[Int]]:
    if i == items.length():
        return k(c, pos, caps)

    let next = fn(var c: Ctx, p: Int, after: List[Int]) Optional[List[Int]]:
        return concat_from(var c, items, i + 1, p, after, k)
    return run(var c, items.get(i), pos, caps, next)

fn choice_from(
    var c: Ctx, options: List[Int], i: Int, pos: Int, caps: List[Int],
    k: fn(var c: Ctx, p: Int, after: List[Int]) Optional[List[Int]]
) Optional[List[Int]]:
    if i == options.length():
        return none

    let found = run(var c, options.get(i), pos, caps, k)
    if found.is_some():
        return found

    return choice_from(var c, options, i + 1, pos, caps, k)

# count is the number of iterations done so far. After min, an iteration that consumes
# nothing ends the loop, so the match continues after it.
fn repeat_from(
    var c: Ctx, body: Int, lo: Int, hi: Int, lazy: Bool, count: Int, pos: Int,
    caps: List[Int], k: fn(var c: Ctx, p: Int, after: List[Int]) Optional[List[Int]]
) Optional[List[Int]]:
    if count < lo:
        let next = fn(var c: Ctx, p: Int, after: List[Int]) Optional[List[Int]]:
            return repeat_from(var c, body, lo, hi, lazy, count + 1, p, after, k)
        return run(var c, body, pos, caps, next)

    let more = hi < 0 or count < hi

    let iterate = fn(var c: Ctx, p: Int, after: List[Int]) Optional[List[Int]]:
        if p == pos:
            return k(c, p, after)

        return repeat_from(var c, body, lo, hi, lazy, count + 1, p, after, k)

    if lazy:
        let stop = k(c, pos, caps)
        if stop.is_some():
            return stop
        if more:
            return run(var c, body, pos, caps, iterate)

        return none

    if more:
        let taken = run(var c, body, pos, caps, iterate)
        if taken.is_some():
            return taken

    return k(c, pos, caps)

# Leftmost match at or after start. With full, only a match from 0 to the end counts.
fn exec(var c: Ctx, start: Int, full: Bool) Optional[List[Int]]:
    let n = c.text.length()
    var blank: List[Int] = []
    for i in range(0, 2 * (c.re.names.length() + 1)):
        blank.append(-1)

    let root = c.re.root
    var s = start

    while s <= n:
        var begin = blank.clone()
        begin.set(0, s)

        let finish = fn(var c: Ctx, p: Int, after: List[Int]) Optional[List[Int]]:
            if full and p != c.text.length():
                return none

            var done = after.clone()
            done.set(1, p)
            return some(done)

        let found = run(var c, root, s, begin, finish)
        if found.is_some() or full:
            return found

        s += 1

    return none

# Every match in find-all order: an empty match moves the search on by one byte.
fn find_all(var c: Ctx) List[List[Int]]:
    var found: List[List[Int]] = []
    var start = 0

    while start <= c.text.length():
        let m = exec(var c, start, false)
        if m.is_none():
            break

        let caps = m.get()
        found.append(caps.clone())

        if caps.get(1) == caps.get(0):
            start = caps.get(1) + 1
        else:
            start = caps.get(1)

    return found

# ---------- output ----------
fn put(var out: BytesBuilder, text: String) Unit:
    out.concat(text.to_bytes())

fn hex_digit(v: Int) Int:
    if v < 10:
        return 48 + v

    return 97 + v - 10

# Appends data[s..e) as a quoted string with the spec's escapes.
fn put_quoted(var out: BytesBuilder, data: Bytes, s: Int, e: Int) Unit:
    out.append(34)

    for i in range(s, e):
        let b = data.get(i)

        if b == 92:
            put(var out, "\\\\")
        else if b == 34:
            put(var out, "\\\"")
        else if b == 10:
            put(var out, "\\n")
        else if b == 9:
            put(var out, "\\t")
        else if b == 13:
            put(var out, "\\r")
        else if b < 32 or b > 126:
            put(var out, "\\x")
            out.append(hex_digit(b / 16))
            out.append(hex_digit(b % 16))
        else:
            out.append(b)

    out.append(34)

# "S..E "quoted"" for a span of the subject.
fn put_span(var out: BytesBuilder, text: Bytes, s: Int, e: Int) Unit:
    put(var out, "{s}..{e} ")
    put_quoted(var out, text, s, e)

fn put_captures(var out: BytesBuilder, re: Regex, text: Bytes, caps: List[Int]) Unit:
    for g in range(0, re.names.length() + 1):
        put(var out, "{g}")

        if g > 0 and not re.names.get(g - 1).is_empty():
            put(var out, " (")
            out.concat(re.names.get(g - 1))
            put(var out, ")")

        let s = caps.get(2 * g)

        if s < 0:
            put(var out, ": unset\n")
        else:
            put(var out, ": ")
            put_span(var out, text, s, caps.get(2 * g + 1))
            put(var out, "\n")

fn put_group(var out: BytesBuilder, text: Bytes, caps: List[Int], g: Int) Unit:
    let s = caps.get(2 * g)
    if s >= 0:
        for j in range(s, caps.get(2 * g + 1)):
            out.append(text.get(j))

# Appends the expansion of repl for one match.
fn expand(
    re: Regex,
    text: Bytes,
    repl: Bytes,
    caps: List[Int],
    var out: BytesBuilder
) Result[Unit, PatError]:
    var i = 0

    while i < repl.length():
        let here = repl.get(i)

        if here != ch("$") or i + 1 >= repl.length():
            out.append(here)
            i += 1
        else:
            let d = repl.get(i + 1)

            if is_digit(d):
                let g = d - 48
                if g > re.names.length():
                    return error(PatError(msg: "bad replacement"))

                put_group(var out, text, caps, g)
                i += 2
            else if d == ch("$"):
                out.append(d)
                i += 2
            else if d == ch("\{"):
                var close = i + 2
                while close < repl.length() and repl.get(close) != ch("\}"):
                    close += 1
                if close >= repl.length():
                    return error(PatError(msg: "bad replacement"))

                let g = find_name(re.names.clone(), repl.slice(i + 2, close).get())
                if g == 0:
                    return error(PatError(msg: "bad replacement"))

                put_group(var out, text, caps, g)
                i = close + 1
            else:
                out.append(here)
                i += 1

    return ok(unit)

fn replace_all(re: Regex, text: Bytes, repl: Bytes) Result[Bytes, PatError]:
    var c = Ctx(re: re.clone(), text: text.clone())
    var out = BytesBuilder()
    var last = 0

    for caps in find_all(var c):
        for j in range(last, caps.get(0)):
            out.append(text.get(j))
        try expand(re.clone(), text.clone(), repl.clone(), caps.clone(), var out)
        last = caps.get(1)

    for j in range(last, text.length()):
        out.append(text.get(j))
    return ok(out.freeze())

# Decodes the escapes of a subject or replacement field.
fn unescape(raw: Bytes) Result[Bytes, PatError]:
    var out = BytesBuilder()
    var i = 0

    while i < raw.length():
        let c = raw.get(i)

        if c != 92:
            out.append(c)
            i += 1
        else:
            if i + 1 >= raw.length():
                return error(PatError(msg: "bad command"))

            let e = raw.get(i + 1)

            if e == ch("n"):
                out.append(10)
                i += 2
            else if e == ch("t"):
                out.append(9)
                i += 2
            else if e == 92:
                out.append(92)
                i += 2
            else if e == ch("x"):
                let hi = hex_value(byte_or(raw, i + 2))
                let lo = hex_value(byte_or(raw, i + 3))
                if hi < 0 or lo < 0:
                    return error(PatError(msg: "bad command"))

                out.append(hi * 16 + lo)
                i += 4
            else:
                return error(PatError(msg: "bad command"))

    return ok(out.freeze())

# Runs one input line and returns its output, or the error to print.
fn process(line: Bytes) Result[Bytes, PatError]:
    let fields = line.split("\t".to_bytes())
    let cmd = fields.get(0).clone()
    let known = (
        cmd == "test".to_bytes()
        or cmd == "match".to_bytes()
        or cmd == "full".to_bytes()
        or cmd == "find-all".to_bytes()
        or cmd == "split".to_bytes()
        or cmd == "replace".to_bytes()
    )
    var want = 3
    if cmd == "replace".to_bytes():
        want = 4
    if not known or fields.length() != want:
        return error(PatError(msg: "bad command"))

    let text = try unescape(fields.get(2).clone())
    var repl = "".to_bytes()
    if want == 4:
        repl = try unescape(fields.get(3).clone())

    let re = try compile(fields.get(1).clone())

    if cmd == "replace".to_bytes():
        let replaced = try replace_all(re, text, repl)
        var out = BytesBuilder()
        put_quoted(var out, replaced.clone(), 0, replaced.length())
        put(var out, "\n")
        return ok(out.freeze())

    var c = Ctx(re: re, text: text)
    var out = BytesBuilder()

    if cmd == "test".to_bytes():
        if exec(var c, 0, false).is_some():
            put(var out, "true\n")
        else:
            put(var out, "false\n")
    else if cmd == "match".to_bytes() or cmd == "full".to_bytes():
        let m = exec(var c, 0, cmd == "full".to_bytes())

        if m.is_none():
            put(var out, "no match\n")
        else:
            put_captures(var out, c.re.clone(), c.text.clone(), m.get())
    else if cmd == "find-all".to_bytes():
        let all = find_all(var c)

        for caps in all:
            put_span(var out, c.text.clone(), caps.get(0), caps.get(1))
            put(var out, "\n")

        put(var out, "({all.length()} matches)\n")
    else:
        var pieces = 1
        var last = 0

        for caps in find_all(var c):
            if caps.get(1) > caps.get(0):
                put_quoted(var out, c.text.clone(), last, caps.get(0))
                put(var out, "\n")
                last = caps.get(1)
                pieces += 1

        put_quoted(var out, c.text.clone(), last, c.text.length())
        put(var out, "\n({pieces} pieces)\n")

    return ok(out.freeze())

export fn main() Int:
    let data = read_all(stdin()).get()
    var out = BytesBuilder()

    for line in data.split("\n".to_bytes()):
        if not line.is_empty():
            let result = process(line)

            if result.is_error():
                put(var out, "error: {result.err().msg}\n")
            else:
                out.concat(result.get())

    stdout().write_bytes(out.freeze()).get()
    return 0
