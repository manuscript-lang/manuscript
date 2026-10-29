import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"
import {Bytes, BytesBuilder} from "@std/bytes.ms"

# Regex AST. Every single-byte matcher is a 256-entry membership table.
type Node:
    case Chars(bits: List[Bool])
    case Seq(items: List[Node])
    case Alt(alts: List[Node])
    case Cap(index: Int, body: Node)
    case Rep(body: Node, low: Int, high: Int, lazy: Bool)
    case Backref(index: Int, name: String)
    case Bol(multi: Bool)
    case Eol(multi: Bool)
    case Word(want: Bool)
    case Look(body: Node, negative: Bool)

type PErr:
    msg: String

impl Error for PErr:
    fn message() String: self.msg.clone()

type Pattern:
    root: Node
    groups: Int
    names: List[String]
    icase: Bool

type Parser:
    pat: Bytes
    at: Int
    groups: Int
    names: List[String]
    ref_nums: List[Int]
    ref_names: List[String]
    icase: Bool
    multi: Bool
    dotall: Bool

fn ch(s: String) Int:
    return s.to_bytes().get(0).to_int()

fn byte_at(bytes: Bytes, i: Int) Int:
    if i >= 0 and i < bytes.length():
        return bytes.get(i).to_int()

    return -1

fn is_digit(c: Int) Bool:
    return c >= 48 and c <= 57

fn is_alpha(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_alnum(c: Int) Bool:
    return is_digit(c) or is_alpha(c)

fn is_word(c: Int) Bool:
    return is_alnum(c) or c == 95

fn is_space(c: Int) Bool:
    return c == 32 or (c >= 9 and c <= 13)

fn is_short(e: Int) Bool:
    return (
        e == ch("d")
        or e == ch("D")
        or e == ch("w")
        or e == ch("W")
        or e == ch("s")
        or e == ch("S")
    )

fn lower(c: Int) Int:
    if c >= 65 and c <= 90:
        return c + 32

    return c

fn hex_val(c: Int) Int:
    if is_digit(c):
        return c - 48
    if c >= 97 and c <= 102:
        return c - 87
    if c >= 65 and c <= 70:
        return c - 55

    return -1

# Value of the two hex digits starting at `at`, or -1.
fn hex2(pat: Bytes, at: Int) Int:
    let hi = hex_val(byte_at(pat, at))
    let lo = hex_val(byte_at(pat, at + 1))
    if hi < 0 or lo < 0:
        return -1

    return hi * 16 + lo

fn simple_escape(e: Int) Int:
    if e == ch("n"):
        return 10
    if e == ch("t"):
        return 9
    if e == ch("r"):
        return 13

    return -1

fn empty_bits() List[Bool]:
    var bits = List[Bool]()
    for _i in 0..256:
        bits.append(false)
    return bits

fn fold_bits(var bits: List[Bool]) Unit:
    for c in 65..91:
        if bits[c] or bits[c + 32]:
            bits[c] = true
            bits[c + 32] = true

fn lit_bits(c: Int, icase: Bool) List[Bool]:
    var bits = empty_bits()
    bits[c] = true
    if icase:
        fold_bits(var bits)
    return bits

fn short_has(e: Int, v: Int) Bool:
    let upper = e < 97

    let base = if upper: e + 32 else: e

    if base == ch("d"):
        return is_digit(v) != upper
    if base == ch("w"):
        return is_word(v) != upper

    return is_space(v) != upper

fn add_short(var bits: List[Bool], e: Int) Unit:
    for v in 0..256:
        if short_has(e, v):
            bits[v] = true

fn short_bits(e: Int) List[Bool]:
    var bits = empty_bits()
    add_short(var bits, e)
    return bits

fn quantifiable(node: Node) Bool:
    match node:
        Bol(_m):
            return false
        Eol(_m):
            return false
        Word(_w):
            return false
        Look(_b, _n):
            return false
        _:
            return true

fn has_name(names: List[String], name: String) Bool:
    return index_of(names, name) > 0

fn index_of(names: List[String], name: String) Int:
    if name == "":
        return -1

    for i in 0..names.length():
        if names[i] == name:
            return i
    return -1

fn digits_end(pat: Bytes, at: Int) Int:
    var i = at
    while is_digit(byte_at(pat, i)):
        i += 1
    return i

fn digits_value(pat: Bytes, from: Int, to: Int) Int:
    var v = 0

    for i in from..to:
        v = v * 10 + byte_at(pat, i) - 48
        if v > 100000:
            v = 100000

    return v

# Length of a well-formed `{n}`, `{n,}` or `{n,m}` at the parser position, or 0.
fn brace_len(ps: Parser) Int:
    let d1 = digits_end(ps.pat, ps.at + 1)
    if d1 == ps.at + 1:
        return 0
    if byte_at(ps.pat, d1) == ch("\}"):
        return d1 + 1 - ps.at
    if byte_at(ps.pat, d1) != ch(","):
        return 0

    let d2 = digits_end(ps.pat, d1 + 1)
    if byte_at(ps.pat, d2) == ch("\}"):
        return d2 + 1 - ps.at

    return 0

fn peek(ps: Parser) Int:
    return byte_at(ps.pat, ps.at)

fn finish_group(var ps: Parser, node: Node) Result[Node, PErr]:
    if peek(ps) != ch(")"):
        return error(PErr(msg: "unmatched ("))

    ps.at += 1
    return ok(node)

# Reads `<name>` where ps.at points at the `<`.
fn read_name(var ps: Parser) Optional[String]:
    let start = ps.at + 1
    var i = start
    if not (is_alpha(byte_at(ps.pat, i)) or byte_at(ps.pat, i) == 95):
        return none

    while is_word(byte_at(ps.pat, i)):
        i += 1
    if byte_at(ps.pat, i) != ch(">"):
        return none

    ps.at = i + 1
    return ps.pat.decode_utf8_range(start, i)

fn parse_pattern(pat: Bytes) Result[Pattern, PErr]:
    var ps = Parser(
        pat: pat.clone(), at: 0, groups: 0, names: [""], ref_nums: List[Int](),
        ref_names: List[String](), icase: false, multi: false, dotall: false
    )

    if byte_at(pat, 0) == ch("(") and byte_at(pat, 1) == ch("?"):
        var j = 2

        while (
            byte_at(pat, j) == ch("i")
            or byte_at(pat, j) == ch("m")
            or byte_at(pat, j) == ch("s")
        ):
            let f = byte_at(pat, j)
            ps.icase = ps.icase or f == ch("i")
            ps.multi = ps.multi or f == ch("m")
            ps.dotall = ps.dotall or f == ch("s")
            j += 1

        if j > 2 and byte_at(pat, j) == ch(")"):
            ps.at = j + 1

    let root = try parse_alt(var ps)
    if ps.at < pat.length():
        return error(PErr(msg: "unmatched )"))

    for n in ps.ref_nums:
        if n > ps.groups:
            return error(PErr(msg: "bad backreference"))
    for nm in ps.ref_names:
        if not has_name(ps.names, nm):
            return error(PErr(msg: "bad backreference"))
    return ok(
        Pattern(
            root: root, groups: ps.groups, names: ps.names.clone(), icase: ps.icase
        )
    )

fn parse_alt(var ps: Parser) Result[Node, PErr]:
    var alts = List[Node]()
    let first = try parse_seq(var ps)
    alts.append(first)

    while peek(ps) == ch("|"):
        ps.at += 1

        let next = try parse_seq(var ps)
        alts.append(next)

    if alts.length() == 1:
        return ok(alts[0].clone())

    return ok(Node.Alt(alts: alts))

fn parse_seq(var ps: Parser) Result[Node, PErr]:
    var items = List[Node]()

    # 0: start of sequence, 1: quantifiable atom, 2: anchor-like, 3: already quantified
    var last = 0

    while ps.at < ps.pat.length():
        let c = peek(ps)
        if c == ch("|") or c == ch(")"):
            break

        if (
            c == ch("*")
            or c == ch("+")
            or c == ch("?")
            or (c == ch("\{") and last != 0 and brace_len(ps) > 0)
        ):
            if last != 1:
                return error(PErr(msg: "nothing to repeat"))

            let idx = items.length() - 1
            let quantified = try parse_quant(var ps, items[idx].clone())
            items[idx] = quantified
            last = 3
        else:
            let atom = try parse_atom(var ps)

            last = if quantifiable(atom): 1 else: 2

            items.append(atom)

    if items.length() == 1:
        return ok(items[0].clone())

    return ok(Node.Seq(items: items))

fn parse_quant(var ps: Parser, body: Node) Result[Node, PErr]:
    let c = peek(ps)
    var low = 0
    var high = -1

    if c == ch("\{"):
        let d1 = digits_end(ps.pat, ps.at + 1)
        low = digits_value(ps.pat, ps.at + 1, d1)

        if byte_at(ps.pat, d1) == ch("\}"):
            high = low
            ps.at = d1 + 1
        else:
            let d2 = digits_end(ps.pat, d1 + 1)

            high = if d2 == d1 + 1: -1 else: digits_value(ps.pat, d1 + 1, d2)

            ps.at = d2 + 1
    else:
        if c == ch("+"):
            low = 1
        if c == ch("?"):
            high = 1
        ps.at += 1

    var lazy = false

    if peek(ps) == ch("?"):
        lazy = true
        ps.at += 1

    if low > 1000 or high > 1000 or (high >= 0 and low > high):
        return error(PErr(msg: "bad repeat"))

    return ok(Node.Rep(body: body, low: low, high: high, lazy: lazy))

fn parse_atom(var ps: Parser) Result[Node, PErr]:
    let c = peek(ps)
    if c == ch("("):
        return parse_group(var ps)
    if c == ch("["):
        return parse_class(var ps)
    if c == ch("\\"):
        return parse_escape(var ps)

    ps.at += 1

    if c == ch("."):
        var dot = empty_bits()
        for v in 0..256:
            dot[v] = ps.dotall or v != 10
        return ok(Node.Chars(bits: dot))

    if c == ch("^"):
        return ok(Node.Bol(multi: ps.multi))
    if c == ch("$"):
        return ok(Node.Eol(multi: ps.multi))

    return ok(Node.Chars(bits: lit_bits(c, ps.icase)))

fn parse_group(var ps: Parser) Result[Node, PErr]:
    ps.at += 1

    if peek(ps) == ch("?"):
        let kind = byte_at(ps.pat, ps.at + 1)

        if kind == ch(":"):
            ps.at += 2

            let body = try parse_alt(var ps)
            return finish_group(var ps, Node.Seq(items: [body]))

        if kind == ch("=") or kind == ch("!"):
            ps.at += 2

            let body = try parse_alt(var ps)
            return finish_group(
                var ps, Node.Look(body: body, negative: kind == ch("!"))
            )

        if kind == ch("<"):
            ps.at += 1

            let name = read_name(var ps)
            if name.is_none():
                return error(PErr(msg: "bad group"))

            let nm = name.get("")
            if has_name(ps.names, nm):
                return error(PErr(msg: "duplicate group name"))

            ps.groups += 1
            ps.names.append(nm)

            let idx = ps.groups
            let body = try parse_alt(var ps)
            return finish_group(var ps, Node.Cap(index: idx, body: body))

        return error(PErr(msg: "bad group"))

    ps.groups += 1
    ps.names.append("")

    let idx = ps.groups
    let body = try parse_alt(var ps)
    return finish_group(var ps, Node.Cap(index: idx, body: body))

fn parse_escape(var ps: Parser) Result[Node, PErr]:
    let e = byte_at(ps.pat, ps.at + 1)
    if e < 0:
        return error(PErr(msg: "bad escape"))

    ps.at += 2
    if is_short(e):
        return ok(Node.Chars(bits: short_bits(e)))
    if e == ch("b"):
        return ok(Node.Word(want: true))
    if e == ch("B"):
        return ok(Node.Word(want: false))

    let simple = simple_escape(e)
    if simple >= 0:
        return ok(Node.Chars(bits: lit_bits(simple, ps.icase)))

    if e == ch("x"):
        let v = hex2(ps.pat, ps.at)
        if v < 0:
            return error(PErr(msg: "bad escape"))

        ps.at += 2
        return ok(Node.Chars(bits: lit_bits(v, ps.icase)))

    if e >= ch("1") and e <= ch("9"):
        ps.ref_nums.append(e - 48)
        return ok(Node.Backref(index: e - 48, name: ""))

    if e == ch("k"):
        if peek(ps) != ch("<"):
            return error(PErr(msg: "bad escape"))

        let name = read_name(var ps)
        if name.is_none():
            return error(PErr(msg: "bad escape"))

        let nm = name.get("")
        ps.ref_names.append(nm.clone())
        return ok(Node.Backref(index: -1, name: nm))

    if e < 128 and not is_alnum(e):
        return ok(Node.Chars(bits: lit_bits(e, ps.icase)))

    return error(PErr(msg: "bad escape"))

# One class member: a byte value, or 256 + letter for a shorthand class.
fn class_atom(var ps: Parser) Result[Int, PErr]:
    if peek(ps) != ch("\\"):
        let c = peek(ps)
        ps.at += 1
        return ok(c)

    let e = byte_at(ps.pat, ps.at + 1)
    if e < 0:
        return error(PErr(msg: "unterminated class"))

    ps.at += 2
    if is_short(e):
        return ok(256 + e)

    let simple = simple_escape(e)
    if simple >= 0:
        return ok(simple)

    if e == ch("x"):
        let v = hex2(ps.pat, ps.at)
        if v < 0:
            return error(PErr(msg: "bad escape"))

        ps.at += 2
        return ok(v)

    if e < 128 and not is_alnum(e):
        return ok(e)

    return error(PErr(msg: "bad escape"))

# True when the parser is at a `-` that forms a range with the previous member.
fn at_range_dash(ps: Parser) Bool:
    if peek(ps) != ch("-"):
        return false

    let next = byte_at(ps.pat, ps.at + 1)
    return next >= 0 and next != ch("]")

fn parse_class(var ps: Parser) Result[Node, PErr]:
    ps.at += 1

    var negate = false

    if peek(ps) == ch("^"):
        negate = true
        ps.at += 1

    var bits = empty_bits()
    var first = true
    var closed = false

    while ps.at < ps.pat.length():
        if peek(ps) == ch("]") and not first:
            ps.at += 1
            closed = true
            break

        first = false

        let a = try class_atom(var ps)

        if a >= 256:
            add_short(var bits, a - 256)
            if at_range_dash(ps):
                return error(PErr(msg: "bad range"))
        else if at_range_dash(ps):
            ps.at += 1

            let b = try class_atom(var ps)
            if b >= 256 or b < a:
                return error(PErr(msg: "bad range"))

            for v in a..b + 1:
                bits[v] = true
        else:
            bits[a] = true

    if not closed:
        return error(PErr(msg: "unterminated class"))

    if ps.icase:
        fold_bits(var bits)
    if negate:
        for v in 0..256:
            bits[v] = not bits[v]
    return ok(Node.Chars(bits: bits))

# Compiled form of a pattern: a flat instruction list run by a backtracking VM.
# Slots hold, in order: capture start/end pairs for groups 0..groups, the open-group
# start positions (-1 when closed), then one progress mark per repeat.
type Inst:
    case CharSet(set: Int)
    case Split(first: Int, second: Int)
    case Jump(target: Int)
    case Open(group: Int)
    case Close(group: Int)
    case LineStart(multi: Bool)
    case LineEnd(multi: Bool)
    case WordEdge(want: Bool)
    case BackRef(group: Int)
    case Mark(slot: Int)
    case Progress(slot: Int, exit: Int)
    case LookStart(negative: Bool, after: Int)
    case Accept
    case Finish

type Prog:
    code: List[Inst]
    sets: List[List[Bool]]
    groups: Int
    slots: Int
    icase: Bool

type Compiler:
    code: List[Inst]
    sets: List[List[Bool]]
    groups: Int
    marks: Int
    names: List[String]

fn emit(var cs: Compiler, inst: Inst) Unit:
    cs.code.append(inst)

fn choice(lazy: Bool, body: Int, exit: Int) Inst:
    if lazy:
        return Inst.Split(first: exit, second: body)

    return Inst.Split(first: body, second: exit)

fn compile(var cs: Compiler, node: Node) Unit:
    match node:
        Chars(bits):
            cs.sets.append(bits.clone())
            emit(var cs, Inst.CharSet(set: cs.sets.length() - 1))
        Seq(items):
            for item in items:
                compile(var cs, item)
        Alt(alts):
            compile_alt(var cs, alts)
        Cap(index, body):
            emit(var cs, Inst.Open(group: index))
            compile(var cs, body)
            emit(var cs, Inst.Close(group: index))
        Rep(body, low, high, lazy):
            compile_rep(var cs, body, low, high, lazy)
        Backref(index, name):
            let g = if index >= 0: index else: index_of(cs.names, name)
            emit(var cs, Inst.BackRef(group: g))
        Bol(multi):
            emit(var cs, Inst.LineStart(multi: multi))
        Eol(multi):
            emit(var cs, Inst.LineEnd(multi: multi))
        Word(want):
            emit(var cs, Inst.WordEdge(want: want))
        Look(body, negative):
            let start = cs.code.length()
            emit(var cs, Inst.Accept)
            compile(var cs, body)
            emit(var cs, Inst.Accept)
            cs.code[start] = Inst.LookStart(negative: negative, after: cs.code.length())

fn compile_alt(var cs: Compiler, alts: List[Node]) Unit:
    var ends = List[Int]()

    for i in 0..alts.length():
        if i < alts.length() - 1:
            let split = cs.code.length()
            emit(var cs, Inst.Accept)
            compile(var cs, alts[i])
            ends.append(cs.code.length())
            emit(var cs, Inst.Accept)
            cs.code[split] = Inst.Split(first: split + 1, second: cs.code.length())
        else:
            compile(var cs, alts[i])

    for j in ends:
        cs.code[j] = Inst.Jump(target: cs.code.length())

# Every iteration after `low` gets a progress check: an iteration that consumed nothing ends the loop.
fn compile_rep(var cs: Compiler, body: Node, low: Int, high: Int, lazy: Bool) Unit:
    for _i in 0..low:
        compile(var cs, body)

    let slot = 3 * (cs.groups + 1) + cs.marks
    cs.marks += 1

    if high < 0:
        let split = cs.code.length()
        emit(var cs, Inst.Accept)
        emit(var cs, Inst.Mark(slot: slot))
        compile(var cs, body)

        let progress = cs.code.length()
        emit(var cs, Inst.Accept)
        emit(var cs, Inst.Jump(target: split))

        let exit = cs.code.length()
        cs.code[split] = choice(lazy, split + 1, exit)
        cs.code[progress] = Inst.Progress(slot: slot, exit: exit)
    else:
        var splits = List[Int]()
        var progresses = List[Int]()

        for _i in low..high:
            splits.append(cs.code.length())
            emit(var cs, Inst.Accept)
            emit(var cs, Inst.Mark(slot: slot))
            compile(var cs, body)
            progresses.append(cs.code.length())
            emit(var cs, Inst.Accept)

        let exit = cs.code.length()
        for s in splits:
            cs.code[s] = choice(lazy, s + 1, exit)
        for p in progresses:
            cs.code[p] = Inst.Progress(slot: slot, exit: exit)

fn build(root: Node, groups: Int, names: List[String], icase: Bool) Prog:
    var cs = Compiler(
        code: List[Inst](), sets: List[List[Bool]](), groups: groups, marks: 0,
        names: names
    )
    compile(var cs, root)
    emit(var cs, Inst.Finish)
    return Prog(
        code: cs.code.clone(), sets: cs.sets.clone(), groups: groups,
        slots: 3 * (groups + 1) + cs.marks, icase: icase
    )

fn initial_slots(p: Prog) List[Int]:
    var slots = List[Int]()
    for _i in 0..p.slots:
        slots.append(-1)
    return slots

fn reset_slots(var slots: List[Int]) Unit:
    for i in 0..slots.length():
        slots[i] = -1

fn restore_slots(var slots: List[Int], snap: List[Int]) Unit:
    for i in 0..snap.length():
        slots[i] = snap[i]

# Writes a slot and logs the old value so backtracking can undo it.
fn set_slot(var stack: List[Int], var slots: List[Int], idx: Int, value: Int) Unit:
    stack.append(slots[idx])
    stack.append(idx)
    stack.append(1)
    slots[idx] = value

fn same_text(subj: Bytes, s: Int, e: Int, pos: Int, icase: Bool) Bool:
    let len = e - s
    if pos + len > subj.length():
        return false

    for i in 0..len:
        var a = subj.get(s + i).to_int()
        var b = subj.get(pos + i).to_int()

        if icase:
            a = lower(a)
            b = lower(b)

        if a != b:
            return false

    return true

# Runs from start_pc at start_pos. Stack entries are triples (kind, a, b):
# kind 0 is a branch to a at position b, kind 1 restores slot a to b, kind 2 restores snapshot a.
fn run(
    p: Prog,
    subj: Bytes,
    var slots: List[Int],
    start_pc: Int,
    start_pos: Int,
    full: Bool
) Bool:
    let n = subj.length()
    let open_base = 2 * (p.groups + 1)
    var pc = start_pc
    var pos = start_pos
    var stack = List[Int]()
    var snaps = List[List[Int]]()

    while true:
        var failed = false
        let ins = p.code[pc]

        match ins:
            CharSet(set):
                if pos < n and p.sets[set][subj.get(pos).to_int()]:
                    pc += 1
                    pos += 1
                else:
                    failed = true
            Split(first, second):
                stack.append(pos)
                stack.append(second)
                stack.append(0)
                pc = first
            Jump(target):
                pc = target
            Open(group):
                set_slot(var stack, var slots, open_base + group, pos)
                pc += 1
            Close(group):
                let start = slots[open_base + group]
                set_slot(var stack, var slots, 2 * group, start)
                set_slot(var stack, var slots, 2 * group + 1, pos)
                set_slot(var stack, var slots, open_base + group, -1)
                pc += 1
            LineStart(multi):
                if pos == 0 or (multi and byte_at(subj, pos - 1) == 10):
                    pc += 1
                else:
                    failed = true
            LineEnd(multi):
                if pos == n or (multi and byte_at(subj, pos) == 10):
                    pc += 1
                else:
                    failed = true
            WordEdge(want):
                let before = is_word(byte_at(subj, pos - 1))
                let after = is_word(byte_at(subj, pos))

                if (before != after) == want:
                    pc += 1
                else:
                    failed = true
            BackRef(group):
                let s = slots[2 * group]
                let e = slots[2 * group + 1]

                if slots[open_base + group] >= 0 or s < 0 or e < 0:
                    failed = true
                else if same_text(subj, s, e, pos, p.icase):
                    pos += e - s
                    pc += 1
                else:
                    failed = true
            Mark(slot):
                set_slot(var stack, var slots, slot, pos)
                pc += 1
            Progress(slot, exit):
                if slots[slot] == pos:
                    pc = exit
                else:
                    pc += 1
            LookStart(negative, after):
                snaps.append(slots.clone())

                let matched = run(p, subj, var slots, pc + 1, pos, false)

                if negative:
                    restore_slots(var slots, snaps[snaps.length() - 1])

                    if matched:
                        failed = true
                    else:
                        pc = after
                else if matched:
                    stack.append(0)
                    stack.append(snaps.length() - 1)
                    stack.append(2)
                    pc = after
                else:
                    failed = true
            Accept:
                return true
            Finish:
                if full and pos != n:
                    failed = true
                else:
                    slots[1] = pos
                    return true

        if failed:
            var resumed = false

            while not resumed:
                if stack.length() == 0:
                    return false

                let kind = stack.pop().get(0)
                let a = stack.pop().get(0)
                let b = stack.pop().get(0)

                if kind == 0:
                    pc = a
                    pos = b
                    resumed = true
                else if kind == 1:
                    slots[a] = b
                else:
                    restore_slots(var slots, snaps[a])

# Leftmost match starting at or after `from`; on success slots holds the match.
fn search(p: Prog, subj: Bytes, var slots: List[Int], from: Int, full: Bool) Bool:
    var s = from

    while s <= subj.length():
        reset_slots(var slots)
        slots[0] = s
        if run(p, subj, var slots, 0, s, full):
            return true
        if full:
            return false

        s += 1

    return false

fn snapshot(slots: List[Int], count: Int) List[Int]:
    var out = List[Int]()
    for i in 0..count:
        out.append(slots[i])
    return out

# Successive matches as capture snapshots, following the find-all rules.
fn find_all(p: Prog, subj: Bytes, var slots: List[Int]) List[List[Int]]:
    var out = List[List[Int]]()
    var pos = 0

    while pos <= subj.length():
        if not search(p, subj, var slots, pos, false):
            break

        let snap = snapshot(slots, 2 * (p.groups + 1))

        pos = if snap[1] > snap[0]: snap[1] else: snap[1] + 1

        out.append(snap)

    return out

fn put(var out: BytesBuilder, v: Int) Unit:
    out.append(v.to_uint8().get(0))

fn put_range(var out: BytesBuilder, src: Bytes, from: Int, to: Int) Unit:
    for i in from..to:
        out.append(src.get(i))

fn emit_text(var out: BytesBuilder, text: String) Unit:
    out.append_bytes(text.to_bytes())

fn emit_quoted(var out: BytesBuilder, src: Bytes, from: Int, to: Int) Unit:
    put(var out, 34)

    for i in from..to:
        let c = src.get(i).to_int()

        if c == 92 or c == 34:
            put(var out, 92)
            put(var out, c)
        else if c == 10:
            put(var out, 92)
            put(var out, ch("n"))
        else if c == 9:
            put(var out, 92)
            put(var out, ch("t"))
        else if c == 13:
            put(var out, 92)
            put(var out, ch("r"))
        else if c < 32 or c > 126:
            put(var out, 92)
            put(var out, ch("x"))
            if c < 16:
                put(var out, ch("0"))
            emit_text(var out, c.to_string_radix(16))
        else:
            put(var out, c)

    put(var out, 34)

fn emit_span(var out: BytesBuilder, start: Int, end: Int, subject: Bytes) Unit:
    emit_text(var out, "{start}..{end} ")
    emit_quoted(var out, subject, start, end)

fn emit_group(
    var out: BytesBuilder, names: List[String], caps: List[Int], subject: Bytes, g: Int
) Unit:
    var label = "{g}"
    if g > 0 and names[g] != "":
        label = "{g} ({names[g]})"
    emit_text(var out, "{label}: ")

    let s = caps[2 * g]
    let e = caps[2 * g + 1]

    if s >= 0 and e >= 0:
        emit_span(var out, s, e, subject)
        emit_text(var out, "\n")
    else:
        emit_text(var out, "unset\n")

# Expands a replacement template for one match.
fn expand(
    tmpl: Bytes,
    subject: Bytes,
    caps: List[Int],
    names: List[String]
) Result[Bytes, PErr]:
    let groups = caps.length() / 2 - 1
    var out = BytesBuilder()
    var i = 0

    while i < tmpl.length():
        let c = tmpl.get(i).to_int()
        let nxt = byte_at(tmpl, i + 1)

        if c != ch("$") or nxt < 0:
            out.append(tmpl.get(i))
            i += 1
        else if is_digit(nxt):
            let g = nxt - 48
            if g > groups:
                return error(PErr(msg: "bad replacement"))

            if caps[2 * g] >= 0 and caps[2 * g + 1] >= 0:
                put_range(var out, subject, caps[2 * g], caps[2 * g + 1])
            i += 2
        else if nxt == ch("$"):
            out.append(tmpl.get(i + 1))
            i += 2
        else if nxt == ch("\{"):
            var close = i + 2
            while close < tmpl.length() and tmpl.get(close).to_int() != ch("\}"):
                close += 1
            if close >= tmpl.length():
                return error(PErr(msg: "bad replacement"))

            let g = index_of(names, tmpl.decode_utf8_range(i + 2, close).get(""))
            if g < 0:
                return error(PErr(msg: "bad replacement"))

            if caps[2 * g] >= 0 and caps[2 * g + 1] >= 0:
                put_range(var out, subject, caps[2 * g], caps[2 * g + 1])
            i = close + 1
        else:
            out.append(tmpl.get(i))
            i += 1

    return ok(out.build())

fn run_command(
    var out: BytesBuilder, cmd: String, pattern: String, subject: Bytes, repl: Bytes
) Result[Unit, PErr]:
    let p = try parse_pattern(pattern.to_bytes())
    let prog = build(p.root.clone(), p.groups, p.names.clone(), p.icase)
    var slots = initial_slots(prog)

    if cmd == "test":
        if search(prog, subject, var slots, 0, false):
            emit_text(var out, "true\n")
        else:
            emit_text(var out, "false\n")

        return ok(unit)

    if cmd == "match" or cmd == "full":
        if not search(prog, subject, var slots, 0, cmd == "full"):
            emit_text(var out, "no match\n")
            return ok(unit)

        for g in 0..p.groups + 1:
            emit_group(var out, p.names, slots, subject, g)
        return ok(unit)

    let matches = find_all(prog, subject, var slots)

    if cmd == "find-all":
        for snap in matches:
            emit_span(var out, snap[0], snap[1], subject)
            emit_text(var out, "\n")

        emit_text(var out, "({matches.length()} matches)\n")
        return ok(unit)

    if cmd == "split":
        var kept = 0
        var prev = 0

        for snap in matches:
            if snap[1] > snap[0]:
                emit_quoted(var out, subject, prev, snap[0])
                emit_text(var out, "\n")
                kept += 1
                prev = snap[1]

        emit_quoted(var out, subject, prev, subject.length())
        emit_text(var out, "\n({kept + 1} pieces)\n")
        return ok(unit)

    var result = BytesBuilder()
    var prev = 0

    for snap in matches:
        put_range(var result, subject, prev, snap[0])

        let piece = try expand(repl, subject, snap, p.names)
        result.append_bytes(piece)
        prev = snap[1]

    put_range(var result, subject, prev, subject.length())

    let text = result.build()
    emit_quoted(var out, text, 0, text.length())
    emit_text(var out, "\n")
    return ok(unit)

# Decodes \n \t \\ \xHH in a subject or replacement field.
fn unescape(raw: Bytes) Optional[Bytes]:
    var out = BytesBuilder()
    var i = 0

    while i < raw.length():
        let c = raw.get(i).to_int()

        if c != ch("\\"):
            out.append(raw.get(i))
            i += 1
        else:
            let e = byte_at(raw, i + 1)

            if e == ch("n"):
                put(var out, 10)
                i += 2
            else if e == ch("t"):
                put(var out, 9)
                i += 2
            else if e == ch("\\"):
                put(var out, 92)
                i += 2
            else if e == ch("x") and hex2(raw, i + 2) >= 0:
                put(var out, hex2(raw, i + 2))
                i += 4
            else:
                return none

    return out.build()

fn process_line(var out: BytesBuilder, line: String) Unit:
    let fields = line.split("\t")
    let cmd = fields[0]
    let is_replace = cmd == "replace"
    let known = (
        cmd == "test"
        or cmd == "match"
        or cmd == "full"
        or cmd == "find-all"
        or cmd == "split"
        or is_replace
    )

    let want = if is_replace: 4 else: 3

    if not known or fields.length() != want:
        emit_text(var out, "error: bad command\n")
        return

    let repl_text = if is_replace: fields[3].clone() else: ""

    if let subject = unescape(fields[2].to_bytes()):
        if let repl = unescape(repl_text.to_bytes()):
            let result = run_command(var out, cmd, fields[1].clone(), subject, repl)
            if result.is_error():
                emit_text(var out, "error: {result.err().message()}\n")
            return

    emit_text(var out, "error: bad command\n")

export fn main() Int:
    var out = BytesBuilder()
    for line in read_lines(stdin()).get():
        if line.length() > 0:
            process_line(var out, line)
    stdout().write_bytes(out.build()).get()
    return 0
