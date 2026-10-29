import {stdout, stdin} from "@std/io.ms"
import read_lines from "@std/streams.ms"
import {bit_and, bit_or, bit_xor, shift_left, shift_right, shift_right_unsigned} from "@std/math.ms"
import {StringBuilder, from_scalars} from "@std/string.ms"

# ---- constants ----------------------------------------------------------

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
let KIND_REG = 0
let KIND_IMM = 1
let KIND_MEM = 2
let SYM_TEXT = 0
let SYM_DATA = 1
let SYM_EQU = 2
let SP = 8
let BP = 9
let WORDS = 4096
let MASK32 = 4294967295
let TWO32 = 4294967296
let DEFAULT_BUDGET = 100000
let MAX_BUDGET = 10000000
let IDENT_HEAD = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
let IDENT_TAIL = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789."

# ---- records ------------------------------------------------------------

type Fault:
    text: String

impl Error for Fault:
    fn message() String: self.text.clone()

type Sym:
    kind: Int
    value: Int
    expr: String

type Operand:
    kind: Int
    reg: Int
    expr: String

# kind 0: instruction, 1: data words (exprs, one per word), 2: data fill (exprs[0], count words)
type Stmt:
    line: Int
    kind: Int
    op: Int
    name: String
    operands: List[Operand]
    addr: Int
    count: Int
    exprs: List[String]

type Asm:
    syms: Map[String, Sym]
    stmts: List[Stmt]
    in_data: Bool
    instr_count: Int
    data_count: Int
    budget: Int

type Rop:
    kind: Int
    reg: Int
    value: Int

type Instr:
    op: Int
    line: Int
    a: Rop
    b: Rop

type Machine:
    regs: List[Int]
    mem: List[Int]
    pc: Int
    steps: Int
    zf: Bool
    lf: Bool
    input: List[Int]
    in_pos: Int
    out: StringBuilder
    has_out: Bool
    ends_nl: Bool
    halted: Bool
    table: List[String]

type Trap:
    msg: String
    pc: Int
    line: String

# ---- small helpers ------------------------------------------------------

fn wrap32(x: Int) Int:
    let u = bit_and(x, MASK32)
    if u >= 2147483648:
        return u - TWO32

    return u

fn is_space(c: String) Bool:
    return c == " " or c == "\t" or c == "\r" or c == "\n"

fn is_digit(c: String) Bool:
    return c != "" and "0123456789".contains(c)

fn is_head(c: String) Bool:
    return c != "" and IDENT_HEAD.contains(c)

fn is_tail(c: String) Bool:
    return c != "" and IDENT_TAIL.contains(c)

fn join_range(cs: List[String], lo: Int, hi: Int) String:
    var s = ""
    var i = lo

    while i < hi:
        s += cs[i]
        i += 1

    return s

fn skip_space(cs: List[String], start: Int) Int:
    var i = start
    while i < cs.length() and is_space(cs[i]):
        i += 1
    return i

# Length of the identifier starting at `start`, or 0 when none starts there.
fn ident_len(cs: List[String], start: Int) Int:
    if start >= cs.length() or not is_head(cs[start]):
        return 0

    var n = 1
    while start + n < cs.length() and is_tail(cs[start + n]):
        n += 1
    return n

fn is_identifier(s: String) Bool:
    let cs = s.chars()
    return cs.length() > 0 and ident_len(cs, 0) == cs.length()

fn reg_index(name: String) Int:
    let names = ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]
    for k in 0..10:
        if names[k] == name:
            return k
    return -1

fn digit_value(c: String) Int:
    let digits = "0123456789abcdefABCDEF".chars()

    for k in 0..22:
        if digits[k] == c:
            if k >= 16:
                return k - 6

            return k

    return -1

# Removes a `;` comment, leaving `;` and `#` alone inside string or character literals.
fn strip_comment(line: String) String:
    var out = ""
    var in_str = false
    var in_char = false
    var esc = false

    for c in line.chars():
        if esc:
            esc = false
        else if (in_str or in_char) and c == "\\":
            esc = true
        else if in_str:
            if c == "\"":
                in_str = false
        else if in_char:
            if c == "'":
                in_char = false
        else if c == ";":
            break
        else if c == "\"":
            in_str = true
        else if c == "'":
            in_char = true

        out += c

    return out

# Splits operands at commas outside brackets and character literals.
fn split_operands(text: String) List[String]:
    var parts = List[String]()
    var cur = ""
    var depth = 0
    var in_char = false
    var esc = false

    for c in text.chars():
        if in_char:
            cur += c

            if esc:
                esc = false
            else if c == "\\":
                esc = true
            else if c == "'":
                in_char = false
        else if c == "'":
            in_char = true
            cur += c
        else if c == "[":
            depth += 1
            cur += c
        else if c == "]":
            depth -= 1
            cur += c
        else if c == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += c

    parts.append(cur)
    return parts

# Splits a bracket body into signed terms: "r2-1+a" -> ["+r2", "-1", "+a"].
fn split_signed(text: String) List[String]:
    var parts = List[String]()
    var cur = "+"
    var in_char = false
    var esc = false
    var k = 0

    for c in text.chars():
        if in_char:
            cur += c

            if esc:
                esc = false
            else if c == "\\":
                esc = true
            else if c == "'":
                in_char = false
        else if (c == "+" or c == "-") and k > 0:
            parts.append(cur)
            cur = c
        else if c == "+" or c == "-":
            cur = c
        else:
            if c == "'":
                in_char = true
            cur += c

        k += 1

    parts.append(cur)
    return parts

fn split_words(line: String) List[String]:
    var words = List[String]()
    var cur = ""

    for c in line.chars():
        if is_space(c):
            if cur != "":
                words.append(cur)
                cur = ""
        else:
            cur += c

    if cur != "":
        words.append(cur)
    return words

# ---- expressions --------------------------------------------------------

fn byte_of(c: String) Int:
    if c.byte_length() != 1:
        return -1

    return c.to_bytes().get(0).to_int()

fn escape_of(c: String) Int:
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

# cs is a complete character literal such as 'a' or '\n'; -1 when malformed.
fn char_value(cs: List[String]) Int:
    let n = cs.length()
    if n == 3 and cs[1] != "\\" and cs[1] != "'":
        return byte_of(cs[1])
    if n == 4 and cs[1] == "\\":
        return escape_of(cs[2])

    return -1

# End index (exclusive) of the term starting at i; i itself when there is none.
fn term_end(cs: List[String], i: Int) Int:
    let n = cs.length()

    if i < n and cs[i] == "'":
        var j = i + 1

        if j < n and cs[j] == "\\":
            j += 2
        else:
            j += 1

        if j < n and cs[j] == "'":
            return j + 1

        return i

    var e = i
    while e < n and is_tail(cs[e]):
        e += 1
    return e

fn parse_number(tok: String, whole: String) Result[Int, Fault]:
    let cs = tok.chars()
    let n = cs.length()
    var base = 10
    var start = 0

    if n >= 2 and cs[0] == "0" and cs[1] == "x":
        base = 16
        start = 2
    else if n >= 2 and cs[0] == "0" and cs[1] == "b":
        base = 2
        start = 2

    if start == n:
        return error(Fault(text: "invalid expression '{whole}'"))

    var v = 0

    for k in start..n:
        let d = digit_value(cs[k])
        if d < 0 or d >= base:
            return error(Fault(text: "invalid expression '{whole}'"))

        v = v * base + d
        if v > MASK32:
            v = TWO32

    if v > MASK32:
        return error(Fault(text: "immediate out of range"))

    return ok(v)

fn eval_token(
    tok: String,
    whole: String,
    syms: Map[String, Sym],
    stack: List[String]
) Result[Int, Fault]:
    let cs = tok.chars()

    if cs[0] == "'":
        let v = char_value(cs)
        if v < 0:
            return error(Fault(text: "invalid expression '{whole}'"))

        return ok(v)

    if is_head(cs[0]):
        if let sym = syms.get(tok):
            if sym.kind == SYM_EQU:
                if stack.contains(tok):
                    return error(Fault(text: "circular definition of '{tok}'"))

                var next = stack.clone()
                next.append(tok)
                return eval_expr(sym.expr, syms, next)

            return ok(sym.value)

        return error(Fault(text: "undefined symbol '{tok}'"))

    if is_digit(cs[0]):
        return parse_number(tok, whole)

    return error(Fault(text: "invalid expression '{whole}'"))

# Evaluates an expression: optional leading sign, then terms joined by + or -.
fn eval_expr(
    text: String,
    syms: Map[String, Sym],
    stack: List[String]
) Result[Int, Fault]:
    let whole = text.trim()
    let cs = text.chars()
    let n = cs.length()
    var i = skip_space(cs, 0)
    var sign = 1

    if i < n and (cs[i] == "+" or cs[i] == "-"):
        if cs[i] == "-":
            sign = -1
        i += 1

    var total = 0

    while true:
        i = skip_space(cs, i)

        let e = term_end(cs, i)
        if e == i:
            return error(Fault(text: "invalid expression '{whole}'"))

        let v = try eval_token(join_range(cs, i, e), whole, syms, stack)
        total = wrap32(total + sign * v)
        i = skip_space(cs, e)
        if i >= n:
            break

        if cs[i] == "+":
            sign = 1
        else if cs[i] == "-":
            sign = -1
        else:
            return error(Fault(text: "invalid expression '{whole}'"))

        i += 1

    return ok(total)

# Value of a decimal integer input token (optional leading '-'), wrapped to 32 bits; none when invalid.
fn input_value(tok: String) Optional[Int]:
    let cs = tok.chars()
    let n = cs.length()
    var k = 0
    var neg = false

    if n > 0 and cs[0] == "-":
        neg = true
        k = 1

    if k >= n:
        return none

    var v = 0

    for j in k..n:
        if not is_digit(cs[j]):
            return none

        v = (v * 10 + digit_value(cs[j])) % TWO32

    if neg:
        v = (TWO32 - v) % TWO32
    return wrap32(v)

# ---- operands and statements (pass 1) -----------------------------------

fn parse_memory(text: String) Result[Operand, Fault]:
    let cs = text.chars()
    let n = cs.length()
    if n < 2 or cs[n - 1] != "]":
        return error(Fault(text: "invalid operand '{text}'"))

    var reg = -1
    var expr = ""

    for part in split_signed(join_range(cs, 1, n - 1)):
        let pcs = part.chars()
        let sign = pcs[0]
        let body = join_range(pcs, 1, pcs.length()).trim()
        if body == "":
            return error(Fault(text: "invalid operand '{text}'"))

        let r = reg_index(body)

        if r >= 0:
            if sign == "-" or reg >= 0:
                return error(Fault(text: "invalid operand '{text}'"))

            reg = r
        else:
            expr += sign + body

    return ok(Operand(kind: KIND_MEM, reg: reg, expr: expr))

fn parse_operand(text: String) Result[Operand, Fault]:
    if text == "":
        return error(Fault(text: "invalid operand ''"))

    let r = reg_index(text)
    if r >= 0:
        return ok(Operand(kind: KIND_REG, reg: r, expr: ""))
    if text.starts_with("["):
        return parse_memory(text)

    return ok(Operand(kind: KIND_IMM, reg: -1, expr: text))

fn opcode_of(name: String) Int:
    if name == "mov":
        return OP_MOV
    if name == "add":
        return OP_ADD
    if name == "sub":
        return OP_SUB
    if name == "mul":
        return OP_MUL
    if name == "div":
        return OP_DIV
    if name == "mod":
        return OP_MOD
    if name == "and":
        return OP_AND
    if name == "or":
        return OP_OR
    if name == "xor":
        return OP_XOR
    if name == "shl":
        return OP_SHL
    if name == "shr":
        return OP_SHR
    if name == "sar":
        return OP_SAR
    if name == "cmp":
        return OP_CMP
    if name == "neg":
        return OP_NEG
    if name == "not":
        return OP_NOT
    if name == "inc":
        return OP_INC
    if name == "dec":
        return OP_DEC
    if name == "lea":
        return OP_LEA
    if name == "push":
        return OP_PUSH
    if name == "pop":
        return OP_POP
    if name == "jmp":
        return OP_JMP
    if name == "je" or name == "jz":
        return OP_JE
    if name == "jne" or name == "jnz":
        return OP_JNE
    if name == "jl":
        return OP_JL
    if name == "jle":
        return OP_JLE
    if name == "jg":
        return OP_JG
    if name == "jge":
        return OP_JGE
    if name == "call":
        return OP_CALL
    if name == "ret":
        return OP_RET
    if name == "in":
        return OP_IN
    if name == "out":
        return OP_OUT
    if name == "outc":
        return OP_OUTC
    if name == "halt":
        return OP_HALT
    if name == "nop":
        return OP_NOP

    return -1

fn is_alu(op: Int) Bool:
    return op >= OP_ADD and op <= OP_SAR

fn is_jump(op: Int) Bool:
    return (op >= OP_JMP and op <= OP_JGE) or op == OP_CALL

fn arity(op: Int) Int:
    if op == OP_MOV or is_alu(op) or op == OP_CMP or op == OP_LEA:
        return 2
    if op == OP_RET or op == OP_HALT or op == OP_NOP:
        return 0

    return 1

fn shape_ok(op: Int, ops: List[Operand]) Bool:
    if op == OP_MOV:
        if ops[0].kind == KIND_REG:
            return true
        if ops[0].kind == KIND_MEM:
            return ops[1].kind != KIND_MEM

        return false

    if is_alu(op) or op == OP_CMP:
        return ops[0].kind == KIND_REG
    if op == OP_LEA:
        return ops[0].kind == KIND_REG and ops[1].kind == KIND_MEM
    if is_jump(op):
        return ops[0].kind == KIND_IMM
    if (
        op == OP_NEG
        or op == OP_NOT
        or op == OP_INC
        or op == OP_DEC
        or op == OP_POP
        or op == OP_IN
    ):
        return ops[0].kind == KIND_REG

    return true

fn add_symbol(var a: Asm, name: String, sym: Sym) Result[Unit, Fault]:
    if reg_index(name) >= 0:
        return error(Fault(text: "reserved name '{name}'"))
    if a.syms.contains(name):
        return error(Fault(text: "duplicate symbol '{name}'"))

    a.syms.add(name, sym)
    return ok(unit)

fn pass1_instruction(var a: Asm, line: Int, head: String, rest: String) Result[
    Unit, Fault
]:
    if a.in_data:
        return error(Fault(text: "instruction in data section"))

    let op = opcode_of(head)
    if op < 0:
        return error(Fault(text: "unknown mnemonic '{head}'"))

    var operands = List[Operand]()

    if rest != "":
        for part in split_operands(rest):
            let o = try parse_operand(part.trim().clone())
            operands.append(o)

    if operands.length() != arity(op):
        return error(Fault(text: "wrong number of operands for '{head}'"))
    if not shape_ok(op, operands):
        return error(Fault(text: "invalid operands for '{head}'"))

    a.stmts.append(
        Stmt(
            line: line, kind: 0, op: op, name: head, operands: operands, addr: 0,
            count: 0, exprs: List[String]()
        )
    )
    a.instr_count += 1
    return ok(unit)

fn trimmed_parts(text: String) List[String]:
    var parts = List[String]()
    for part in split_operands(text):
        parts.append(part.trim().clone())
    return parts

fn pass1_equ(var a: Asm, rest: String) Result[Unit, Fault]:
    let parts = if rest == "": List[String]() else: trimmed_parts(rest)

    if parts.length() != 2:
        return error(Fault(text: "wrong number of operands for '.equ'"))

    let name = parts[0]
    if not is_identifier(name):
        return error(Fault(text: "invalid operand '{name}'"))

    return add_symbol(
        var a, name.clone(), Sym(kind: SYM_EQU, value: 0, expr: parts[1].clone())
    )

fn pass1_budget(var a: Asm, rest: String) Result[Unit, Fault]:
    let cs = rest.chars()
    let bad = Fault(text: "invalid operand '{rest}'")
    if cs.length() == 0:
        return error(bad)

    var v = 0

    for c in cs:
        if not is_digit(c):
            return error(bad)

        v = v * 10 + digit_value(c)
        if v > MAX_BUDGET:
            return error(bad)

    if v < 1:
        return error(bad)

    a.budget = v
    return ok(unit)

fn parse_string(rest: String) Result[List[Int], Fault]:
    let cs = rest.chars()
    let n = cs.length()
    let bad = Fault(text: "invalid string")
    if n < 2 or cs[0] != "\"":
        return error(bad)

    var bytes = List[Int]()
    var i = 1

    while i < n:
        let c = cs[i]

        if c == "\"":
            if i == n - 1:
                return ok(bytes)

            return error(bad)

        if c == "\\":
            if i + 1 >= n:
                return error(bad)

            let e = escape_of(cs[i + 1])
            if e < 0:
                return error(bad)

            bytes.append(e)
            i += 2
        else:
            let enc = c.to_bytes()
            for k in 0..enc.length():
                bytes.append(enc.get(k).to_int())
            i += 1

    return error(bad)

fn pass1_string(var a: Asm, line: Int, rest: String, zero_term: Bool) Result[
    Unit, Fault
]:
    var bytes = try parse_string(rest)
    if zero_term:
        bytes.append(0)

    let count = bytes.length()
    if a.data_count + count > WORDS:
        return error(Fault(text: "data section too large"))

    var exprs = List[String]()
    for b in bytes:
        exprs.append("{b}")
    a.stmts.append(
        Stmt(
            line: line, kind: 1, op: 0, name: "", operands: List[Operand](),
            addr: a.data_count, count: count, exprs: exprs
        )
    )
    a.data_count += count
    return ok(unit)

fn pass1_word(var a: Asm, line: Int, rest: String) Result[Unit, Fault]:
    if rest == "":
        return error(Fault(text: "wrong number of operands for '.word'"))

    let exprs = trimmed_parts(rest)
    let count = exprs.length()
    if a.data_count + count > WORDS:
        return error(Fault(text: "data section too large"))

    a.stmts.append(
        Stmt(
            line: line, kind: 1, op: 0, name: "", operands: List[Operand](),
            addr: a.data_count, count: count, exprs: exprs
        )
    )
    a.data_count += count
    return ok(unit)

fn pass1_space(var a: Asm, line: Int, rest: String) Result[Unit, Fault]:
    let parts = if rest == "": List[String]() else: trimmed_parts(rest)

    if parts.length() < 1 or parts.length() > 2:
        return error(Fault(text: "wrong number of operands for '.space'"))

    let n = try eval_expr(parts[0], a.syms, List[String]())
    if n < 0:
        return error(Fault(text: "invalid operand '{parts[0]}'"))
    if a.data_count + n > WORDS:
        return error(Fault(text: "data section too large"))

    var fill = "0"
    if parts.length() == 2:
        fill = parts[1].clone()
    a.stmts.append(
        Stmt(
            line: line, kind: 2, op: 0, name: "", operands: List[Operand](),
            addr: a.data_count, count: n, exprs: [fill]
        )
    )
    a.data_count += n
    return ok(unit)

fn pass1_directive(var a: Asm, line: Int, head: String, rest: String) Result[
    Unit, Fault
]:
    if head == ".text" or head == ".data":
        if rest != "":
            return error(Fault(text: "invalid operand '{rest}'"))

        a.in_data = head == ".data"
        return ok(unit)

    if head == ".equ":
        return pass1_equ(var a, rest)
    if head == ".budget":
        return pass1_budget(var a, rest)

    if head == ".word" or head == ".ascii" or head == ".asciz" or head == ".space":
        if not a.in_data:
            return error(Fault(text: "data directive in text section"))
        if head == ".word":
            return pass1_word(var a, line, rest)
        if head == ".space":
            return pass1_space(var a, line, rest)

        return pass1_string(var a, line, rest, head == ".asciz")

    return error(Fault(text: "unknown directive '{head}'"))

fn define_label(var a: Asm, name: String) Result[Unit, Fault]:
    if a.in_data:
        return add_symbol(
            var a, name, Sym(kind: SYM_DATA, value: a.data_count, expr: "")
        )

    return add_symbol(var a, name, Sym(kind: SYM_TEXT, value: a.instr_count, expr: ""))

fn pass1_line(var a: Asm, line: Int, raw: String) Result[Unit, Fault]:
    let cs = strip_comment(raw).trim().chars()
    let n = cs.length()
    var pos = 0

    while true:
        pos = skip_space(cs, pos)

        let m = ident_len(cs, pos)
        if m == 0 or pos + m >= n or cs[pos + m] != ":":
            break

        try define_label(var a, join_range(cs, pos, pos + m))
        pos = pos + m + 1

    let rest = join_range(cs, pos, n).trim()
    if rest == "":
        return ok(unit)

    let rcs = rest.chars()
    var k = 0
    while k < rcs.length() and not is_space(rcs[k]):
        k += 1

    let head = join_range(rcs, 0, k)
    let tail = join_range(rcs, k, rcs.length()).trim()
    if head.starts_with("."):
        return pass1_directive(var a, line, head, tail)

    return pass1_instruction(var a, line, head, tail)

# ---- pass 2 -------------------------------------------------------------

fn resolve_operand(
    o: Operand,
    syms: Map[String, Sym],
    check_target: Bool,
    ninstr: Int
) Result[Rop, Fault]:
    if o.kind == KIND_REG:
        return ok(Rop(kind: KIND_REG, reg: o.reg, value: 0))

    var v = 0
    if o.expr != "":
        v = try eval_expr(o.expr, syms, List[String]())
    if check_target and (v < 0 or v >= ninstr):
        return error(Fault(text: "invalid jump target"))

    return ok(Rop(kind: o.kind, reg: o.reg, value: v))

fn resolve_instr(s: Stmt, syms: Map[String, Sym], ninstr: Int) Result[Instr, Fault]:
    var a = Rop(kind: KIND_REG, reg: 0, value: 0)
    var b = Rop(kind: KIND_REG, reg: 0, value: 0)
    var k = 0

    for o in s.operands:
        let r = try resolve_operand(o, syms, is_jump(s.op), ninstr)

        if k == 0:
            a = r
        else:
            b = r

        k += 1

    return ok(Instr(op: s.op, line: s.line, a: a, b: b))

fn write_data(var mem: List[Int], s: Stmt, syms: Map[String, Sym]) Result[Unit, Fault]:
    if s.kind == 1:
        for k in 0..s.count:
            let v = try eval_expr(s.exprs[k], syms, List[String]())
            mem[s.addr + k] = v
    else:
        let v = try eval_expr(s.exprs[0], syms, List[String]())
        for k in 0..s.count:
            mem[s.addr + k] = v

    return ok(unit)

# ---- execution ----------------------------------------------------------

fn effective(m: Machine, o: Rop) Int:
    if o.reg < 0:
        return o.value

    return wrap32(m.regs[o.reg] + o.value)

fn mem_read(m: Machine, addr: Int) Result[Int, Fault]:
    if addr < 0 or addr >= WORDS:
        return error(Fault(text: "memory access out of range: {addr}"))

    return ok(m.mem[addr])

fn mem_write(var m: Machine, addr: Int, v: Int) Result[Unit, Fault]:
    if addr < 0 or addr >= WORDS:
        return error(Fault(text: "memory access out of range: {addr}"))

    m.mem[addr] = v
    return ok(unit)

fn read_op(m: Machine, o: Rop) Result[Int, Fault]:
    if o.kind == KIND_REG:
        return ok(m.regs[o.reg])
    if o.kind == KIND_IMM:
        return ok(o.value)

    return mem_read(m, effective(m, o))

fn write_op(var m: Machine, o: Rop, v: Int) Result[Unit, Fault]:
    if o.kind == KIND_REG:
        m.regs[o.reg] = v
        return ok(unit)

    return mem_write(var m, effective(m, o), v)

fn push_value(var m: Machine, v: Int) Result[Unit, Fault]:
    if m.regs[SP] <= 0:
        return error(Fault(text: "stack overflow"))

    m.regs[SP] = m.regs[SP] - 1
    return mem_write(var m, m.regs[SP], v)

fn pop_value(var m: Machine) Result[Int, Fault]:
    if m.regs[SP] >= WORDS:
        return error(Fault(text: "stack underflow"))

    let v = try mem_read(m, m.regs[SP])
    m.regs[SP] = m.regs[SP] + 1
    return ok(v)

fn alu(op: Int, d: Int, s: Int) Result[Int, Fault]:
    if op == OP_ADD:
        return ok(wrap32(d + s))
    if op == OP_SUB:
        return ok(wrap32(d - s))
    if op == OP_MUL:
        return ok(wrap32(d * s))

    if op == OP_DIV or op == OP_MOD:
        if s == 0:
            return error(Fault(text: "division by zero"))
        if op == OP_DIV:
            return ok(wrap32(d / s))

        return ok(wrap32(d % s))

    if op == OP_AND:
        return ok(wrap32(bit_and(d, s)))
    if op == OP_OR:
        return ok(wrap32(bit_or(d, s)))
    if op == OP_XOR:
        return ok(wrap32(bit_xor(d, s)))
    if op == OP_SHL:
        return ok(wrap32(shift_left(bit_and(d, MASK32), bit_and(s, 31))))
    if op == OP_SHR:
        return ok(wrap32(shift_right_unsigned(bit_and(d, MASK32), bit_and(s, 31))))

    return ok(wrap32(shift_right(d, bit_and(s, 31))))

fn exec_step(var m: Machine, code: List[Instr]) Result[Unit, Fault]:
    let ins = code[m.pc]
    let op = ins.op
    var next = m.pc + 1

    if op == OP_MOV:
        let v = try read_op(m, ins.b)
        try write_op(var m, ins.a, v)
    else if is_alu(op):
        let s = try read_op(m, ins.b)
        let r = try alu(op, m.regs[ins.a.reg], s)
        m.regs[ins.a.reg] = r
    else if op == OP_CMP:
        let s = try read_op(m, ins.b)
        let d = try read_op(m, ins.a)
        m.zf = d == s
        m.lf = d < s
    else if op == OP_NEG:
        m.regs[ins.a.reg] = wrap32(0 - m.regs[ins.a.reg])
    else if op == OP_NOT:
        m.regs[ins.a.reg] = wrap32(-1 - m.regs[ins.a.reg])
    else if op == OP_INC:
        m.regs[ins.a.reg] = wrap32(m.regs[ins.a.reg] + 1)
    else if op == OP_DEC:
        m.regs[ins.a.reg] = wrap32(m.regs[ins.a.reg] - 1)
    else if op == OP_LEA:
        m.regs[ins.a.reg] = effective(m, ins.b)
    else if op == OP_PUSH:
        let v = try read_op(m, ins.a)
        try push_value(var m, v)
    else if op == OP_POP:
        let v = try pop_value(var m)
        m.regs[ins.a.reg] = v
    else if is_jump(op):
        var taken = false

        if op == OP_JMP or op == OP_CALL:
            taken = true
        else if op == OP_JE:
            taken = m.zf
        else if op == OP_JNE:
            taken = not m.zf
        else if op == OP_JL:
            taken = m.lf
        else if op == OP_JLE:
            taken = m.lf or m.zf
        else if op == OP_JG:
            taken = not m.lf and not m.zf
        else:
            taken = not m.lf

        if op == OP_CALL:
            try push_value(var m, m.pc + 1)
        if taken:
            next = ins.a.value
    else if op == OP_RET:
        next = try pop_value(var m)
    else if op == OP_IN:
        if m.in_pos >= m.input.length():
            return error(Fault(text: "input exhausted"))

        m.regs[ins.a.reg] = m.input[m.in_pos]
        m.in_pos += 1
    else if op == OP_OUT:
        let v = try read_op(m, ins.a)
        m.out.append("{v}\n")
        m.has_out = true
        m.ends_nl = true
    else if op == OP_OUTC:
        let v = try read_op(m, ins.a)
        if v < 0 or v > 127:
            return error(Fault(text: "invalid character"))

        m.out.append(m.table[v])
        m.has_out = true
        m.ends_nl = v == 10
    else if op == OP_HALT:
        m.halted = true

    m.pc = next
    m.steps += 1
    return ok(unit)

fn run_machine(var m: Machine, code: List[Instr], budget: Int) Trap:
    while not m.halted:
        if m.pc < 0 or m.pc >= code.length():
            return Trap(msg: "pc out of range", pc: m.pc, line: "-")
        if m.steps == budget:
            return Trap(msg: "budget exceeded", pc: m.pc, line: "{code[m.pc].line}")

        let r = exec_step(var m, code)
        if r.is_error():
            return Trap(msg: r.err().text.clone(), pc: m.pc, line: "{code[m.pc].line}")

    return Trap(msg: "", pc: 0, line: "")

# ---- driver -------------------------------------------------------------

fn report_asm_error(line: Int, msg: String) Int:
    stdout().write("asm error line {line}: {msg}\n").get()
    return 0

export fn main() Int:
    var source = List[String]()
    var input_lines = List[String]()
    var in_input = false

    for l in read_lines(stdin()).get():
        if in_input:
            input_lines.append(l)
        else if l == "====":
            in_input = true
        else:
            source.append(l)

    var a = Asm(
        syms: Map[String, Sym](), stmts: List[Stmt](), in_data: false, instr_count: 0,
        data_count: 0, budget: DEFAULT_BUDGET
    )

    for k in 0..source.length():
        let r = pass1_line(var a, k + 1, source[k])
        if r.is_error():
            return report_asm_error(k + 1, r.err().text.clone())

    var mem = List[Int](reserve: WORDS)
    for k in 0..WORDS:
        mem.append(0)

    var code = List[Instr]()

    for s in a.stmts:
        if s.kind == 0:
            let r = resolve_instr(s, a.syms, a.instr_count)
            if r.is_error():
                return report_asm_error(s.line, r.err().text.clone())

            code.append(r.get())
        else:
            let r = write_data(var mem, s, a.syms)
            if r.is_error():
                return report_asm_error(s.line, r.err().text.clone())

    var entry = 0
    if let sym = a.syms.get("main"):
        if sym.kind == SYM_TEXT:
            entry = sym.value

    var input = List[Int]()
    for l in input_lines:
        for tok in split_words(l):
            if let v = input_value(tok):
                input.append(v)

    var codes = List[Int]()
    for k in 0..128:
        codes.append(k)

    let table = from_scalars(codes).get().chars()
    var regs = List[Int](reserve: 10)
    for k in 0..10:
        regs.append(0)
    regs[SP] = WORDS

    var m = Machine(
        regs: regs, mem: mem, pc: entry, steps: 0, zf: false, lf: false, input: input,
        in_pos: 0, out: StringBuilder(), has_out: false, ends_nl: false, halted: false,
        table: table
    )
    let t = run_machine(var m, code, a.budget)
    var text = m.out.build()
    if m.has_out and not m.ends_nl:
        text += "\n"

    if t.msg == "":
        text += "-- halted after {m.steps} steps\n"
    else:
        text += "-- trap: {t.msg} (pc={t.pc} line={t.line}) after {m.steps} steps\n"

    let z = if m.zf: 1 else: 0

    let l = if m.lf: 1 else: 0

    text += "regs: r0={m.regs[0]} r1={m.regs[1]} r2={m.regs[2]} r3={m.regs[3]} r4={m.regs[4]} r5={m.regs[5]} r6={m.regs[6]} r7={m.regs[7]} sp={m.regs[SP]} bp={m.regs[BP]}\n"
    text += "flags: Z={z} L={l}\n"
    stdout().write(text).get()
    return 0
