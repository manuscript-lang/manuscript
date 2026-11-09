import stdin, stdout_bytes from "@std/io/io.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"

// ---------------------------------------------------------------
// AST
// ---------------------------------------------------------------
enum Node:
    Lit(bits: List[Bool])
    Assert(kind: Int)
    Cap(index: Int, body: Node)
    Seq(items: List[Node])
    Alt(items: List[Node])
    Rep(body: Node, lo: Int, hi: Int, lazy: Bool)
    Look(body: Node, neg: Bool)
    Backref(num: Int, name: String)

// ---------------------------------------------------------------
// Parser state and quantifier / class helper records
// ---------------------------------------------------------------
type PState:
    p: Bytes
    i: Int
    ngroups: Int
    names: List[String]
    name_nums: List[Int]
    br_nums: List[Int]
    br_names: List[String]
    ci: Bool
    multi: Bool
    dotall: Bool
    err: String

type Quant:
    ok: Bool
    lo: Int
    hi: Int
    width: Int

type CItem:
    kind: Int
    val: Int

// ---------------------------------------------------------------
// Compiled program + matcher state (one record keeps things simple)
// Opcodes:
//   0 SET a=set          1 SPLIT a=pref b=alt     2 JMP a
//   3 SAVE_OPEN a=tmp    4 SAVE_CLOSE a=tmp b=capslot
//   5 MARK a=slot        6 PROGRESS a=slot b=exit c=loop
//   7 ASSERT a=kind      8 BACKREF a=group b=ci
//   9 LOOK a=neg b=body c=next     10 ACCEPT
// Assert kinds: 0 ^  1 $  2 ^(m)  3 $(m)  4 \b  5 \B  6 end-of-subject
// ---------------------------------------------------------------
type Ins:
    op: Int
    a: Int
    b: Int
    c: Int

type Vm:
    code: List[Ins]
    sets: List[List[Bool]]
    nslots: Int
    ngroups: Int
    names: List[String]
    name_nums: List[Int]
    ci: Bool
    full: Bool
    err: String
    subj: Bytes
    n: Int
    slots: List[Int]
    jslot: List[Int]
    jold: List[Int]
    spc: List[Int]
    spos: List[Int]
    sj: List[Int]
    mstart: Int
    mend: Int

type Mt:
    s: Int
    e: Int
    caps: List[Int]

// ---------------------------------------------------------------
// Small byte / set helpers
// ---------------------------------------------------------------
fn at(p: Bytes, i: Int) Int:
    if i >= 0 and i < p.length():
        return p.get(i).to_int()

    return -1

fn is_digit(x: Int) Bool:
    return x >= 48 and x <= 57

fn is_alpha(x: Int) Bool:
    return (x >= 65 and x <= 90) or (x >= 97 and x <= 122)

fn is_alnum(x: Int) Bool:
    return is_digit(x) or is_alpha(x)

fn is_word(x: Int) Bool:
    return is_alnum(x) or x == 95

fn is_space(x: Int) Bool:
    return x == 32 or (x >= 9 and x <= 13)

fn lower(x: Int) Int:
    if x >= 65 and x <= 90:
        return x + 32

    return x

fn other_case(x: Int) Int:
    if x >= 65 and x <= 90:
        return x + 32
    if x >= 97 and x <= 122:
        return x - 32

    return x

fn hexval(x: Int) Int:
    if x >= 48 and x <= 57:
        return x - 48
    if x >= 65 and x <= 70:
        return x - 55
    if x >= 97 and x <= 102:
        return x - 87

    return -1

fn u8(v: Int) UInt8:
    return v.to_uint8().get()

fn blank() List[Bool]:
    var b = List[Bool]()
    for _i in 0..256:
        b.append(false)
    return b

fn single(c: Int, ci: Bool) List[Bool]:
    var b = blank()
    b[c] = true
    if ci:
        b[other_case(c)] = true
    return b

fn shorthand_bits(k: Int) List[Bool]:
    var b = blank()
    let neg = k < 97
    let kl = lower(k)

    for x in 0..256:
        var m = false

        if kl == 100:
            m = is_digit(x)
        else if kl == 119:
            m = is_word(x)
        else:
            m = is_space(x)

        b[x] = if m: not neg else: neg

    return b

fn union_into(var b: List[Bool], src: List[Bool]) Unit:
    for x in 0..256:
        if src[x]:
            b[x] = true

fn fold(var b: List[Bool]) Unit:
    for x in 0..256:
        if b[x]:
            b[other_case(x)] = true

fn negate(var b: List[Bool]) Unit:
    for x in 0..256:
        b[x] = not b[x]

// ---------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------
fn dummy() Node:
    return Seq(List[Node]())

// Returns the index just past a valid name starting at `start`, or -1.
fn name_end(p: Bytes, start: Int) Int:
    let c0 = at(p, start)
    if not (is_alpha(c0) or c0 == 95):
        return -1

    var j = start + 1
    while is_word(at(p, j)):
        j += 1
    return j

fn scan_quant(p: Bytes, i: Int) Quant:
    let c = at(p, i)
    if c == 42:
        return Quant(true, 0, -1, 1)
    if c == 43:
        return Quant(true, 1, -1, 1)
    if c == 63:
        return Quant(true, 0, 1, 1)
    if c != 123:
        return Quant(false, 0, 0, 0)

    var j = i + 1
    var lo = 0
    var nd = 0

    while is_digit(at(p, j)):
        if lo < 100000:
            lo = lo * 10 + (at(p, j) - 48)
        nd += 1
        j += 1

    if nd == 0:
        return Quant(false, 0, 0, 0)
    if at(p, j) == 125:
        return Quant(true, lo, lo, j + 1 - i)
    if at(p, j) != 44:
        return Quant(false, 0, 0, 0)

    j += 1

    var hi = 0
    var hd = 0

    while is_digit(at(p, j)):
        if hi < 100000:
            hi = hi * 10 + (at(p, j) - 48)
        hd += 1
        j += 1

    if at(p, j) != 125:
        return Quant(false, 0, 0, 0)
    if hd == 0:
        return Quant(true, lo, -1, j + 1 - i)

    return Quant(true, lo, hi, j + 1 - i)

fn quantifiable(node: Node) Bool:
    match node:
        Assert(_):
            return false
        Look(_, _):
            return false
        _:
            return true

// Escapes shared by literals and classes. Returns the byte, or -1 if bad.
fn escape_byte(var ps: PState, c: Int) Int:
    if c == 110:
        return 10
    if c == 116:
        return 9
    if c == 114:
        return 13

    if c == 120:
        let h1 = hexval(at(ps.p, ps.i))
        let h2 = hexval(at(ps.p, ps.i + 1))
        if h1 < 0 or h2 < 0:
            return -1

        ps.i += 2
        return h1 * 16 + h2

    if c >= 0 and c < 128 and not is_alnum(c):
        return c

    return -1

fn parse_escape(var ps: PState) Node:
    ps.i += 1

    let c = at(ps.p, ps.i)

    if c < 0:
        ps.err = "bad escape"
        return dummy()

    ps.i += 1
    if c == 100 or c == 68 or c == 119 or c == 87 or c == 115 or c == 83:
        return Lit(shorthand_bits(c))
    if c == 98:
        return Assert(4)
    if c == 66:
        return Assert(5)

    if c >= 49 and c <= 57:
        ps.br_nums.append(c - 48)
        return Backref(c - 48, "")

    if c == 107:
        if at(ps.p, ps.i) != 60:
            ps.err = "bad escape"
            return dummy()

        let e = name_end(ps.p, ps.i + 1)

        if e < 0 or at(ps.p, e) != 62:
            ps.err = "bad escape"
            return dummy()

        let name = ps.p.decode_utf8_range(ps.i + 1, e).get("")
        ps.i = e + 1
        ps.br_names.append(name.clone())
        return Backref(-1, name)

    let v = escape_byte(var ps, c)

    if v < 0:
        ps.err = "bad escape"
        return dummy()

    return Lit(single(v, ps.ci))

fn parse_group(var ps: PState) Node:
    ps.i += 1

    var capture = 0
    var look = -1
    var noncap = false

    if at(ps.p, ps.i) == 63:
        let c2 = at(ps.p, ps.i + 1)

        if c2 == 58:
            noncap = true
            ps.i += 2
        else if c2 == 61 or c2 == 33:
            look = if c2 == 61: 0 else: 1
            ps.i += 2
        else if c2 == 60:
            let e = name_end(ps.p, ps.i + 2)

            if e < 0 or at(ps.p, e) != 62:
                ps.err = "bad group"
                return dummy()

            let name = ps.p.decode_utf8_range(ps.i + 2, e).get("")

            for nm in ps.names:
                if nm == name:
                    ps.err = "duplicate group name"
                    return dummy()

            ps.i = e + 1
            ps.ngroups += 1
            capture = ps.ngroups
            ps.names.append(name)
            ps.name_nums.append(capture)
        else:
            ps.err = "bad group"
            return dummy()
    else:
        ps.ngroups += 1
        capture = ps.ngroups

    let inner = parse_alt(var ps)
    if ps.err != "":
        return dummy()

    if at(ps.p, ps.i) != 41:
        ps.err = "unmatched ("
        return dummy()

    ps.i += 1
    if look >= 0:
        return Look(inner, look == 1)

    if noncap:
        var l = List[Node]()
        l.append(inner)
        return Seq(l)

    return Cap(capture, inner)

fn parse_atom(var ps: PState) Node:
    let c = at(ps.p, ps.i)
    if c == 40:
        return parse_group(var ps)
    if c == 91:
        return parse_class(var ps)
    if c == 92:
        return parse_escape(var ps)

    if c == 42 or c == 43 or c == 63:
        ps.err = "nothing to repeat"
        return dummy()

    ps.i += 1

    if c == 46:
        var b = blank()
        for x in 0..256:
            if x != 10 or ps.dotall:
                b[x] = true
        return Lit(b)

    if c == 94:
        let k = if ps.multi: 2 else: 0
        return Assert(k)

    if c == 36:
        let k = if ps.multi: 3 else: 1
        return Assert(k)

    return Lit(single(c, ps.ci))

fn parse_seq(var ps: PState) Node:
    var items = List[Node]()

    while ps.i < ps.p.length():
        let c = at(ps.p, ps.i)
        if c == 124 or c == 41:
            break

        var node = parse_atom(var ps)
        if ps.err != "":
            return dummy()

        let q = scan_quant(ps.p, ps.i)

        if q.ok:
            if q.hi > 1000 or q.lo > 1000 or (q.hi != -1 and q.lo > q.hi):
                ps.err = "bad repeat"
                return dummy()

            if not quantifiable(node):
                ps.err = "nothing to repeat"
                return dummy()

            ps.i += q.width

            var lazy = false

            if at(ps.p, ps.i) == 63:
                lazy = true
                ps.i += 1

            let nc = at(ps.p, ps.i)

            if nc == 42 or nc == 43 or nc == 63 or scan_quant(ps.p, ps.i).ok:
                ps.err = "nothing to repeat"
                return dummy()

            node = Rep(node, q.lo, q.hi, lazy)

        items.append(node)

    if items.length() == 1:
        return items.pop().get()

    return Seq(items)

fn parse_alt(var ps: PState) Node:
    var alts = List[Node]()

    while true:
        let seq = parse_seq(var ps)
        if ps.err != "":
            return dummy()

        alts.append(seq)

        if at(ps.p, ps.i) == 124:
            ps.i += 1
        else:
            break

    if alts.length() == 1:
        return alts.pop().get()

    return Alt(alts)

fn class_atom(var ps: PState) CItem:
    let c = at(ps.p, ps.i)

    if c < 0:
        ps.err = "unterminated class"
        return CItem(0, 0)

    ps.i += 1
    if c != 92:
        return CItem(0, c)

    let d = at(ps.p, ps.i)

    if d < 0:
        ps.err = "unterminated class"
        return CItem(0, 0)

    ps.i += 1
    if d == 100 or d == 68 or d == 119 or d == 87 or d == 115 or d == 83:
        return CItem(1, d)

    let v = escape_byte(var ps, d)

    if v < 0:
        ps.err = "bad escape"
        return CItem(0, 0)

    return CItem(0, v)

fn parse_class(var ps: PState) Node:
    ps.i += 1

    var neg = false

    if at(ps.p, ps.i) == 94:
        neg = true
        ps.i += 1

    var bits = blank()
    var first = true

    while true:
        let c = at(ps.p, ps.i)

        if c < 0:
            ps.err = "unterminated class"
            return dummy()

        if c == 93 and not first:
            ps.i += 1
            break

        first = false

        let a = class_atom(var ps)
        if ps.err != "":
            return dummy()

        let nx = at(ps.p, ps.i)
        let nn = at(ps.p, ps.i + 1)

        if nx == 45 and nn >= 0 and nn != 93:
            ps.i += 1

            let b = class_atom(var ps)
            if ps.err != "":
                return dummy()

            if a.kind == 1 or b.kind == 1 or b.val < a.val:
                ps.err = "bad range"
                return dummy()

            let hi = b.val + 1
            for x in a.val..hi:
                bits[x] = true
        else if a.kind == 1:
            union_into(var bits, shorthand_bits(a.val))
        else:
            bits[a.val] = true

    if ps.ci:
        fold(var bits)
    if neg:
        negate(var bits)
    return Lit(bits)

// ---------------------------------------------------------------
// Compilation to VM instructions
// ---------------------------------------------------------------
fn emit(var vm: Vm, op: Int, a: Int, b: Int, c: Int) Unit:
    vm.code.append(Ins(op, a, b, c))

fn set_ins(var vm: Vm, idx: Int, op: Int, a: Int, b: Int, c: Int) Unit:
    vm.code.set(idx, Ins(op, a, b, c))

fn name_num(vm: Vm, name: String) Int:
    for k in 0..vm.names.length():
        if vm.names[k] == name:
            return vm.name_nums[k]
    return -1

fn comp(var vm: Vm, node: Node) Unit:
    match node:
        Lit(bits):
            vm.sets.append(bits.clone())
            emit(var vm, 0, vm.sets.length() - 1, 0, 0)
        Assert(kind):
            emit(var vm, 7, kind, 0, 0)
        Cap(index, body):
            let tmp = 2 * (vm.ngroups + 1) + index
            emit(var vm, 3, tmp, 0, 0)
            comp(var vm, body)
            emit(var vm, 4, tmp, 2 * index, 0)
        Seq(items):
            for it in items:
                comp(var vm, it)
        Alt(items):
            var jumps = List[Int]()
            let n = items.length()

            for k in 0..n:
                if k < n - 1:
                    let sp = vm.code.length()
                    emit(var vm, 1, 0, 0, 0)
                    comp(var vm, items[k])
                    jumps.append(vm.code.length())
                    emit(var vm, 2, 0, 0, 0)

                    let nxt = vm.code.length()
                    set_ins(var vm, sp, 1, sp + 1, nxt, 0)
                else:
                    comp(var vm, items[k])

            let end = vm.code.length()
            for j in jumps:
                set_ins(var vm, j, 2, end, 0, 0)
        Rep(body, lo, hi, lazy):
            for _i in 0..lo:
                comp(var vm, body)

            if hi == -1:
                let loop_pc = vm.code.length()
                emit(var vm, 1, 0, 0, 0)

                let mark = vm.nslots
                vm.nslots += 1
                emit(var vm, 5, mark, 0, 0)
                comp(var vm, body)

                let pr = vm.code.length()
                emit(var vm, 6, mark, 0, loop_pc)

                let exit = vm.code.length()
                let bstart = loop_pc + 1

                if lazy:
                    set_ins(var vm, loop_pc, 1, exit, bstart, 0)
                else:
                    set_ins(var vm, loop_pc, 1, bstart, exit, 0)

                set_ins(var vm, pr, 6, mark, exit, loop_pc)
            else:
                var sps = List[Int]()
                var prs = List[Int]()
                var marks = List[Int]()

                for _i in lo..hi:
                    let sp = vm.code.length()
                    emit(var vm, 1, 0, 0, 0)

                    let mark = vm.nslots
                    vm.nslots += 1
                    emit(var vm, 5, mark, 0, 0)
                    comp(var vm, body)

                    let pr = vm.code.length()
                    emit(var vm, 6, mark, 0, 0)
                    sps.append(sp)
                    prs.append(pr)
                    marks.append(mark)

                let exit = vm.code.length()

                for j in 0..sps.length():
                    let sp = sps[j]
                    let pr = prs[j]
                    let mark = marks[j]

                    if lazy:
                        set_ins(var vm, sp, 1, exit, sp + 1, 0)
                    else:
                        set_ins(var vm, sp, 1, sp + 1, exit, 0)

                    set_ins(var vm, pr, 6, mark, exit, pr + 1)
        Look(body, neg):
            let lp = vm.code.length()
            let nv = if neg: 1 else: 0
            emit(var vm, 9, nv, lp + 1, 0)
            comp(var vm, body)
            emit(var vm, 10, 0, 0, 0)

            let nxt = vm.code.length()
            set_ins(var vm, lp, 9, nv, lp + 1, nxt)
        Backref(num, name):
            var g = num
            if g < 0:
                g = name_num(vm, name)

            let ci = if vm.ci: 1 else: 0
            emit(var vm, 8, g, ci, 0)

// Parses and compiles a pattern. Errors are stored in the result's `err`.
fn build(p: Bytes, full: Bool) Vm:
    var ps = PState(
        p: p.clone(), i: 0, ngroups: 0, names: List[String](), name_nums: List[Int](),
        br_nums: List[Int](), br_names: List[String](), ci: false, multi: false,
        dotall: false, err: ""
    )
    let n = p.length()

    if at(p, 0) == 40 and at(p, 1) == 63:
        var j = 2
        var fi = false
        var fm = false
        var fs = false

        while at(p, j) == 105 or at(p, j) == 109 or at(p, j) == 115:
            if at(p, j) == 105:
                fi = true
            if at(p, j) == 109:
                fm = true
            if at(p, j) == 115:
                fs = true
            j += 1

        if j > 2 and at(p, j) == 41:
            ps.ci = fi
            ps.multi = fm
            ps.dotall = fs
            ps.i = j + 1

    let root = parse_alt(var ps)
    if ps.err == "" and ps.i < n:
        ps.err = "unmatched )"

    if ps.err == "":
        for k in ps.br_nums:
            if k > ps.ngroups:
                ps.err = "bad backreference"
        for nm in ps.br_names:
            if name_num_ps(ps, nm) < 0:
                ps.err = "bad backreference"

    var vm = Vm(
        code: List[Ins](), sets: List[List[Bool]](), nslots: 0, ngroups: ps.ngroups,
        names: ps.names, name_nums: ps.name_nums, ci: ps.ci, full: full, err: ps.err,
        subj: "".as_bytes(), n: 0, slots: List[Int](), jslot: List[Int](),
        jold: List[Int](), spc: List[Int](), spos: List[Int](), sj: List[Int](),
        mstart: 0, mend: 0
    )
    if vm.err != "":
        return vm

    vm.nslots = 2 * (ps.ngroups + 1) + ps.ngroups + 1
    comp(var vm, root)
    if full:
        emit(var vm, 7, 6, 0, 0)
    emit(var vm, 10, 0, 0, 0)
    for _k in 0..vm.nslots:
        vm.slots.append(-1)
    return vm

fn name_num_ps(ps: PState, name: String) Int:
    for k in 0..ps.names.length():
        if ps.names[k] == name:
            return ps.name_nums[k]
    return -1

// ---------------------------------------------------------------
// Backtracking VM
// ---------------------------------------------------------------
fn setslot(var vm: Vm, idx: Int, v: Int) Unit:
    vm.jslot.append(idx)
    vm.jold.append(vm.slots[idx])
    vm.slots[idx] = v

fn undo_to(var vm: Vm, jl: Int) Unit:
    while vm.jslot.length() > jl:
        let idx = vm.jslot.pop().get()
        let old = vm.jold.pop().get()
        vm.slots[idx] = old

fn push(var vm: Vm, pc: Int, pos: Int) Unit:
    vm.spc.append(pc)
    vm.spos.append(pos)
    vm.sj.append(vm.jslot.length())

fn assert_ok(vm: Vm, kind: Int, pos: Int) Bool:
    if kind == 0:
        return pos == 0
    if kind == 1:
        return pos == vm.n
    if kind == 2:
        return pos == 0 or vm.subj.get(pos - 1).to_int() == 10
    if kind == 3:
        return pos == vm.n or vm.subj.get(pos).to_int() == 10
    if kind == 6:
        return pos == vm.n

    let before = pos > 0 and is_word(vm.subj.get(pos - 1).to_int())
    let after = pos < vm.n and is_word(vm.subj.get(pos).to_int())
    let boundary = before != after
    if kind == 4:
        return boundary

    return not boundary

// Runs from pc at pos. Returns the end position of the first successful
// path (ACCEPT), or -1. On failure all journal changes are undone.
fn run(var vm: Vm, start_pc: Int, start_pos: Int) Int:
    let sbase = vm.spc.length()
    let j0 = vm.jslot.length()
    var pc = start_pc
    var pos = start_pos

    while true:
        let op = vm.code[pc].op
        let a = vm.code[pc].a
        let b = vm.code[pc].b
        let c = vm.code[pc].c
        var good = true

        if op == 0:
            if pos < vm.n and vm.sets[a][vm.subj.get(pos).to_int()]:
                pos += 1
                pc += 1
            else:
                good = false
        else if op == 1:
            push(var vm, b, pos)
            pc = a
        else if op == 2:
            pc = a
        else if op == 3:
            setslot(var vm, a, pos)
            pc += 1
        else if op == 4:
            setslot(var vm, b, vm.slots[a])
            setslot(var vm, b + 1, pos)
            pc += 1
        else if op == 5:
            setslot(var vm, a, pos)
            pc += 1
        else if op == 6:
            if pos == vm.slots[a]:
                pc = b
            else:
                pc = c
        else if op == 7:
            if assert_ok(vm, a, pos):
                pc += 1
            else:
                good = false
        else if op == 8:
            let s = vm.slots[2 * a]
            let e = vm.slots[2 * a + 1]

            if s < 0 or e < 0 or pos + (e - s) > vm.n:
                good = false
            else:
                var k = 0
                var same = true

                while k < e - s:
                    var x = vm.subj.get(s + k).to_int()
                    var y = vm.subj.get(pos + k).to_int()

                    if b == 1:
                        x = lower(x)
                        y = lower(y)

                    if x != y:
                        same = false
                        break

                    k += 1

                if same:
                    pos += e - s
                    pc += 1
                else:
                    good = false
        else if op == 9:
            let jb = vm.jslot.length()
            let r = run(var vm, b, pos)

            if a == 0:
                if r >= 0:
                    pc = c
                else:
                    good = false
            else:
                if r >= 0:
                    undo_to(var vm, jb)
                    good = false
                else:
                    pc = c
        else if op == 10:
            while vm.spc.length() > sbase:
                vm.spc.pop()
                vm.spos.pop()
                vm.sj.pop()

            return pos

        if not good:
            if vm.spc.length() == sbase:
                undo_to(var vm, j0)
                return -1

            pc = vm.spc.pop().get()
            pos = vm.spos.pop().get()

            let jl = vm.sj.pop().get()
            undo_to(var vm, jl)

    return -1

// Finds the leftmost match starting at or after `from`. On success the
// slots hold the captures and mstart/mend the span.
fn search(var vm: Vm, from: Int) Bool:
    var s = from

    while s <= vm.n:
        for k in 0..vm.slots.length():
            vm.slots[k] = -1
        vm.jslot = List[Int]()
        vm.jold = List[Int]()
        vm.spc = List[Int]()
        vm.spos = List[Int]()
        vm.sj = List[Int]()

        let e = run(var vm, 0, s)

        if e >= 0:
            vm.slots[0] = s
            vm.slots[1] = e
            vm.mstart = s
            vm.mend = e
            return true

        if vm.full:
            return false

        s += 1

    return false

fn find_all(var vm: Vm) List[Mt]:
    var out = List[Mt]()
    var pos = 0

    while pos <= vm.n:
        if not search(var vm, pos):
            break

        let s = vm.mstart
        let e = vm.mend
        out.append(Mt(s, e, vm.slots.clone()))

        if e > s:
            pos = e
        else:
            pos = e + 1

    return out

// ---------------------------------------------------------------
// Output helpers
// ---------------------------------------------------------------
fn put(var ob: BytesBuilder, s: String) Unit:
    ob.append_bytes(s.as_bytes())

fn err_line(msg: String) Bytes:
    return "error: {msg}\n".as_bytes()

fn quote_range(var ob: BytesBuilder, src: Bytes, s: Int, e: Int) Unit:
    let hd = "0123456789abcdef".as_bytes()
    put(var ob, "\"")

    for i in s..e:
        let c = src.get(i).to_int()

        if c == 92:
            put(var ob, "\\\\")
        else if c == 34:
            put(var ob, "\\\"")
        else if c == 10:
            put(var ob, "\\n")
        else if c == 9:
            put(var ob, "\\t")
        else if c == 13:
            put(var ob, "\\r")
        else if c >= 32 and c <= 126:
            ob.append(src.get(i))
        else:
            put(var ob, "\\x")
            ob.append(hd.get(c / 16))
            ob.append(hd.get(c % 16))

    put(var ob, "\"")

fn append_range(var ob: BytesBuilder, src: Bytes, s: Int, e: Int) Unit:
    for i in s..e:
        ob.append(src.get(i))

fn name_for(vm: Vm, g: Int) String:
    for k in 0..vm.names.length():
        if vm.name_nums[k] == g:
            return vm.names[k].clone()
    return ""

// Prints one line per group 0..ngroups with the given capture array.
fn put_groups(var ob: BytesBuilder, vm: Vm, caps: List[Int]) Unit:
    for g in 0..vm.ngroups + 1:
        var label = "{g}"

        if g > 0:
            let nm = name_for(vm, g)
            if nm != "":
                label = "{g} ({nm})"

        let s = caps[2 * g]
        let e = caps[2 * g + 1]

        if s >= 0 and e >= 0:
            put(var ob, "{label}: {s}..{e} ")
            quote_range(var ob, vm.subj, s, e)
            put(var ob, "\n")
        else:
            put(var ob, "{label}: unset\n")

fn append_group(var ob: BytesBuilder, vm: Vm, caps: List[Int], g: Int) Unit:
    let s = caps[2 * g]
    let e = caps[2 * g + 1]
    if s >= 0 and e >= 0:
        append_range(var ob, vm.subj, s, e)

// Expands a replacement for one match. Returns false on a bad replacement.
fn expand(var ob: BytesBuilder, vm: Vm, rep: Bytes, caps: List[Int]) Bool:
    var i = 0
    let n = rep.length()

    while i < n:
        let c = rep.get(i).to_int()

        if c != 36:
            ob.append(rep.get(i))
            i += 1
        else if i + 1 >= n:
            ob.append(rep.get(i))
            i += 1
        else:
            let d = rep.get(i + 1).to_int()

            if is_digit(d):
                let g = d - 48
                if g > vm.ngroups:
                    return false

                append_group(var ob, vm, caps, g)
                i += 2
            else if d == 36:
                ob.append(rep.get(i))
                i += 2
            else if d == 123:
                var j = i + 2
                while j < n and rep.get(j).to_int() != 125:
                    j += 1
                if j >= n:
                    return false

                let name = rep.decode_utf8_range(i + 2, j).get("")
                var g = -1
                for k in 0..vm.names.length():
                    if vm.names[k] == name:
                        g = vm.name_nums[k]
                if g < 0:
                    return false

                append_group(var ob, vm, caps, g)
                i = j + 1
            else:
                ob.append(rep.get(i))
                i += 1

    return true

// ---------------------------------------------------------------
// Input unescaping (subject and replacement fields)
// ---------------------------------------------------------------
fn unesc_ok(b: Bytes) Bool:
    var i = 0
    let n = b.length()

    while i < n:
        if b.get(i).to_int() == 92:
            if i + 1 >= n:
                return false

            let d = b.get(i + 1).to_int()

            if d == 110 or d == 116 or d == 92:
                i += 2
            else if d == 120:
                if i + 3 >= n:
                    return false
                if (
                    hexval(b.get(i + 2).to_int()) < 0
                    or hexval(b.get(i + 3).to_int()) < 0
                ):
                    return false

                i += 4
            else:
                return false
        else:
            i += 1

    return true

fn unescape(b: Bytes) Bytes:
    var out = BytesBuilder()
    var i = 0
    let n = b.length()

    while i < n:
        if b.get(i).to_int() == 92:
            let d = b.get(i + 1).to_int()

            if d == 110:
                out.append(u8(10))
                i += 2
            else if d == 116:
                out.append(u8(9))
                i += 2
            else if d == 92:
                out.append(u8(92))
                i += 2
            else:
                let v = (
                    hexval(b.get(i + 2).to_int()) * 16
                    + hexval(b.get(i + 3).to_int())
                )
                out.append(u8(v))
                i += 4
        else:
            out.append(b.get(i))
            i += 1

    return out.build()

// ---------------------------------------------------------------
// Command handling
// ---------------------------------------------------------------
fn handle(line: Bytes) Bytes:
    let f = line.split("\t".as_bytes())
    let name = f[0].decode_utf8().get("")
    let known = (
        name == "test"
        or name == "match"
        or name == "full"
        or name == "find-all"
        or name == "split"
        or name == "replace"
    )
    let want = if name == "replace": 4 else: 3
    if not known or f.length() != want:
        return err_line("bad command")
    if not unesc_ok(f[2]):
        return err_line("bad command")
    if name == "replace" and not unesc_ok(f[3]):
        return err_line("bad command")

    let subject = unescape(f[2])
    var vm = build(f[1].clone(), name == "full")
    if vm.err != "":
        return err_line(vm.err)

    vm.n = subject.length()
    vm.subj = subject

    var ob = BytesBuilder()

    if name == "test":
        if search(var vm, 0):
            put(var ob, "true\n")
        else:
            put(var ob, "false\n")
    else if name == "match" or name == "full":
        if search(var vm, 0):
            put_groups(var ob, vm, vm.slots)
        else:
            put(var ob, "no match\n")
    else if name == "find-all":
        let ms = find_all(var vm)

        for m in ms:
            put(var ob, "{m.s}..{m.e} ")
            quote_range(var ob, vm.subj, m.s, m.e)
            put(var ob, "\n")

        put(var ob, "({ms.length()} matches)\n")
    else if name == "split":
        let ms = find_all(var vm)
        var prev = 0
        var count = 0

        for m in ms:
            if m.e > m.s:
                quote_range(var ob, vm.subj, prev, m.s)
                put(var ob, "\n")
                count += 1
                prev = m.e

        quote_range(var ob, vm.subj, prev, vm.n)
        put(var ob, "\n")
        count += 1
        put(var ob, "({count} pieces)\n")
    else:
        let rep = unescape(f[3])
        let ms = find_all(var vm)
        var rb = BytesBuilder()
        var prev = 0

        for m in ms:
            append_range(var rb, vm.subj, prev, m.s)
            if not expand(var rb, vm, rep, m.caps):
                return err_line("bad replacement")

            prev = m.e

        append_range(var rb, vm.subj, prev, vm.n)

        let res = rb.build()
        quote_range(var ob, res, 0, res.length())
        put(var ob, "\n")

    return ob.build()

fn read_all() Bytes!:
    var buf = BytesBuilder()
    for chunk in stdin():
        buf.append_bytes(chunk)
    return ok(buf.build())

export fn main() Int:
    let input = read_all().get()
    var out = BytesBuilder()
    for line in input.split("\n".as_bytes()):
        if line.length() > 0:
            out.append_bytes(handle(line))
    stdout_bytes().write(out.build()).get()
    return 0
