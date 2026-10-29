import {stdin, stdout} from "@std/io.ms"
import {read_lines} from "@std/streams.ms"
import {from_scalars} from "@std/string.ms"
import {bit_and, bit_not, bit_or, bit_xor, shift_left, shift_right} from "@std/math.ms"

let MEM_SIZE = 4096
let SP = 8
let MAX_LITERAL = 4294967295
let MAX_BUDGET = 10000000
let DEFAULT_BUDGET = 100000
let K_REG = 0
let K_IMM = 1
let K_MEM = 2
let OP_MOV = 0
let OP_ADD = 1
let OP_SUB = 2
let OP_MUL = 3
let OP_DIV = 4
let OP_MOD = 5
let OP_AND = 6
let OP_OR = 7
let OP_XOR = 8
let OP_SHL = 9
let OP_SHR = 10
let OP_SAR = 11
let OP_CMP = 12
let OP_NEG = 13
let OP_NOT = 14
let OP_INC = 15
let OP_DEC = 16
let OP_LEA = 17
let OP_PUSH = 18
let OP_POP = 19
let OP_JMP = 20
let OP_JE = 21
let OP_JNE = 22
let OP_JL = 23
let OP_JLE = 24
let OP_JG = 25
let OP_JGE = 26
let OP_CALL = 27
let OP_RET = 28
let OP_IN = 29
let OP_OUT = 30
let OP_OUTC = 31
let OP_HALT = 32
let OP_NOP = 33

type Failure:
    msg: String

impl Error for Failure:
    fn message() String:
        return self.msg.clone()

type Term:
    neg: Bool
    text: String
    reg: Int

type Arg:
    kind: Int
    reg: Int
    value: Int
    terms: List[Term]

type Stmt:
    line: Int
    is_instr: Bool
    code: Int
    args: List[Arg]
    addr: Int
    count: Int
    texts: List[String]
    is_space: Bool

type Instr:
    code: Int
    line: Int
    args: List[Arg]

type Program:
    instrs: List[Instr]
    mem: List[Int]
    budget: Int
    entry: Int

type Asm:
    labels: Map[String, Int]
    equs: Map[String, String]
    stmts: List[Stmt]
    text_count: Int
    data_size: Int
    in_data: Bool
    budget: Int
    entry: Int

type Machine:
    regs: List[Int]
    mem: List[Int]
    z: Bool
    l: Bool
    pc: Int
    steps: Int
    halted: Bool
    inputs: List[Int]
    in_pos: Int
    out: List[String]

type Scan:
    value: Int
    next: Int

type Word:
    word: String
    args: String

fn bad(msg: String) Failure:
    return Failure(msg: msg)

fn wrap(x: Int) Int:
    let u = bit_and(x, 4294967295)
    if u >= 2147483648:
        return u - 4294967296

    return u

fn unsigned(x: Int) Int:
    return bit_and(x, 4294967295)

fn ch(cs: List[String], i: Int) String:
    if i >= 0 and i < cs.length():
        return cs[i].clone()

    return ""

fn slice_chars(cs: List[String], start: Int, end: Int) String:
    var s = ""
    for i in start..end:
        s += cs[i]
    return s

fn is_in(c: String, set: String) Bool:
    return c != "" and set.contains(c)

fn is_letter(c: String) Bool:
    return is_in(c, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")

fn is_digit(c: String) Bool:
    return is_in(c, "0123456789")

fn is_ident(c: String) Bool:
    return is_letter(c) or is_digit(c) or c == "."

fn is_space(c: String) Bool:
    return c == " " or c == "\t"

fn skip_ws(cs: List[String], i: Int) Int:
    var j = i
    while is_space(ch(cs, j)):
        j += 1
    return j

fn digit_value(c: String) Int:
    let code = c.scalar_at(0)
    if code >= 48 and code <= 57:
        return code - 48
    if code >= 97 and code <= 102:
        return code - 87
    if code >= 65 and code <= 70:
        return code - 55

    return -1

fn is_identifier(text: String) Bool:
    let cs = text.chars()
    if not is_letter(ch(cs, 0)):
        return false

    for c in cs:
        if not is_ident(c):
            return false
    return true

fn reg_index(name: String) Int:
    let names = ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]
    for k in 0..names.length():
        if names[k] == name:
            return k
    return -1

fn op_code(name: String) Int:
    let names = [
        "mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr",
        "sar", "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je",
        "jne", "jl", "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt",
        "nop"
    ]
    for k in 0..names.length():
        if names[k] == name:
            return k
    if name == "jz":
        return OP_JE
    if name == "jnz":
        return OP_JNE

    return -1

fn op_arity(code: Int) Int:
    if code <= OP_CMP or code == OP_LEA:
        return 2
    if code == OP_RET or code == OP_HALT or code == OP_NOP:
        return 0

    return 1

# Operand classes allowed by the instruction shape, checked after the arity.
fn shape_ok(code: Int, args: List[Arg]) Bool:
    if args.length() == 0:
        return true

    let d = args[0].kind

    if args.length() == 2:
        if code == OP_MOV:
            if d == K_MEM:
                return args[1].kind != K_MEM

            return d == K_REG

        if code == OP_LEA:
            return d == K_REG and args[1].kind == K_MEM

        return d == K_REG

    if (code >= OP_NEG and code <= OP_DEC) or code == OP_POP or code == OP_IN:
        return d == K_REG
    if code == OP_PUSH or code == OP_OUT or code == OP_OUTC:
        return true

    return d == K_IMM

# Character-literal length at i ('c' or '\c'), or 0 when there is none.
fn char_lit_len(cs: List[String], i: Int) Int:
    if ch(cs, i) != "'":
        return 0

    if ch(cs, i + 1) == "\\":
        if ch(cs, i + 3) == "'":
            return 4

        return 0

    if ch(cs, i + 2) == "'":
        return 3

    return 0

fn escape_value(c: String) Int:
    if c == "n":
        return 10
    if c == "t":
        return 9
    if c == "0":
        return 0
    if c == "\\":
        return 92
    if c == "'":
        return 39
    if c == "\"":
        return 34

    return -1

fn ascii_value(c: String) Int:
    let code = c.scalar_at(0)
    if code < 128:
        return code

    return -1

fn char_lit_value(cs: List[String], i: Int) Int:
    if ch(cs, i + 1) == "\\":
        return escape_value(ch(cs, i + 2))

    return ascii_value(ch(cs, i + 1))

fn byte_values(s: String) List[Int]:
    var out = List[Int]()
    for b in s.to_bytes().values():
        out.append(b.to_int())
    return out

# Removes a `;` comment that is not inside a string or character literal.
fn strip_comment(line: String) String:
    let cs = line.chars()
    let n = cs.length()
    var i = 0

    while i < n:
        let c = cs[i]

        if c == "\"":
            i = skip_string(cs, i)
        else if char_lit_len(cs, i) > 0:
            i += char_lit_len(cs, i)
        else if c == ";":
            return slice_chars(cs, 0, i)
        else:
            i += 1

    return line

fn skip_string(cs: List[String], i: Int) Int:
    var j = i + 1

    while j < cs.length():
        if cs[j] == "\\":
            j += 2
        else if cs[j] == "\"":
            return j + 1
        else:
            j += 1

    return cs.length()

# Splits operands at commas outside brackets and character literals.
fn split_operands(text: String) List[String]:
    var parts = List[String]()
    if text == "":
        return parts

    let cs = text.chars()
    let n = cs.length()
    var cur = ""
    var depth = 0
    var i = 0

    while i < n:
        let c = cs[i]
        let len = char_lit_len(cs, i)

        if len > 0:
            cur += slice_chars(cs, i, i + len)
            i += len
        else if c == "[":
            depth += 1
            cur += c
            i += 1
        else if c == "]":
            if depth > 0:
                depth -= 1
            cur += c
            i += 1
        else if c == "," and depth == 0:
            parts.append(cur.trim().clone())
            cur = ""
            i += 1
        else:
            cur += c
            i += 1

    parts.append(cur.trim().clone())
    return parts

# Splits the inside of [...] into signed terms; register terms are marked by reg.
fn split_terms(inner: String) Result[List[Term], Failure]:
    let cs = inner.chars()
    let n = cs.length()
    var terms = List[Term]()
    var neg = false
    var have_sign = false
    var cur = ""
    var i = 0

    while i < n:
        let c = cs[i]
        let len = char_lit_len(cs, i)

        if len > 0:
            cur += slice_chars(cs, i, i + len)
            i += len
        else if c == "+" or c == "-":
            let seg = cur.trim().clone()

            if seg == "":
                if have_sign:
                    return error(bad("empty term"))
            else:
                terms.append(Term(neg: neg, text: seg.clone(), reg: reg_index(seg)))

            neg = c == "-"
            have_sign = true
            cur = ""
            i += 1
        else:
            cur += c
            i += 1

    let last = cur.trim().clone()
    if last == "":
        return error(bad("empty term"))

    terms.append(Term(neg: neg, text: last.clone(), reg: reg_index(last)))
    return ok(terms)

fn classify(text: String) Result[Arg, Failure]:
    if text == "":
        return error(bad("invalid operand ''"))

    let r = reg_index(text)
    if r >= 0:
        return ok(Arg(kind: K_REG, reg: r, value: 0, terms: List[Term]()))

    if text.starts_with("["):
        let cs = text.chars()
        let n = cs.length()
        if n < 2 or cs[n - 1] != "]":
            return error(bad("invalid operand '{text}'"))

        let terms = split_terms(slice_chars(cs, 1, n - 1))
        if terms.is_error():
            return error(bad("invalid operand '{text}'"))

        var base = -1

        for t in terms.get():
            if t.reg >= 0:
                if t.neg or base >= 0:
                    return error(bad("invalid operand '{text}'"))

                base = t.reg

        return ok(Arg(kind: K_MEM, reg: base, value: 0, terms: terms.get().clone()))

    var terms = List[Term]()
    terms.append(Term(neg: false, text: text, reg: -1))
    return ok(Arg(kind: K_IMM, reg: -1, value: 0, terms: terms))

fn parse_number(tok: String) Int:
    let cs = tok.chars()
    var base = 10
    var start = 0

    if cs.length() > 2 and cs[0] == "0" and cs[1] == "x":
        base = 16
        start = 2
    else if cs.length() > 2 and cs[0] == "0" and cs[1] == "b":
        base = 2
        start = 2

    var acc = 0
    var big = false

    for i in start..cs.length():
        let d = digit_value(cs[i])
        if d < 0 or d >= base:
            return -1

        if not big:
            acc = acc * base + d
            if acc > MAX_LITERAL:
                big = true

    if big:
        return -2

    return acc

# Parses a decimal integer for .budget; anything invalid or above the budget limit is out of range.
fn parse_decimal(text: String) Int:
    let cs = text.chars()
    if cs.length() == 0:
        return -1

    var acc = 0

    for c in cs:
        if not is_digit(c):
            return -1

        acc = acc * 10 + digit_value(c)
        if acc > MAX_BUDGET:
            return MAX_BUDGET + 1

    return acc

fn symbol_value(name: String, asm: Asm, stack: List[String]) Result[Int, Failure]:
    if let v = asm.labels.get(name):
        return ok(v)

    if let text = asm.equs.get(name):
        if stack.contains(name):
            return error(bad("circular definition of '{name}'"))

        var inner = stack.clone()
        inner.append(name)
        return eval_expr(text, asm, inner)

    return error(bad("undefined symbol '{name}'"))

fn read_term(
    cs: List[String],
    i: Int,
    whole: String,
    asm: Asm,
    stack: List[String]
) Result[Scan, Failure]:
    let c = ch(cs, i)

    if c == "'":
        let len = char_lit_len(cs, i)
        if len == 0:
            return error(bad("invalid expression '{whole}'"))

        let v = char_lit_value(cs, i)
        if v < 0:
            return error(bad("invalid expression '{whole}'"))

        return ok(Scan(value: v, next: i + len))

    if is_digit(c):
        var j = i
        while is_ident(ch(cs, j)):
            j += 1

        let v = parse_number(slice_chars(cs, i, j))
        if v == -1:
            return error(bad("invalid expression '{whole}'"))
        if v == -2:
            return error(bad("immediate out of range"))

        return ok(Scan(value: v, next: j))

    if is_letter(c):
        var j = i
        while is_ident(ch(cs, j)):
            j += 1

        let v = symbol_value(slice_chars(cs, i, j), asm, stack)
        if v.is_error():
            return error(v.err().clone())

        return ok(Scan(value: v.get(), next: j))

    return error(bad("invalid expression '{whole}'"))

# Evaluates an expression: optional sign, terms joined by + and -, 32-bit wraparound.
fn eval_expr(text: String, asm: Asm, stack: List[String]) Result[Int, Failure]:
    let whole = text.trim()
    let cs = whole.chars()
    let n = cs.length()
    var i = skip_ws(cs, 0)
    var sign = 1

    if ch(cs, i) == "-":
        sign = -1
        i = skip_ws(cs, i + 1)
    else if ch(cs, i) == "+":
        i = skip_ws(cs, i + 1)

    var total = 0
    var done = false

    while not done:
        let t = read_term(cs, i, whole, asm, stack)
        if t.is_error():
            return error(t.err().clone())

        total = wrap(total + sign * t.get().value)
        i = skip_ws(cs, t.get().next)

        if i >= n:
            done = true
        else if cs[i] == "+":
            sign = 1
            i = skip_ws(cs, i + 1)
        else if cs[i] == "-":
            sign = -1
            i = skip_ws(cs, i + 1)
        else:
            return error(bad("invalid expression '{whole}'"))

    return ok(total)

fn define_label(var asm: Asm, name: String) Result[Unit, Failure]:
    if reg_index(name) >= 0:
        return error(bad("reserved name '{name}'"))
    if asm.labels.contains(name) or asm.equs.contains(name):
        return error(bad("duplicate symbol '{name}'"))

    if asm.in_data:
        asm.labels[name.clone()] = asm.data_size
    else:
        asm.labels[name.clone()] = asm.text_count
        if name == "main":
            asm.entry = asm.text_count

    return ok(unit)

fn define_equ(var asm: Asm, args: String) Result[Unit, Failure]:
    let ops = split_operands(args)
    if ops.length() != 2:
        return error(bad("wrong number of operands for '.equ'"))

    let name = ops[0]
    if not is_identifier(name):
        return error(bad("invalid operand '{name}'"))
    if reg_index(name) >= 0:
        return error(bad("reserved name '{name}'"))
    if asm.labels.contains(name) or asm.equs.contains(name):
        return error(bad("duplicate symbol '{name}'"))

    asm.equs[name.clone()] = ops[1].clone()
    return ok(unit)

# Parses a .ascii/.asciz string literal into its byte values.
fn parse_string(text: String) Result[List[Int], Failure]:
    let cs = text.chars()
    let n = cs.length()
    if n < 2 or cs[0] != "\"":
        return error(bad("invalid string"))

    var bytes = List[Int]()
    var i = 1

    while i < n:
        let c = cs[i]

        if c == "\"":
            if i == n - 1:
                return ok(bytes)

            return error(bad("invalid string"))

        if c == "\\":
            if i + 1 >= n:
                return error(bad("invalid string"))

            let v = escape_value(cs[i + 1])
            if v < 0:
                return error(bad("invalid string"))

            bytes.append(v)
            i += 2
        else:
            for b in byte_values(c):
                bytes.append(b)
            i += 1

    return error(bad("invalid string"))

fn data_directive(var asm: Asm, word: String, args: String, line: Int) Result[
    Unit, Failure
]:
    if word == ".space":
        let ops = split_operands(args)
        if ops.length() != 1 and ops.length() != 2:
            return error(bad("wrong number of operands for '.space'"))

        let count = eval_expr(ops[0], asm, List[String]())
        if count.is_error():
            return error(count.err().clone())
        if count.get() < 0:
            return error(bad("invalid operand '{ops[0]}'"))
        if asm.data_size + count.get() > MEM_SIZE:
            return error(bad("data section too large"))

        var fill = "0"
        if ops.length() == 2:
            fill = ops[1].clone()

        var texts = List[String]()
        texts.append(fill)
        asm.stmts.append(
            Stmt(
                line: line, is_instr: false, code: 0, args: List[Arg](),
                addr: asm.data_size, count: count.get(), texts: texts, is_space: true
            )
        )
        asm.data_size += count.get()
        return ok(unit)

    var texts = List[String]()

    if word == ".word":
        texts = split_operands(args)
        if texts.length() == 0:
            return error(bad("wrong number of operands for '.word'"))
    else:
        let bytes = parse_string(args)
        if bytes.is_error():
            return error(bytes.err().clone())

        for b in bytes.get():
            texts.append("{b}")
        if word == ".asciz":
            texts.append("0")

    if asm.data_size + texts.length() > MEM_SIZE:
        return error(bad("data section too large"))

    asm.stmts.append(
        Stmt(
            line: line, is_instr: false, code: 0, args: List[Arg](),
            addr: asm.data_size, count: texts.length(), texts: texts.clone(),
            is_space: false
        )
    )
    asm.data_size += texts.length()
    return ok(unit)

fn directive(var asm: Asm, word: String, args: String, line: Int) Result[Unit, Failure]:
    if word == ".text" or word == ".data":
        if args != "":
            return error(bad("invalid operand '{args}'"))

        asm.in_data = (word == ".data")
        return ok(unit)

    if word == ".equ":
        return define_equ(var asm, args)

    if word == ".budget":
        let v = parse_decimal(args)
        if v < 1 or v > MAX_BUDGET:
            return error(bad("invalid operand '{args}'"))

        asm.budget = v
        return ok(unit)

    if word == ".word" or word == ".ascii" or word == ".asciz" or word == ".space":
        if not asm.in_data:
            return error(bad("data directive in text section"))

        return data_directive(var asm, word, args, line)

    return error(bad("unknown directive '{word}'"))

fn instruction(var asm: Asm, name: String, args: String, line: Int) Result[
    Unit, Failure
]:
    if asm.in_data:
        return error(bad("instruction in data section"))

    let code = op_code(name)
    if code < 0:
        return error(bad("unknown mnemonic '{name}'"))

    let ops = split_operands(args)
    var resolved = List[Arg]()

    for o in ops:
        let arg = classify(o.clone())
        if arg.is_error():
            return error(arg.err().clone())

        resolved.append(arg.get().clone())

    if ops.length() != op_arity(code):
        return error(bad("wrong number of operands for '{name}'"))
    if not shape_ok(code, resolved):
        return error(bad("invalid operands for '{name}'"))

    asm.stmts.append(
        Stmt(
            line: line, is_instr: true, code: code, args: resolved, addr: 0, count: 0,
            texts: List[String](), is_space: false
        )
    )
    asm.text_count += 1
    return ok(unit)

# Label names are identifiers followed by ':'; returns the identifier length, or 0.
fn label_len(cs: List[String]) Int:
    if not is_letter(ch(cs, 0)):
        return 0

    var k = 1
    while is_ident(ch(cs, k)):
        k += 1
    if ch(cs, k) == ":":
        return k

    return 0

fn split_word(rest: String) Word:
    let cs = rest.chars()
    var k = 0
    while k < cs.length() and not is_space(cs[k]):
        k += 1
    return Word(
        word: slice_chars(cs, 0, k), args: slice_chars(cs, k, cs.length()).trim()
    )

fn pass1_line(var asm: Asm, raw: String, line: Int) Result[Unit, Failure]:
    var rest = strip_comment(raw).trim()

    while true:
        let cs = rest.chars()
        let k = label_len(cs)
        if k == 0:
            break

        let r = define_label(var asm, slice_chars(cs, 0, k))
        if r.is_error():
            return r

        rest = slice_chars(cs, k + 1, cs.length()).trim()

    if rest == "":
        return ok(unit)

    let w = split_word(rest)
    if w.word.starts_with("."):
        return directive(var asm, w.word, w.args, line)

    return instruction(var asm, w.word, w.args, line)

fn pass1(var asm: Asm, src: List[String]) Result[Unit, Failure]:
    for k in 0..src.length():
        let r = pass1_line(var asm, src[k].clone(), k + 1)
        if r.is_error():
            return error(bad("line {k + 1}: {r.err().msg}"))

    return ok(unit)

fn resolve_arg(a: Arg, asm: Asm) Result[Arg, Failure]:
    var v = 0

    if a.kind == K_IMM:
        let e = eval_expr(a.terms[0].text, asm, List[String]())
        if e.is_error():
            return error(e.err().clone())

        v = e.get()
    else if a.kind == K_MEM:
        for t in a.terms:
            if t.reg < 0:
                let e = eval_expr(t.text, asm, List[String]())
                if e.is_error():
                    return error(e.err().clone())

                if t.neg:
                    v = wrap(v - e.get())
                else:
                    v = wrap(v + e.get())

    return ok(Arg(kind: a.kind, reg: a.reg, value: v, terms: List[Term]()))

fn is_jump(code: Int) Bool:
    return code >= OP_JMP and code <= OP_CALL

fn resolve_stmt(var prog: Program, st: Stmt, asm: Asm) Result[Unit, Failure]:
    if st.is_instr:
        var args = List[Arg]()

        for a in st.args:
            let r = resolve_arg(a, asm)
            if r.is_error():
                return error(r.err().clone())

            args.append(r.get().clone())

        if is_jump(st.code):
            let t = args[0].value
            if t < 0 or t >= asm.text_count:
                return error(bad("invalid jump target"))

        prog.instrs.append(Instr(code: st.code, line: st.line, args: args))
        return ok(unit)

    if st.is_space:
        let fill = eval_expr(st.texts[0], asm, List[String]())
        if fill.is_error():
            return error(fill.err().clone())

        for k in 0..st.count:
            prog.mem[st.addr + k] = fill.get()
        return ok(unit)

    for k in 0..st.texts.length():
        let v = eval_expr(st.texts[k], asm, List[String]())
        if v.is_error():
            return error(v.err().clone())

        prog.mem[st.addr + k] = v.get()

    return ok(unit)

fn assemble(var asm: Asm, src: List[String]) Result[Program, Failure]:
    let p1 = pass1(var asm, src)
    if p1.is_error():
        return error(p1.err().clone())

    var mem = List[Int]()
    for i in 0..MEM_SIZE:
        mem.append(0)

    var entry = 0
    if asm.entry >= 0:
        entry = asm.entry

    var prog = Program(
        instrs: List[Instr](), mem: mem, budget: asm.budget, entry: entry
    )

    for st in asm.stmts:
        let r = resolve_stmt(var prog, st, asm)
        if r.is_error():
            return error(bad("line {st.line}: {r.err().msg}"))

    return ok(prog)

fn wrap_alu(code: Int, a: Int, b: Int) Result[Int, Failure]:
    if code == OP_ADD:
        return ok(wrap(a + b))
    if code == OP_SUB:
        return ok(wrap(a - b))
    if code == OP_MUL:
        return ok(wrap(a * b))

    if code == OP_DIV or code == OP_MOD:
        if b == 0:
            return error(bad("division by zero"))
        if code == OP_DIV:
            return ok(wrap(a / b))

        return ok(wrap(a % b))

    if code == OP_AND:
        return ok(bit_and(a, b))
    if code == OP_OR:
        return ok(bit_or(a, b))
    if code == OP_XOR:
        return ok(bit_xor(a, b))

    let count = bit_and(b, 31)
    if code == OP_SHL:
        return ok(wrap(shift_left(unsigned(a), count)))
    if code == OP_SHR:
        return ok(wrap(shift_right(unsigned(a), count)))

    return ok(wrap(shift_right(a, count)))

fn unary(code: Int, x: Int) Int:
    if code == OP_NEG:
        return wrap(-x)
    if code == OP_NOT:
        return bit_not(x)
    if code == OP_INC:
        return wrap(x + 1)

    return wrap(x - 1)

fn jump_taken(code: Int, vm: Machine) Bool:
    if code == OP_JMP:
        return true
    if code == OP_JE:
        return vm.z
    if code == OP_JNE:
        return not vm.z
    if code == OP_JL:
        return vm.l
    if code == OP_JLE:
        return vm.l or vm.z
    if code == OP_JG:
        return not vm.l and not vm.z

    return not vm.l

fn addr_of(vm: Machine, arg: Arg) Int:
    var base = 0
    if arg.reg >= 0:
        base = vm.regs[arg.reg]
    return wrap(base + arg.value)

fn mem_read(vm: Machine, addr: Int) Result[Int, Failure]:
    if addr < 0 or addr >= MEM_SIZE:
        return error(bad("memory access out of range: {addr}"))

    return ok(vm.mem[addr])

fn mem_write(var vm: Machine, addr: Int, v: Int) Result[Unit, Failure]:
    if addr < 0 or addr >= MEM_SIZE:
        return error(bad("memory access out of range: {addr}"))

    vm.mem[addr] = v
    return ok(unit)

fn read_val(vm: Machine, arg: Arg) Result[Int, Failure]:
    if arg.kind == K_REG:
        return ok(vm.regs[arg.reg])
    if arg.kind == K_IMM:
        return ok(arg.value)

    return mem_read(vm, addr_of(vm, arg))

fn write_arg(var vm: Machine, arg: Arg, v: Int) Result[Unit, Failure]:
    if arg.kind == K_REG:
        vm.regs[arg.reg] = v
        return ok(unit)

    return mem_write(var vm, addr_of(vm, arg), v)

# Runs one instruction and returns the next pc; the pc and steps are only updated by the caller on success.
fn execute(var vm: Machine, ins: Instr) Result[Int, Failure]:
    let code = ins.code
    var next = vm.pc + 1

    if code == OP_MOV:
        let v = read_val(vm, ins.args[1])
        if v.is_error():
            return error(v.err().clone())

        let w = write_arg(var vm, ins.args[0], v.get())
        if w.is_error():
            return error(w.err().clone())
    else if code == OP_LEA:
        vm.regs[ins.args[0].reg] = addr_of(vm, ins.args[1])
    else if code >= OP_ADD and code <= OP_CMP:
        let src = read_val(vm, ins.args[1])
        if src.is_error():
            return error(src.err().clone())

        let d = ins.args[0].reg

        if code == OP_CMP:
            vm.z = vm.regs[d] == src.get()
            vm.l = vm.regs[d] < src.get()
        else:
            let res = wrap_alu(code, vm.regs[d], src.get())
            if res.is_error():
                return error(res.err().clone())

            vm.regs[d] = res.get()
    else if code >= OP_NEG and code <= OP_DEC:
        let d = ins.args[0].reg
        vm.regs[d] = unary(code, vm.regs[d])
    else if code == OP_PUSH:
        let v = read_val(vm, ins.args[0])
        if v.is_error():
            return error(v.err().clone())
        if vm.regs[SP] <= 0:
            return error(bad("stack overflow"))

        vm.regs[SP] = vm.regs[SP] - 1

        let w = mem_write(var vm, vm.regs[SP], v.get())
        if w.is_error():
            return error(w.err().clone())
    else if code == OP_POP:
        if vm.regs[SP] >= MEM_SIZE:
            return error(bad("stack underflow"))

        let v = mem_read(vm, vm.regs[SP])
        if v.is_error():
            return error(v.err().clone())

        vm.regs[SP] = vm.regs[SP] + 1
        vm.regs[ins.args[0].reg] = v.get()
    else if code == OP_CALL:
        if vm.regs[SP] <= 0:
            return error(bad("stack overflow"))

        vm.regs[SP] = vm.regs[SP] - 1

        let w = mem_write(var vm, vm.regs[SP], vm.pc + 1)
        if w.is_error():
            return error(w.err().clone())

        next = ins.args[0].value
    else if code == OP_RET:
        if vm.regs[SP] >= MEM_SIZE:
            return error(bad("stack underflow"))

        let target = mem_read(vm, vm.regs[SP])
        if target.is_error():
            return error(target.err().clone())

        vm.regs[SP] = vm.regs[SP] + 1
        next = target.get()
    else if code >= OP_JMP and code <= OP_JGE and jump_taken(code, vm):
        next = ins.args[0].value
    else if code == OP_IN:
        if vm.in_pos >= vm.inputs.length():
            return error(bad("input exhausted"))

        vm.regs[ins.args[0].reg] = vm.inputs[vm.in_pos]
        vm.in_pos += 1
    else if code == OP_OUT:
        let v = read_val(vm, ins.args[0])
        if v.is_error():
            return error(v.err().clone())

        vm.out.append("{v.get()}\n")
    else if code == OP_OUTC:
        let v = read_val(vm, ins.args[0])
        if v.is_error():
            return error(v.err().clone())
        if v.get() < 0 or v.get() > 127:
            return error(bad("invalid character"))

        vm.out.append(from_scalars([v.get()]).get())
    else if code == OP_HALT:
        vm.halted = true

    return ok(next)

fn parse_inputs(lines: List[String]) List[Int]:
    var values = List[Int]()

    for line in lines:
        for chunk in line.split(" "):
            for tok in chunk.split("\t"):
                let v = input_value(tok)
                if let x = v:
                    values.append(x)

    return values

# Input tokens are optional '-' then decimal digits, wrapped to 32 bits; anything else is skipped.
fn input_value(tok: String) Optional[Int]:
    let cs = tok.chars()
    let n = cs.length()
    var start = 0
    var negative = false

    if ch(cs, 0) == "-":
        negative = true
        start = 1

    if start >= n:
        return none

    var acc = 0

    for i in start..n:
        if not is_digit(cs[i]):
            return none

        acc = bit_and(acc * 10 + digit_value(cs[i]), 4294967295)

    if negative:
        return some(wrap(-acc))

    return some(wrap(acc))

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var src = List[String]()
    var input_lines = List[String]()
    var after = false

    for line in lines:
        if after:
            input_lines.append(line)
        else if line == "====":
            after = true
        else:
            src.append(line)

    var out = stdout()
    var asm = Asm(
        labels: Map[String, Int](), equs: Map[String, String](), stmts: List[Stmt](),
        text_count: 0, data_size: 0, in_data: false, budget: DEFAULT_BUDGET, entry: -1
    )
    let assembled = assemble(var asm, src)

    if assembled.is_error():
        out.write("asm error {assembled.err().msg}\n").get()
        return 0

    let prog = assembled.get()
    var regs = List[Int]()
    for i in 0..10:
        regs.append(0)
    regs[SP] = MEM_SIZE

    var vm = Machine(
        regs: regs, mem: prog.mem.clone(), z: false, l: false, pc: prog.entry, steps: 0,
        halted: false, inputs: parse_inputs(input_lines), in_pos: 0, out: List[String]()
    )
    var trap = ""

    while true:
        if vm.steps == prog.budget:
            trap = "budget exceeded"
            break

        if vm.pc < 0 or vm.pc >= prog.instrs.length():
            trap = "pc out of range"
            break

        let r = execute(var vm, prog.instrs[vm.pc])

        if r.is_error():
            trap = r.err().msg.clone()
            break

        vm.pc = r.get()
        vm.steps += 1
        if vm.halted:
            break

    var text = vm.out.join("")
    if text != "" and not text.ends_with("\n"):
        text += "\n"

    var summary = "-- halted after {vm.steps} steps\n"

    if trap != "":
        var line_no = "-"
        if vm.pc >= 0 and vm.pc < prog.instrs.length():
            line_no = "{prog.instrs[vm.pc].line}"
        summary = "-- trap: {trap} (pc={vm.pc} line={line_no}) after {vm.steps} steps\n"

    var zf = 0
    if vm.z:
        zf = 1

    var lf = 0
    if vm.l:
        lf = 1

    let r = vm.regs
    let regs_line = "regs: r0={r[0]} r1={r[1]} r2={r[2]} r3={r[3]} r4={r[4]} r5={r[5]} r6={r[6]} r7={r[7]} sp={r[8]} bp={r[9]}\n"
    out.write(text + summary + regs_line + "flags: Z={zf} L={lf}\n").get()
    return 0
