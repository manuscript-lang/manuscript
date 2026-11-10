// Backtracking regular-expression engine and line-based command driver.
// Strings are handled as lists of byte values (0-255); output is always ASCII.
import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

C_TAB := 9
C_NL := 10
C_CR := 13
C_DQUOTE := 34
C_DOLLAR := 36
C_LPAREN := 40
C_RPAREN := 41
C_STAR := 42
C_PLUS := 43
C_COMMA := 44
C_COLON := 58
C_DASH := 45
C_DOT := 46
C_ZERO := 48
C_BANG := 33
C_LT := 60
C_EQ := 61
C_GT := 62
C_QMARK := 63
C_LBRACK := 91
C_BS := 92
C_RBRACK := 93
C_CARET := 94
C_UNDER := 95
C_LBRACE := 123
C_PIPE := 124
C_RBRACE := 125
C_b := 98
C_B := 66
C_d := 100
C_D := 68
C_i := 105
C_k := 107
C_m := 109
C_n := 110
C_r := 114
C_s := 115
C_S := 83
C_t := 116
C_w := 119
C_W := 87
C_x := 120
PRINTABLE := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz\{|\}~"
HEX := "0123456789abcdef"
COMMANDS := ["test", "match", "full", "find-all", "split", "replace"]
// Instruction opcodes for the matcher.
OP_CLASS := 0  // a: class index; consume one byte in the class
OP_SPLIT := 1  // a: first choice, b: second choice (backtrack point)
OP_JMP := 2  // a: target
OP_OPEN := 3  // a: register; store the current position
OP_CLOSE := 4  // a: group number, b: register holding the group start
OP_CHECK := 5  // a: register; if no progress since OP_OPEN, jump to b
OP_ASSERT := 6  // a: assertion kind, b: multiline flag
OP_BREF := 7  // a: group number, b: case-insensitive flag
OP_LOOK := 8  // a: 1 for negative, b: continuation after the body
OP_LOOKEND := 9  // end of a lookahead body
OP_MATCH := 10  // overall success
// AST node kinds.
K_EMPTY := 0
K_CLASS := 1  // a: class index
K_SEQ := 2  // kids
K_ALT := 3  // kids
K_GROUP := 4  // a: group number (0 = non-capturing); kids[0]
K_REPEAT := 5  // a: min, b: max (-1 = unbounded), c: lazy flag; kids[0]
K_ASSERT := 6  // a: 0 ^, 1 $, 2 \b, 3 \B; b: multiline flag
K_BREF := 7  // a: group number, b: case-insensitive flag
K_NBREF := 8  // name: group name, resolved after parsing
K_LOOK := 9  // a: 1 for negative; kids[0]

type PErr:
    msg: String

impl Error for PErr:
    fn message() String:
        return self.msg.clone()

type Node:
    kind: Int
    a: Int = 0
    b: Int = 0
    c: Int = 0
    name: String = ""
    kids: List[Int] = List[Int]()

type Member:
    is_set: Bool
    value: Int
    bits: List[Bool]

type Brace:
    valid: Bool
    lo: Int
    hi: Int
    end: Int

type Parser:
    src: List[Int]
    pos: Int
    icase: Bool
    multi: Bool
    dotall: Bool
    names: List[String]
    nodes: List[Node]
    classes: List[List[Bool]]
    root: Int

type Ins:
    op: Int
    a: Int = 0
    b: Int = 0

type Gen:
    code: List[Ins]
    nregs: Int
    nodes: List[Node]

type Prog:
    code: List[Ins]
    classes: List[List[Bool]]
    nregs: Int
    names: List[String]

fn at(src: List[Int], i: Int) Int:
    if i < 0 or i >= src.length():
        return -1

    return src[i]

fn is_digit(c: Int) Bool:
    return c >= C_ZERO and c <= C_ZERO + 9

fn is_alpha(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_word_byte(c: Int) Bool:
    return is_alpha(c) or is_digit(c) or c == C_UNDER

fn is_space_byte(c: Int) Bool:
    return c == 32 or (c >= C_TAB and c <= C_CR) or c == 11 or c == 12

fn lower(c: Int) Int:
    if c >= 65 and c <= 90:
        return c + 32

    return c

fn fold(c: Int, icase: Bool) Int:
    if icase:
        return lower(c)

    return c

fn hex_value(c: Int) Int:
    if is_digit(c):
        return c - C_ZERO
    if c >= 97 and c <= 102:
        return c - 87
    if c >= 65 and c <= 70:
        return c - 55

    return -1

fn printable(c: Int) String:
    return PRINTABLE.get(c - 32)

fn to_flag(v: Bool) Int:
    if v:
        return 1

    return 0

fn grow(v: Int, digit: Int) Int:
    if v >= 100000:
        return v

    return v * 10 + digit - C_ZERO

fn empty_set() List[Bool]:
    var bits = List[Bool]()
    for _i in 0..256:
        bits.append(false)
    return bits

fn fold_case(var bits: List[Bool]) Unit:
    for b in 65..91:
        if bits[b] or bits[b + 32]:
            bits.set(b, true)
            bits.set(b + 32, true)

fn negate_set(var bits: List[Bool]) Unit:
    for b in 0..256:
        bits.set(b, not bits[b])

fn shorthand_set(letter: Int) List[Bool]:
    kind := lower(letter)
    negate := kind != letter
    var bits = empty_set()

    for b in 0..256:
        var inside = false

        if kind == C_d:
            inside = is_digit(b)
        else if kind == C_w:
            inside = is_word_byte(b)
        else:
            inside = is_space_byte(b)

        bits.set(b, inside != negate)

    return bits

fn is_shorthand(c: Int) Bool:
    return c == C_d or c == C_D or c == C_w or c == C_W or c == C_s or c == C_S

fn is_escape_char(c: Int) Bool:
    return c == C_n or c == C_t or c == C_r or c == C_x

// Scans `{n}`, `{n,}` or `{n,m}` starting at the `{` at index `at_index`.
fn scan_brace(src: List[Int], at_index: Int) Brace:
    var i = at_index + 1
    var lo = 0
    var digits = 0

    while is_digit(at(src, i)):
        lo = grow(lo, at(src, i))
        digits += 1
        i += 1

    if digits == 0:
        return Brace(valid: false, lo: 0, hi: 0, end: 0)

    var hi = lo

    if at(src, i) == C_COMMA:
        i += 1
        hi = -1

        while is_digit(at(src, i)):
            if hi < 0:
                hi = 0
            hi = grow(hi, at(src, i))
            i += 1

    if at(src, i) != C_RBRACE:
        return Brace(valid: false, lo: 0, hi: 0, end: 0)

    return Brace(valid: true, lo: lo, hi: hi, end: i + 1)

fn undo_push(var stack: List[Int], reg: Int, old: Int) Unit:
    stack.append(1)
    stack.append(reg)
    stack.append(old)

impl Parser:
    fn peek() Int:
        return at(self.src, self.pos)

    fn peek_at(k: Int) Int:
        return at(self.src, self.pos + k)

    var fn add(n: Node) Int:
        self.nodes.append(n)
        return self.nodes.length() - 1

    var fn class_node(bits: List[Bool]) Int:
        self.classes.append(bits)
        return self.add(Node(kind: K_CLASS, a: self.classes.length() - 1))

    var fn literal(c: Int) Int:
        var bits = empty_set()
        bits.set(c, true)
        if self.icase:
            fold_case(var bits)
        return self.class_node(bits)

    var fn read_flags() Unit:
        // A leading `(?flags)` sets the global flags; anywhere else it is a bad group.
        src := self.src
        if at(src, 0) != C_LPAREN or at(src, 1) != C_QMARK:
            return

        var i = 2
        while at(src, i) == C_i or at(src, i) == C_m or at(src, i) == C_s:
            i += 1
        if i == 2 or at(src, i) != C_RPAREN:
            return

        for k in 2..i:
            if src[k] == C_i:
                self.icase = true
            else if src[k] == C_m:
                self.multi = true
            else:
                self.dotall = true

        self.pos = i + 1

    var fn read_name() String:
        var name = ""
        if not (is_alpha(self.peek()) or self.peek() == C_UNDER):
            return ""

        while is_word_byte(self.peek()):
            ch := printable(self.peek())
            name = "{name}{ch}"
            self.pos += 1

        return name

    var fn hex_byte() Result[Int, PErr]:
        hi := hex_value(self.peek())
        lo := hex_value(self.peek_at(1))
        if hi < 0 or lo < 0:
            return error(PErr(msg: "bad escape"))

        self.pos += 2
        return ok(hi * 16 + lo)

    var fn parse_alt() Result[Int, PErr]:
        var alts = List[Int]()

        while true:
            seq := try self.parse_seq()
            alts.append(seq)
            if self.peek() != C_PIPE:
                break

            self.pos += 1

        if alts.length() == 1:
            return ok(alts[0])

        return ok(self.add(Node(kind: K_ALT, kids: alts)))

    var fn parse_seq() Result[Int, PErr]:
        var items = List[Int]()

        while true:
            c := self.peek()
            if c < 0 or c == C_PIPE or c == C_RPAREN:
                break

            atom := try self.parse_atom()
            quantified := try self.parse_quant(atom)
            items.append(quantified)

        if items.length() == 1:
            return ok(items[0])
        if items.length() == 0:
            return ok(self.add(Node(kind: K_EMPTY)))

        return ok(self.add(Node(kind: K_SEQ, kids: items)))

    var fn parse_atom() Result[Int, PErr]:
        c := self.peek()
        if c == C_LPAREN:
            return self.parse_group()
        if c == C_LBRACK:
            return self.parse_class()
        if c == C_BS:
            return self.parse_escape()
        if c == C_STAR or c == C_PLUS or c == C_QMARK:
            return error(PErr(msg: "nothing to repeat"))

        self.pos += 1

        if c == C_DOT:
            var bits = empty_set()
            for b in 0..256:
                bits.set(b, self.dotall or b != C_NL)
            return ok(self.class_node(bits))

        if c == C_CARET:
            return ok(self.add(Node(kind: K_ASSERT, a: 0, b: to_flag(self.multi))))
        if c == C_DOLLAR:
            return ok(self.add(Node(kind: K_ASSERT, a: 1, b: to_flag(self.multi))))

        return ok(self.literal(c))

    var fn is_quantifier_here() Bool:
        c := self.peek()
        if c == C_STAR or c == C_PLUS or c == C_QMARK:
            return true

        return c == C_LBRACE and scan_brace(self.src, self.pos).valid

    var fn parse_quant(atom: Int) Result[Int, PErr]:
        c := self.peek()
        brace := scan_brace(self.src, self.pos)
        braced := c == C_LBRACE and brace.valid
        if not (braced or c == C_STAR or c == C_PLUS or c == C_QMARK):
            return ok(atom)

        kind := self.nodes[atom].kind
        if kind == K_ASSERT or kind == K_LOOK:
            return error(PErr(msg: "nothing to repeat"))

        var lo = 0
        var hi = -1

        if braced:
            if (
                brace.lo > 1000
                or brace.hi > 1000
                or (brace.hi >= 0 and brace.lo > brace.hi)
            ):
                return error(PErr(msg: "bad repeat"))

            lo = brace.lo
            hi = brace.hi
            self.pos = brace.end
        else if c == C_PLUS:
            lo = 1
            self.pos += 1
        else if c == C_QMARK:
            hi = 1
            self.pos += 1
        else:
            self.pos += 1

        var lazy = 0

        if self.peek() == C_QMARK:
            lazy = 1
            self.pos += 1

        if self.is_quantifier_here():
            return error(PErr(msg: "nothing to repeat"))

        return ok(self.add(Node(kind: K_REPEAT, a: lo, b: hi, c: lazy, kids: [atom])))

    var fn parse_escape() Result[Int, PErr]:
        // The backslash is at self.pos.
        if self.pos + 1 >= self.src.length():
            return error(PErr(msg: "bad escape"))

        e := self.src[self.pos + 1]
        self.pos += 2

        if is_shorthand(e):
            idx := self.class_node(shorthand_set(e))
            return ok(idx)

        if e == C_b:
            return ok(self.add(Node(kind: K_ASSERT, a: 2)))
        if e == C_B:
            return ok(self.add(Node(kind: K_ASSERT, a: 3)))
        if e >= 49 and e <= 57:
            return ok(
                self.add(
                    Node(
                        kind: K_BREF, a: e - C_ZERO, b: to_flag(self.icase)
                    )
                )
            )

        if e == C_k:
            if self.peek() != C_LT:
                return error(PErr(msg: "bad escape"))

            self.pos += 1

            nm := self.read_name()
            if nm == "" or self.peek() != C_GT:
                return error(PErr(msg: "bad escape"))

            self.pos += 1
            return ok(self.add(Node(kind: K_NBREF, name: nm, b: to_flag(self.icase))))

        if e == C_n:
            return ok(self.literal(C_NL))
        if e == C_t:
            return ok(self.literal(C_TAB))
        if e == C_r:
            return ok(self.literal(C_CR))

        if e == C_x:
            v := try self.hex_byte()
            return ok(self.literal(v))

        if is_alpha(e) or is_digit(e) or e >= 128:
            return error(PErr(msg: "bad escape"))

        return ok(self.literal(e))

    // Reads one class member: a byte, or a shorthand set.
    var fn class_member() Result[Member, PErr]:
        c := self.peek()

        if c != C_BS:
            self.pos += 1
            return ok(Member(is_set: false, value: c, bits: List[Bool]()))

        e := self.peek_at(1)
        if e < 0:
            return error(PErr(msg: "bad escape"))

        self.pos += 2
        if is_shorthand(e):
            return ok(Member(is_set: true, value: 0, bits: shorthand_set(e)))
        if e == C_n:
            return ok(Member(is_set: false, value: C_NL, bits: List[Bool]()))
        if e == C_t:
            return ok(Member(is_set: false, value: C_TAB, bits: List[Bool]()))
        if e == C_r:
            return ok(Member(is_set: false, value: C_CR, bits: List[Bool]()))

        if e == C_x:
            v := try self.hex_byte()
            return ok(Member(is_set: false, value: v, bits: List[Bool]()))

        if is_alpha(e) or is_digit(e) or e >= 128:
            return error(PErr(msg: "bad escape"))

        return ok(Member(is_set: false, value: e, bits: List[Bool]()))

    var fn parse_class() Result[Int, PErr]:
        self.pos += 1

        var negate = false

        if self.peek() == C_CARET:
            negate = true
            self.pos += 1

        var bits = empty_set()
        var first = true

        while true:
            if self.peek() < 0:
                return error(PErr(msg: "unterminated class"))

            if self.peek() == C_RBRACK and not first:
                self.pos += 1
                break

            first = false

            m := try self.class_member()
            after := self.peek_at(1)

            if self.peek() == C_DASH and after >= 0 and after != C_RBRACK:
                self.pos += 1

                hi := try self.class_member()
                if m.is_set or hi.is_set or hi.value < m.value:
                    return error(PErr(msg: "bad range"))

                for b in m.value..hi.value + 1:
                    bits.set(b, true)
            else if m.is_set:
                for b in 0..256:
                    if m.bits[b]:
                        bits.set(b, true)
            else:
                bits.set(m.value, true)

        if self.icase:
            fold_case(var bits)
        if negate:
            negate_set(var bits)
        return ok(self.class_node(bits))

    var fn parse_group() Result[Int, PErr]:
        self.pos += 1

        if self.peek() != C_QMARK:
            g := self.names.length()
            self.names.append("")

            body := try self.parse_alt()
            try self.close_paren()
            return ok(self.add(Node(kind: K_GROUP, a: g, kids: [body])))

        c2 := self.peek_at(1)

        if c2 == C_COLON:
            self.pos += 2

            body := try self.parse_alt()
            try self.close_paren()
            return ok(self.add(Node(kind: K_GROUP, a: 0, kids: [body])))

        if c2 == C_EQ or c2 == C_BANG:
            self.pos += 2

            body := try self.parse_alt()
            try self.close_paren()
            return ok(
                self.add(
                    Node(
                        kind: K_LOOK, a: to_flag(c2 == C_BANG), kids: [body]
                    )
                )
            )

        if c2 == C_LT:
            self.pos += 2

            nm := self.read_name()
            if nm == "" or self.peek() != C_GT:
                return error(PErr(msg: "bad group"))

            self.pos += 1
            if self.names.contains(nm):
                return error(PErr(msg: "duplicate group name"))

            g := self.names.length()
            self.names.append(nm)

            body := try self.parse_alt()
            try self.close_paren()
            return ok(self.add(Node(kind: K_GROUP, a: g, kids: [body])))

        return error(PErr(msg: "bad group"))

    var fn close_paren() Result[Unit, PErr]:
        if self.peek() != C_RPAREN:
            return error(PErr(msg: "unmatched ("))

        self.pos += 1
        return ok(unit)

    // Replaces named back-references by numbers and checks every reference.
    var fn resolve_refs() Result[Unit, PErr]:
        ngroups := self.names.length() - 1

        for i in 0..self.nodes.length():
            node := self.nodes[i].clone()
            if node.kind == K_BREF and node.a > ngroups:
                return error(PErr(msg: "bad backreference"))

            if node.kind == K_NBREF:
                if g := self.names.index_of(node.name):
                    self.nodes.set(i, Node(kind: K_BREF, a: g, b: node.b))
                else:
                    return error(PErr(msg: "bad backreference"))

        return ok(unit)

impl Gen:
    var fn emit(op: Int, a: Int, b: Int) Int:
        self.code.append(Ins(op: op, a: a, b: b))
        return self.code.length() - 1

    var fn new_reg() Int:
        self.nregs += 1
        return self.nregs - 1

    var fn set_targets(at: Int, a: Int, b: Int) Unit:
        old := self.code[at]
        self.code.set(at, Ins(op: old.op, a: a, b: b))

    var fn gen(id: Int) Unit:
        node := self.nodes[id].clone()

        if node.kind == K_CLASS:
            self.emit(OP_CLASS, node.a, 0)
        else if node.kind == K_SEQ:
            for kid in node.kids:
                self.gen(kid)
        else if node.kind == K_ALT:
            self.gen_alt(node.kids)
        else if node.kind == K_GROUP:
            if node.a == 0:
                self.gen(node.kids[0])
            else:
                tmp := self.new_reg()
                self.emit(OP_OPEN, tmp, 0)
                self.gen(node.kids[0])
                self.emit(OP_CLOSE, node.a, tmp)
        else if node.kind == K_REPEAT:
            self.gen_repeat(node)
        else if node.kind == K_ASSERT:
            self.emit(OP_ASSERT, node.a, node.b)
        else if node.kind == K_BREF:
            self.emit(OP_BREF, node.a, node.b)
        else if node.kind == K_LOOK:
            look := self.emit(OP_LOOK, node.a, 0)
            self.gen(node.kids[0])
            self.emit(OP_LOOKEND, 0, 0)

            here := self.code.length()
            self.set_targets(look, node.a, here)

    var fn gen_alt(alts: List[Int]) Unit:
        var jumps = List[Int]()

        for i in 0..alts.length() - 1:
            split := self.emit(OP_SPLIT, 0, 0)
            self.gen(alts[i])
            jumps.append(self.emit(OP_JMP, 0, 0))

            next := self.code.length()
            self.set_targets(split, split + 1, next)

        self.gen(alts[alts.length() - 1])

        end := self.code.length()
        for j in jumps:
            self.set_targets(j, end, 0)

    // Each optional iteration is a SPLIT, then OPEN/body/CHECK; an iteration that
    // consumed nothing ends the loop (CHECK jumps to the exit).
    var fn gen_repeat(node: Node) Unit:
        body := node.kids[0]
        lazy := node.c == 1
        for _i in 0..node.a:
            self.gen(body)

        if node.b < 0:
            top := self.emit(OP_SPLIT, 0, 0)
            reg := self.new_reg()
            self.emit(OP_OPEN, reg, 0)
            self.gen(body)

            check := self.emit(OP_CHECK, reg, 0)
            self.emit(OP_JMP, top, 0)

            end := self.code.length()

            if lazy:
                self.set_targets(top, end, top + 1)
            else:
                self.set_targets(top, top + 1, end)

            self.set_targets(check, reg, end)
        else:
            var splits = List[Int]()
            var checks = List[Int]()

            for _i in 0..node.b - node.a:
                split := self.emit(OP_SPLIT, 0, 0)
                splits.append(split)

                reg := self.new_reg()
                self.emit(OP_OPEN, reg, 0)
                self.gen(body)
                checks.append(self.emit(OP_CHECK, reg, 0))

            end := self.code.length()

            for split in splits:
                if lazy:
                    self.set_targets(split, end, split + 1)
                else:
                    self.set_targets(split, split + 1, end)

            for check in checks:
                self.set_targets(check, self.code[check].a, end)

fn compile_prog(p: Parser) Prog:
    var g = Gen(code: List[Ins](), nregs: 2 * p.names.length(), nodes: p.nodes.clone())
    tmp := g.new_reg()
    g.emit(OP_OPEN, tmp, 0)
    g.gen(p.root)
    g.emit(OP_CLOSE, 0, tmp)
    g.emit(OP_MATCH, 0, 0)
    return Prog(
        code: g.code.clone(), classes: p.classes.clone(), nregs: g.nregs,
        names: p.names.clone()
    )

fn parse_pattern(src: List[Int]) Result[Prog, PErr]:
    var p = Parser(
        src: src.clone(), pos: 0, icase: false, multi: false, dotall: false,
        names: [""], nodes: List[Node](), classes: List[List[Bool]](), root: 0
    )
    p.read_flags()

    root := try p.parse_alt()
    p.root = root
    if p.pos < src.length():
        return error(PErr(msg: "unmatched )"))

    try p.resolve_refs()
    return ok(compile_prog(p))

fn word_at(subject: List[Int], i: Int) Bool:
    c := at(subject, i)
    return c >= 0 and is_word_byte(c)

fn assertion_holds(kind: Int, multi: Bool, subject: List[Int], pos: Int) Bool:
    n := subject.length()

    if kind == 0:
        if pos == 0:
            return true

        return multi and subject[pos - 1] == C_NL

    if kind == 1:
        if pos == n:
            return true

        return multi and subject[pos] == C_NL

    boundary := word_at(subject, pos - 1) != word_at(subject, pos)
    if kind == 2:
        return boundary

    return not boundary

fn backref_matches(subject: List[Int], start: Int, pos: Int, len: Int, icase: Bool) Bool:
    if pos + len > subject.length():
        return false

    for k in 0..len:
        if fold(subject[start + k], icase) != fold(subject[pos + k], icase):
            return false
    return true

// Runs the program from `start_pc` at `start_pos`. Returns the end position on success
// (regs hold the captures), or -1 with regs restored to their entry state.
fn exec(
    prog: Prog,
    subject: List[Int],
    start_pc: Int,
    start_pos: Int,
    var regs: List[Int],
    full: Bool
) Int:
    var stack = List[Int]()
    var pc = start_pc
    var pos = start_pos
    n := subject.length()

    while true:
        ins := prog.code[pc]
        var ok = true

        if ins.op == OP_CLASS:
            if pos >= n:
                ok = false
            else if prog.classes[ins.a][subject[pos]]:
                pos += 1
                pc += 1
            else:
                ok = false
        else if ins.op == OP_SPLIT:
            stack.append(0)
            stack.append(ins.b)
            stack.append(pos)
            pc = ins.a
        else if ins.op == OP_JMP:
            pc = ins.a
        else if ins.op == OP_OPEN:
            undo_push(var stack, ins.a, regs[ins.a])
            regs[ins.a] = pos
            pc += 1
        else if ins.op == OP_CLOSE:
            s := 2 * ins.a
            undo_push(var stack, s, regs[s])
            undo_push(var stack, s + 1, regs[s + 1])
            regs[s] = regs[ins.b]
            regs[s + 1] = pos
            pc += 1
        else if ins.op == OP_CHECK:
            if regs[ins.a] == pos:
                pc = ins.b
            else:
                pc += 1
        else if ins.op == OP_ASSERT:
            if assertion_holds(ins.a, ins.b == 1, subject, pos):
                pc += 1
            else:
                ok = false
        else if ins.op == OP_BREF:
            s := regs[2 * ins.a]
            e := regs[2 * ins.a + 1]

            if s < 0 or e < 0:
                ok = false
            else if backref_matches(subject, s, pos, e - s, ins.b == 1):
                pos += e - s
                pc += 1
            else:
                ok = false
        else if ins.op == OP_LOOK:
            before := regs.clone()
            r := exec(prog, subject, pc + 1, pos, var regs, false)

            if ins.a == 0:
                if r < 0:
                    ok = false
                else:
                    for i in 0..regs.length():
                        if regs[i] != before[i]:
                            undo_push(var stack, i, before[i])
                    pc = ins.b
            else if r >= 0:
                for i in 0..regs.length():
                    regs[i] = before[i]
                ok = false
            else:
                pc = ins.b
        else if ins.op == OP_LOOKEND:
            return pos
        else if ins.op == OP_MATCH:
            if full and pos != n:
                ok = false
            else:
                return pos

        if not ok:
            var resumed = false

            while not resumed:
                if stack.length() == 0:
                    return -1

                arg2 := stack.pop().get(0)
                arg1 := stack.pop().get(0)
                kind := stack.pop().get(0)

                if kind == 1:
                    regs[arg1] = arg2
                else:
                    pc = arg1
                    pos = arg2
                    resumed = true

fn fresh_regs(count: Int) List[Int]:
    var regs = List[Int]()
    for _i in 0..count:
        regs.append(-1)
    return regs

// Leftmost match at or after `from`; `full` only tries start 0 and requires the end of the subject.
fn search(prog: Prog, subject: List[Int], from: Int, full: Bool) Optional[List[Int]]:
    var start = from

    while start <= subject.length():
        var regs = fresh_regs(prog.nregs)
        if exec(prog, subject, 0, start, var regs, full) >= 0:
            return some(regs)
        if full:
            break

        start += 1

    return none

fn find_all(prog: Prog, subject: List[Int]) List[List[Int]]:
    var found = List[List[Int]]()
    var start = 0

    while start <= subject.length():
        if m := search(prog, subject, start, false):
            s := m[0]
            e := m[1]
            found.append(m)

            if e > s:
                start = e
            else:
                start = e + 1
        else:
            break

    return found

fn escape_byte(b: Int) String:
    if b == C_DQUOTE:
        return "\\\""
    if b == C_BS:
        return "\\\\"
    if b == C_NL:
        return "\\n"
    if b == C_TAB:
        return "\\t"
    if b == C_CR:
        return "\\r"
    if b < 32 or b > 126:
        return "\\x{HEX.get(b / 16)}{HEX.get(b % 16)}"

    return printable(b)

fn quoted(bytes: List[Int], from: Int, to: Int) String:
    var parts = List[String]()
    parts.append("\"")
    for i in from..to:
        parts.append(escape_byte(bytes[i]))
    parts.append("\"")
    return parts.join("")

fn match_line(subject: List[Int], m: List[Int]) String:
    q := quoted(subject, m[0], m[1])
    return "{m[0]}..{m[1]} {q}"

fn group_label(names: List[String], g: Int) String:
    if names[g] == "":
        return "{g}"

    return "{g} ({names[g]})"

fn group_lines(names: List[String], subject: List[Int], regs: List[Int]) List[String]:
    var lines = List[String]()

    for g in 0..names.length():
        label := group_label(names, g)
        s := regs[2 * g]
        e := regs[2 * g + 1]

        if e >= 0:
            q := quoted(subject, s, e)
            lines.append("{label}: {s}..{e} {q}")
        else:
            lines.append("{label}: unset")

    return lines

fn append_range(var out: List[Int], subject: List[Int], from: Int, to: Int) Unit:
    for i in from..to:
        out.append(subject[i])

// Appends one group's text (empty when unset).
fn append_group(var out: List[Int], subject: List[Int], regs: List[Int], g: Int) Unit:
    s := regs[2 * g]
    e := regs[2 * g + 1]
    if s >= 0 and e >= 0:
        append_range(var out, subject, s, e)

fn name_of(repl: List[Int], from: Int, to: Int) String:
    var name = ""

    for i in from..to:
        c := repl[i]
        if not (is_word_byte(c)):
            return ""

        ch := printable(c)
        name = "{name}{ch}"

    return name

// Expands the replacement template for one match. Returns false on a bad reference.
fn expand_into(
    var out: List[Int], repl: List[Int], subject: List[Int], regs: List[Int],
    names: List[String]
) Bool:
    n := repl.length()
    var i = 0

    while i < n:
        c := repl[i]

        if c != C_DOLLAR or i + 1 >= n:
            out.append(c)
            i += 1
        else if is_digit(repl[i + 1]):
            g := repl[i + 1] - C_ZERO
            if g >= names.length():
                return false

            append_group(var out, subject, regs, g)
            i += 2
        else if repl[i + 1] == C_DOLLAR:
            out.append(C_DOLLAR)
            i += 2
        else if repl[i + 1] == C_LBRACE:
            var close = i + 2
            while at(repl, close) >= 0 and at(repl, close) != C_RBRACE:
                close += 1
            if at(repl, close) != C_RBRACE:
                return false

            nm := name_of(repl, i + 2, close)
            if nm == "":
                return false

            if g := names.index_of(nm):
                append_group(var out, subject, regs, g)
            else:
                return false

            i = close + 1
        else:
            out.append(C_DOLLAR)
            i += 1

    return true

fn run_prog(cmd: String, prog: Prog, subject: List[Int], repl: List[Int]) List[String]:
    if cmd == "test":
        if search(prog, subject, 0, false).is_some():
            return ["true"]

        return ["false"]

    if cmd == "match" or cmd == "full":
        if m := search(prog, subject, 0, cmd == "full"):
            return group_lines(prog.names, subject, m)

        return ["no match"]

    if cmd == "find-all":
        found := find_all(prog, subject)
        var lines = List[String]()
        for m in found:
            lines.append(match_line(subject, m))
        lines.append("({found.length()} matches)")
        return lines

    if cmd == "split":
        var pieces = List[String]()
        var prev = 0
        var kept = 0

        for m in find_all(prog, subject):
            if m[0] != m[1]:
                pieces.append(quoted(subject, prev, m[0]))
                prev = m[1]
                kept += 1

        pieces.append(quoted(subject, prev, subject.length()))
        pieces.append("({kept + 1} pieces)")
        return pieces

    var out = List[Int]()
    var prev = 0

    for m in find_all(prog, subject):
        append_range(var out, subject, prev, m[0])
        if not expand_into(var out, repl, subject, m, prog.names):
            return ["error: bad replacement"]

        prev = m[1]

    append_range(var out, subject, prev, subject.length())
    return [quoted(out, 0, out.length())]

fn to_ints(text: String) List[Int]:
    var out = List[Int]()
    for b in text.to_bytes().values():
        out.append(b.to_int())
    return out

// Undoes the subject/replacement escapes; none on a malformed escape.
fn unescape(src: List[Int]) Optional[List[Int]]:
    var out = List[Int]()
    var i = 0

    while i < src.length():
        c := src[i]
        e := at(src, i + 1)

        if c != C_BS:
            out.append(c)
            i += 1
        else if e < 0:
            return none
        else if e == C_n:
            out.append(C_NL)
            i += 2
        else if e == C_t:
            out.append(C_TAB)
            i += 2
        else if e == C_BS:
            out.append(C_BS)
            i += 2
        else if (
            e == C_x
            and hex_value(at(src, i + 2)) >= 0
            and hex_value(at(src, i + 3)) >= 0
        ):
            out.append(hex_value(at(src, i + 2)) * 16 + hex_value(at(src, i + 3)))
            i += 4
        else:
            return none

    return some(out)

fn run_command(
    cmd: String,
    pattern: String,
    subject: List[Int],
    repl: List[Int]
) List[String]:
    compiled := parse_pattern(to_ints(pattern))

    if compiled.is_error():
        msg := compiled.err().message()
        return ["error: {msg}"]

    return run_prog(cmd, compiled.get(), subject, repl)

fn run_line(line: String) List[String]:
    fields := line.split("\t")
    cmd := fields[0]
    if not COMMANDS.contains(cmd):
        return ["error: bad command"]

    var want = 3
    if cmd == "replace":
        want = 4
    if fields.length() != want:
        return ["error: bad command"]

    if subject := unescape(to_ints(fields[2])):
        if cmd != "replace":
            return run_command(cmd, fields[1], subject, List[Int]())
        if repl := unescape(to_ints(fields[3])):
            return run_command(cmd, fields[1], subject, repl)

    return ["error: bad command"]

export fn main() Int:
    var out = List[String]()
    if lines := read_lines(stdin()):
        for line in lines:
            if line != "":
                for text in run_line(line):
                    out.append("{text}\n")
    stdout().write(out.join("")).get()
    return 0
