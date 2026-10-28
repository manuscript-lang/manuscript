from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines
from "@std/math.ms" import bit_and, bit_not, bit_or, bit_xor, shift_left, shift_right
from "@std/bytes.ms" import Bytes, BytesBuilder

# Values are signed 32-bit words held in Int; every result is wrapped back into range.
let WORD = 4294967296
let HALF_WORD = 2147483648
let MAX_LITERAL = 4294967295
let MEMORY_SIZE = 4096
let REG_COUNT = 10
let REG_SP = 8
let REG_BP = 9
let MAX_BUDGET = 10000000
let DEFAULT_BUDGET = 100000
let NOT_A_NUMBER = -1
let TOO_BIG = -2
let MALFORMED = ""
let DIGITS = "0123456789"
let HEX_DIGITS = "0123456789abcdef"
let IDENT_START = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
let IDENT_REST = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789."
let REGISTER_NAMES = ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]
let ARG_REG = 0
let ARG_IMM = 1
let ARG_MEM = 2
# Opcodes; the index of each name in MNEMONICS is its opcode.
let MNEMONICS = [
    "mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar",
    "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je", "jne", "jl",
    "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt", "nop"
]
let MOV = 0
let ADD = 1
let SUB = 2
let MUL = 3
let DIV = 4
let MOD = 5
let AND = 6
let OR = 7
let XOR = 8
let SHL = 9
let SHR = 10
let SAR = 11
let CMP = 12
let NEG = 13
let NOT = 14
let INC = 15
let DEC = 16
let LEA = 17
let PUSH = 18
let POP = 19
let JMP = 20
let JE = 21
let JNE = 22
let JL = 23
let JLE = 24
let JG = 25
let JGE = 26
let CALL = 27
let RET = 28
let IN = 29
let OUT = 30
let OUTC = 31
let HALT = 32
let NOP = 33

type Fault:
    text: String

impl Error for Fault:
    def message() -> String:
        return self.text.clone()

# `equs` holds every .equ from the start so that lookups see constants defined further down;
# `defined_equs` records the ones already reached, which decides duplicate symbols in source order.
type Symbols:
    labels: Map[String, Int]
    equs: Map[String, String]
    defined_equs: Map[String, Bool]

# One source line split into its parts; comments are already gone.
type Line:
    number: Int
    labels: List[String]
    head: String
    rest: String

type Term:
    negative: Bool
    text: String

# An operand as written, before its expressions are evaluated.
type Source:
    kind: Int
    reg: Int
    text: String

# An instruction (code >= 0) or a data directive's words (code == -1), in source order.
type Item:
    line: Int
    code: Int
    address: Int
    times: Int
    args: List[Source]

type Arg:
    kind: Int
    reg: Int
    value: Int

type Instr:
    code: Int
    line: Int
    args: List[Arg]

type Assembly:
    syms: Symbols
    items: List[Item]
    in_data: Bool
    instr_count: Int
    data_ptr: Int
    budget: Int
    entry: Int

type Machine:
    regs: List[Int]
    mem: List[Int]
    z: Bool
    l: Bool
    pc: Int
    input: List[Int]
    next_input: Int
    out: BytesBuilder
    last_char: Int

def fail[T](text: String) -> Result[T, Fault]:
    return error(Fault(text: text))

def wrap(x: Int) -> Int:
    var r = x % WORD
    if r < 0:
        r += WORD
    if r >= HALF_WORD:
        r -= WORD
    return r

def is_space(c: String) -> Bool:
    return c == " " or c == "\t" or c == "\r"

def span(cs: List[String], start: Int, end: Int) -> String:
    var text = ""
    for i in start..end:
        text += cs[i]
    return text

def skip_spaces(cs: List[String], start: Int) -> Int:
    var i = start
    while i < cs.length() and is_space(cs[i]):
        i += 1
    return i

def ident_end(cs: List[String], start: Int) -> Int:
    if start >= cs.length() or not IDENT_START.contains(cs[start]):
        return start

    var end = start + 1
    while end < cs.length() and IDENT_REST.contains(cs[end]):
        end += 1
    return end

def is_identifier(name: String) -> Bool:
    return name != "" and ident_end(name.chars(), 0) == name.length()

def reg_index(name: String) -> Int:
    return REGISTER_NAMES.index_of(name).get(-1)

def digit_value(c: String) -> Int:
    return HEX_DIGITS.index_of(c.lower()).get(-1)

# Index just past the quoted literal starting at `i`, or -1 when there is none.
def literal_end(cs: List[String], i: Int) -> Int:
    let n = cs.length()

    if cs[i] == "'":
        if i + 3 < n and cs[i + 1] == "\\" and cs[i + 3] == "'":
            return i + 4
        if i + 2 < n and cs[i + 1] != "\\" and cs[i + 1] != "'" and cs[i + 2] == "'":
            return i + 3

        return -1

    var j = i + 1

    while j < n:
        if cs[j] == "\\":
            j += 2
        elif cs[j] == "\"":
            return j + 1
        else:
            j += 1

    return -1

def comment_start(cs: List[String]) -> Int:
    var i = 0

    while i < cs.length():
        if cs[i] == ";":
            return i

        if cs[i] == "'" or cs[i] == "\"":
            let end = literal_end(cs, i)

            if end > 0:
                i = end
                continue

        i += 1

    return cs.length()

def split_line(number: Int, raw: String) -> Line:
    let all = raw.chars()
    let code = span(all, 0, comment_start(all)).chars()
    let n = code.length()
    var labels = List[String]()
    var i = skip_spaces(code, 0)

    while True:
        let end = ident_end(code, i)
        if end == i:
            break

        let colon = skip_spaces(code, end)
        if colon >= n or code[colon] != ":":
            break

        labels.append(span(code, i, end))
        i = skip_spaces(code, colon + 1)

    var end = i
    while end < n and not is_space(code[end]):
        end += 1
    return Line(
        number: number, labels: labels, head: span(code, i, end),
        rest: span(code, end, n).trim()
    )

# Splits at commas outside brackets and character literals.
def split_operands(text: String) -> List[String]:
    var parts = List[String]()
    if text == "":
        return parts

    let cs = text.chars()
    var inside = False
    var start = 0
    var i = 0

    while i < cs.length():
        let c = cs[i]

        if c == "'":
            let end = literal_end(cs, i)

            if end > 0:
                i = end
                continue

        if c == "[":
            inside = True
        elif c == "]":
            inside = False
        elif c == "," and not inside:
            parts.append(span(cs, start, i).trim())
            start = i + 1

        i += 1

    parts.append(span(cs, start, cs.length()).trim())
    return parts

# Splits an expression into signed terms. None when an operator has no term after it.
def split_terms(text: String) -> Optional[List[Term]]:
    let cs = text.chars()
    let n = cs.length()
    var terms = List[Term]()
    var negative = False
    var pending = False
    var start = 0
    var i = 0

    while i < n:
        let c = cs[i]

        if c == "'":
            let end = literal_end(cs, i)

            if end > 0:
                i = end
                continue

        if c == "+" or c == "-":
            let piece = span(cs, start, i).trim()

            if piece != "":
                terms.append(Term(negative: negative, text: piece))
                pending = False
            elif pending:
                return none

            negative = c == "-"
            pending = True
            start = i + 1

        i += 1

    let last = span(cs, start, n).trim()

    if last != "":
        terms.append(Term(negative: negative, text: last))
    elif pending:
        return none

    return terms

def parse_number(cs: List[String]) -> Int:
    var base = 10
    var start = 0

    if cs.length() > 2 and cs[0] == "0" and cs[1] == "x":
        base = 16
        start = 2
    elif cs.length() > 2 and cs[0] == "0" and cs[1] == "b":
        base = 2
        start = 2

    var value = 0

    for i in start..cs.length():
        let d = digit_value(cs[i])
        if d < 0 or d >= base:
            return NOT_A_NUMBER

        if value <= MAX_LITERAL:
            value = value * base + d

    if value > MAX_LITERAL:
        return TOO_BIG

    return value

def escape_value(c: String) -> Int:
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

# Value of a character literal such as 'a' or '\n'; -1 when malformed.
def char_value(cs: List[String]) -> Int:
    let n = cs.length()

    if n == 3 and cs[1] != "\\" and cs[1] != "'" and cs[2] == "'":
        let bs = cs[1].to_bytes()
        if bs.length() == 1:
            return bs.get(0).to_int()

        return -1

    if n == 4 and cs[1] == "\\" and cs[3] == "'":
        return escape_value(cs[2])

    return -1

def resolve(name: String, syms: Symbols, path: List[String]) -> Result[Int, Fault]:
    if let value = syms.labels.get(name):
        return ok(value)

    if let text = syms.equs.get(name):
        if path.contains(name):
            return fail("circular definition of '" + name + "'")

        var next = path.clone()
        next.append(name)
        return eval_expr(text, syms, next)

    return fail("undefined symbol '" + name + "'")

def term_value(text: String, syms: Symbols, path: List[String]) -> Result[Int, Fault]:
    let cs = text.chars()

    if DIGITS.contains(cs[0]):
        let value = parse_number(cs)
        if value == NOT_A_NUMBER:
            return fail(MALFORMED)
        if value == TOO_BIG:
            return fail("immediate out of range")

        return ok(value)

    if cs[0] == "'":
        let value = char_value(cs)
        if value < 0:
            return fail(MALFORMED)

        return ok(value)

    if ident_end(cs, 0) == cs.length():
        return resolve(text, syms, path)

    return fail(MALFORMED)

def sum_terms(
    text: String,
    terms: List[Term],
    syms: Symbols,
    path: List[String]
) -> Result[Int, Fault]:
    var total = 0

    for t in terms:
        let v = term_value(t.text.clone(), syms, path)

        if v.is_error():
            if v.err().text == MALFORMED:
                return fail("invalid expression '" + text + "'")

            return v

        if t.negative:
            total = wrap(total - v.get())
        else:
            total = wrap(total + v.get())

    return ok(total)

def eval_expr(text: String, syms: Symbols, path: List[String]) -> Result[Int, Fault]:
    if let terms = split_terms(text):
        if terms.length() > 0:
            return sum_terms(text, terms, syms, path)
    return fail("invalid expression '" + text + "'")

def parse_budget(text: String) -> Int:
    let cs = text.chars()
    if cs.length() == 0:
        return -1

    var value = 0

    for c in cs:
        if not DIGITS.contains(c):
            return -1

        if value <= MAX_BUDGET:
            value = value * 10 + digit_value(c)

    if value < 1 or value > MAX_BUDGET:
        return -1

    return value

def escape_bytes(text: String) -> Result[List[Int], Fault]:
    let cs = text.chars()
    let n = cs.length()
    var bytes = List[Int]()
    if n < 2 or cs[0] != "\"" or cs[n - 1] != "\"":
        return fail("invalid string")

    var i = 1

    while i < n - 1:
        let c = cs[i]
        if c == "\"":
            return fail("invalid string")

        if c == "\\":
            if i + 1 >= n - 1:
                return fail("invalid string")

            let e = escape_value(cs[i + 1])
            if e < 0:
                return fail("invalid string")

            bytes.append(e)
            i += 2
        else:
            let bs = c.to_bytes()
            for k in 0..bs.length():
                bytes.append(bs.get(k).to_int())
            i += 1

    return ok(bytes)

def memory_source(operand: String) -> Result[Source, Fault]:
    let bad = "invalid operand '" + operand + "'"
    let cs = operand.chars()
    let n = cs.length()
    if n < 2 or cs[n - 1] != "]":
        return fail(bad)

    let inner = span(cs, 1, n - 1)
    if inner.trim() == "" or inner.contains("[") or inner.contains("]"):
        return fail(bad)
    if let parts = split_terms(inner):
        return memory_terms(operand, parts)

    return fail(bad)

def memory_terms(operand: String, parts: List[Term]) -> Result[Source, Fault]:
    let bad = "invalid operand '" + operand + "'"
    var base = -1
    var constant = ""

    for t in parts:
        let r = reg_index(t.text)

        if r >= 0:
            if t.negative or base >= 0:
                return fail(bad)

            base = r
        else:
            let sign = "-" if t.negative else "+"

            constant += sign + t.text

    return ok(Source(kind: ARG_MEM, reg: base, text: constant))

def operand_source(text: String) -> Result[Source, Fault]:
    if text == "":
        return fail("invalid operand ''")

    let reg = reg_index(text)
    if reg >= 0:
        return ok(Source(kind: ARG_REG, reg: reg, text: text))
    if text.starts_with("["):
        return memory_source(text)

    return ok(Source(kind: ARG_IMM, reg: -1, text: text))

def opcode_of(name: String) -> Int:
    if name == "jz":
        return JE
    if name == "jnz":
        return JNE

    return MNEMONICS.index_of(name).get(-1)

def arity(code: Int) -> Int:
    if code == MOV or (code >= ADD and code <= CMP) or code == LEA:
        return 2
    if code == RET or code == HALT or code == NOP:
        return 0

    return 1

def kinds_allowed(code: Int, args: List[Source]) -> Bool:
    if args.length() == 0:
        return True

    let dst = args[0].kind
    if code == MOV:
        return dst == ARG_REG or (dst == ARG_MEM and args[1].kind != ARG_MEM)
    if code >= ADD and code <= CMP:
        return dst == ARG_REG
    if code == LEA:
        return dst == ARG_REG and args[1].kind == ARG_MEM
    if (code >= NEG and code <= DEC) or code == POP or code == IN:
        return dst == ARG_REG
    if code >= JMP and code <= CALL:
        return dst == ARG_IMM

    return True

def define_label(var asm: Assembly, name: String) -> Result[Unit, Fault]:
    if reg_index(name) >= 0:
        return fail("reserved name '" + name + "'")
    if asm.syms.labels.get(name).is_some() or asm.syms.defined_equs.get(name).is_some():
        return fail("duplicate symbol '" + name + "'")

    if asm.in_data:
        asm.syms.labels[name.clone()] = asm.data_ptr
    else:
        asm.syms.labels[name.clone()] = asm.instr_count
        if name == "main":
            asm.entry = asm.instr_count

    return ok(())

def define_equ(var asm: Assembly, rest: String) -> Result[Unit, Fault]:
    let ops = split_operands(rest)
    if ops.length() != 2:
        return fail("wrong number of operands for '.equ'")

    let name = ops[0]
    if not is_identifier(name):
        return fail("invalid operand '" + name + "'")
    if reg_index(name) >= 0:
        return fail("reserved name '" + name + "'")
    if asm.syms.labels.get(name).is_some() or asm.syms.defined_equs.get(name).is_some():
        return fail("duplicate symbol '" + name + "'")

    asm.syms.defined_equs[name.clone()] = True
    return ok(())

def preload_equs(var asm: Assembly, lines: List[Line]) -> Unit:
    for line in lines:
        if line.head == ".equ":
            let ops = split_operands(line.rest)
            if ops.length() == 2 and is_identifier(ops[0]) and reg_index(ops[0]) < 0:
                asm.syms.equs[ops[0].clone()] = ops[1].clone()

def reserve(var asm: Assembly, number: Int, texts: List[String], times: Int) -> Result[
    Unit, Fault
]:
    let words = texts.length() * times
    if asm.data_ptr + words > MEMORY_SIZE:
        return fail("data section too large")

    var args = List[Source]()
    for t in texts:
        args.append(Source(kind: ARG_IMM, reg: -1, text: t))
    asm.items.append(
        Item(
            line: number, code: -1, address: asm.data_ptr, times: times, args: args
        )
    )
    asm.data_ptr = asm.data_ptr + words
    return ok(())

def data_directive(var asm: Assembly, line: Line) -> Result[Unit, Fault]:
    let head = line.head

    if head == ".word":
        let ops = split_operands(line.rest)
        if ops.length() == 0:
            return fail("wrong number of operands for '.word'")

        return reserve(var asm, line.number, ops, 1)

    if head == ".ascii" or head == ".asciz":
        let bytes = try escape_bytes(line.rest)
        var texts = List[String]()
        for b in bytes:
            texts.append(b.to_string())
        if head == ".asciz":
            texts.append("0")
        return reserve(var asm, line.number, texts, 1)

    let ops = split_operands(line.rest)
    if ops.length() != 1 and ops.length() != 2:
        return fail("wrong number of operands for '.space'")

    let count = try eval_expr(ops[0], asm.syms, List[String]())
    if count < 0:
        return fail("invalid operand '" + ops[0] + "'")

    let fill = ops[1].clone() if ops.length() == 2 else "0"

    var texts = List[String]()
    texts.append(fill)
    return reserve(var asm, line.number, texts, count)

def directive(var asm: Assembly, line: Line) -> Result[Unit, Fault]:
    let head = line.head
    let rest = line.rest

    if head == ".text" or head == ".data":
        if rest != "":
            return fail("invalid operand '" + rest + "'")

        asm.in_data = head == ".data"
        return ok(())

    if head == ".equ":
        return define_equ(var asm, rest)

    if head == ".budget":
        let budget = parse_budget(rest)
        if budget < 0:
            return fail("invalid operand '" + rest + "'")

        asm.budget = budget
        return ok(())

    if head == ".word" or head == ".ascii" or head == ".asciz" or head == ".space":
        if not asm.in_data:
            return fail("data directive in text section")

        return data_directive(var asm, line)

    return fail("unknown directive '" + head + "'")

def instruction(var asm: Assembly, line: Line) -> Result[Unit, Fault]:
    if asm.in_data:
        return fail("instruction in data section")

    let code = opcode_of(line.head)
    if code < 0:
        return fail("unknown mnemonic '" + line.head + "'")

    var args = List[Source]()

    for text in split_operands(line.rest):
        let s = try operand_source(text)
        args.append(s)

    if args.length() != arity(code):
        return fail("wrong number of operands for '" + line.head + "'")
    if not kinds_allowed(code, args):
        return fail("invalid operands for '" + line.head + "'")

    asm.items.append(
        Item(line: line.number, code: code, address: 0, times: 1, args: args)
    )
    asm.instr_count += 1
    return ok(())

def pass1_line(var asm: Assembly, line: Line) -> Result[Unit, Fault]:
    for name in line.labels:
        let _ = try define_label(var asm, name.clone())
    if line.head == "":
        return ok(())
    if line.head.starts_with("."):
        return directive(var asm, line)

    return instruction(var asm, line)

def build_arg(s: Source, syms: Symbols) -> Result[Arg, Fault]:
    if s.kind == ARG_REG:
        return ok(Arg(kind: ARG_REG, reg: s.reg, value: 0))
    if s.kind == ARG_MEM and s.text == "":
        return ok(Arg(kind: ARG_MEM, reg: s.reg, value: 0))

    let value = try eval_expr(s.text, syms, List[String]())
    return ok(Arg(kind: s.kind, reg: s.reg, value: value))

def write_data(item: Item, syms: Symbols, var image: List[Int]) -> Result[Unit, Fault]:
    var values = List[Int]()

    for s in item.args:
        let v = try eval_expr(s.text, syms, List[String]())
        values.append(v)

    var k = 0

    for _r in 0..item.times:
        for v in values:
            image[item.address + k] = v
            k += 1

    return ok(())

def is_jump(code: Int) -> Bool:
    return code >= JMP and code <= CALL

def build_item(
    item: Item,
    syms: Symbols,
    instr_total: Int,
    var program: List[Instr],
    var image: List[Int]
) -> Result[Unit, Fault]:
    if item.code < 0:
        return write_data(item, syms, var image)

    var args = List[Arg]()

    for s in item.args:
        let a = try build_arg(s, syms)
        args.append(a)

    if is_jump(item.code):
        let target = args[0].value
        if target < 0 or target >= instr_total:
            return fail("invalid jump target")

    program.append(Instr(code: item.code, line: item.line, args: args))
    return ok(())

# Runtime

def initial_registers() -> List[Int]:
    var regs = List[Int]()
    for _i in 0..REG_COUNT:
        regs.append(0)
    regs[REG_SP] = MEMORY_SIZE
    return regs

def check_address(addr: Int) -> Result[Int, Fault]:
    if addr < 0 or addr >= MEMORY_SIZE:
        return fail("memory access out of range: " + addr.to_string())

    return ok(addr)

def address_of(m: Machine, a: Arg) -> Int:
    let base = m.regs[a.reg] if a.reg >= 0 else 0

    return wrap(base + a.value)

def read_arg(m: Machine, a: Arg) -> Result[Int, Fault]:
    if a.kind == ARG_REG:
        return ok(m.regs[a.reg])
    if a.kind == ARG_IMM:
        return ok(a.value)

    let addr = try check_address(address_of(m, a))
    return ok(m.mem[addr])

def write_arg(var m: Machine, a: Arg, v: Int) -> Result[Unit, Fault]:
    if a.kind == ARG_REG:
        m.regs[a.reg] = v
        return ok(())

    let addr = try check_address(address_of(m, a))
    m.mem[addr] = v
    return ok(())

def push_value(var m: Machine, v: Int) -> Result[Unit, Fault]:
    if m.regs[REG_SP] <= 0:
        return fail("stack overflow")

    m.regs[REG_SP] = m.regs[REG_SP] - 1

    let addr = try check_address(m.regs[REG_SP])
    m.mem[addr] = v
    return ok(())

def pop_value(var m: Machine) -> Result[Int, Fault]:
    if m.regs[REG_SP] >= MEMORY_SIZE:
        return fail("stack underflow")

    let addr = try check_address(m.regs[REG_SP])
    let v = m.mem[addr]
    m.regs[REG_SP] = m.regs[REG_SP] + 1
    return ok(v)

def arith(code: Int, x: Int, y: Int) -> Result[Int, Fault]:
    if code == ADD:
        return ok(wrap(x + y))
    if code == SUB:
        return ok(wrap(x - y))
    if code == MUL:
        return ok(wrap(x * y))

    if code == DIV:
        if y == 0:
            return fail("division by zero")

        return ok(wrap(x / y))

    if code == MOD:
        if y == 0:
            return fail("division by zero")

        return ok(wrap(x % y))

    if code == AND:
        return ok(bit_and(x, y))
    if code == OR:
        return ok(bit_or(x, y))
    if code == XOR:
        return ok(bit_xor(x, y))

    let count = bit_and(y, 31)
    if code == SHL:
        return ok(wrap(shift_left(x, count)))
    if code == SHR:
        return ok(wrap(shift_right(bit_and(x, MAX_LITERAL), count)))

    return ok(shift_right(x, count))

def unary(code: Int, x: Int) -> Int:
    if code == NEG:
        return wrap(-x)
    if code == NOT:
        return wrap(bit_not(x))
    if code == INC:
        return wrap(x + 1)

    return wrap(x - 1)

def jump_taken(code: Int, z: Bool, l: Bool) -> Bool:
    if code == JE:
        return z
    if code == JNE:
        return not z
    if code == JL:
        return l
    if code == JLE:
        return l or z
    if code == JG:
        return not l and not z
    if code == JGE:
        return not l

    return True

def emit_text(var m: Machine, v: Int) -> Unit:
    m.out.append_bytes((v.to_string() + "\n").to_bytes())
    m.last_char = 10

def emit_byte(var m: Machine, v: Int) -> Unit:
    if let b = v.to_uint8():
        m.out.append(b)
    m.last_char = v

# Runs one instruction and returns the next pc. Faults leave the machine at the same pc.
def execute(var m: Machine, ins: Instr) -> Result[Int, Fault]:
    let code = ins.code
    let args = ins.args
    let next = m.pc + 1
    if code == NOP:
        return ok(next)

    if code == MOV:
        let v = try read_arg(m, args[1])
        let _ = try write_arg(var m, args[0], v)
        return ok(next)

    if code >= ADD and code <= SAR:
        let src = try read_arg(m, args[1])
        let dst = args[0].reg
        let r = try arith(code, m.regs[dst], src)
        m.regs[dst] = r
        return ok(next)

    if code == CMP:
        let src = try read_arg(m, args[1])
        let x = m.regs[args[0].reg]
        m.z = x == src
        m.l = x < src
        return ok(next)

    if code >= NEG and code <= DEC:
        let dst = args[0].reg
        m.regs[dst] = unary(code, m.regs[dst])
        return ok(next)

    if code == LEA:
        m.regs[args[0].reg] = address_of(m, args[1])
        return ok(next)

    if code == PUSH:
        let v = try read_arg(m, args[0])
        let _ = try push_value(var m, v)
        return ok(next)

    if code == POP:
        let v = try pop_value(var m)
        let _ = try write_arg(var m, args[0], v)
        return ok(next)

    if code == IN:
        if m.next_input >= m.input.length():
            return fail("input exhausted")

        m.regs[args[0].reg] = m.input[m.next_input]
        m.next_input += 1
        return ok(next)

    if code == OUT:
        let v = try read_arg(m, args[0])
        emit_text(var m, v)
        return ok(next)

    if code == OUTC:
        let v = try read_arg(m, args[0])
        if v < 0 or v > 127:
            return fail("invalid character")

        emit_byte(var m, v)
        return ok(next)

    if code == RET:
        let v = try pop_value(var m)
        return ok(v)

    if code >= JMP and code <= CALL:
        if code == CALL:
            let _ = try push_value(var m, next)
        if jump_taken(code, m.z, m.l):
            return ok(args[0].value)

        return ok(next)

    return ok(next)

def register_summary(m: Machine) -> String:
    let names = REGISTER_NAMES.clone()
    var text = "regs:"
    for r in 0..REG_COUNT:
        text += " " + names[r] + "=" + m.regs[r].to_string()

    let z = 1 if m.z else 0

    let l = 1 if m.l else 0

    return text + "\nflags: Z=" + z.to_string() + " L=" + l.to_string() + "\n"

def run(
    program: List[Instr],
    image: List[Int],
    entry: Int,
    budget: Int,
    input: List[Int]
) -> Bytes:
    var m = Machine(
        regs: initial_registers(), mem: image, z: False, l: False, pc: entry,
        input: input, next_input: 0, out: BytesBuilder(), last_char: -1
    )
    var steps = 0
    var halted = False
    var message = ""

    while True:
        if steps == budget:
            message = "budget exceeded"
            break

        if m.pc < 0 or m.pc >= program.length():
            message = "pc out of range"
            break

        let ins = program[m.pc]

        if ins.code == HALT:
            steps += 1
            halted = True
            break

        let next = execute(var m, ins)

        if next.is_error():
            message = next.err().text.clone()
            break

        m.pc = next.get()
        steps += 1

    if m.last_char != -1 and m.last_char != 10:
        emit_byte(var m, 10)

    var summary = ""

    if halted:
        summary = "-- halted after " + steps.to_string() + " steps\n"
    else:
        let line = program[m.pc].line if m.pc >= 0 and m.pc < program.length() else - 1

        let line_text = "-" if line < 0 else line.to_string()

        summary = (
            "-- trap: "
            + message
            + " (pc="
            + m.pc.to_string()
            + " line="
            + line_text
            + ") after "
            + steps.to_string()
            + " steps\n"
        )

    m.out.append_bytes(summary.to_bytes())
    m.out.append_bytes(register_summary(m).to_bytes())
    return m.out.build()

# Input section

def split_words(line: String) -> List[String]:
    var words = List[String]()
    var word = ""

    for c in line.chars():
        if is_space(c):
            if word != "":
                words.append(word)
                word = ""
        else:
            word += c

    if word != "":
        words.append(word)
    return words

# Wrapped value of a whitespace-free token, or none if it is not a decimal integer.
def input_value(token: String) -> Optional[Int]:
    let cs = token.chars()
    var start = 0
    var negative = False

    if cs.length() > 0 and cs[0] == "-":
        negative = True
        start = 1

    if start >= cs.length():
        return none

    var magnitude = 0

    for i in start..cs.length():
        if not DIGITS.contains(cs[i]):
            return none

        magnitude = (magnitude * 10 + digit_value(cs[i])) % WORD

    if negative:
        return wrap(-magnitude)

    return wrap(magnitude)

def report(line: Int, message: String) -> Unit:
    var out = stdout()
    let _ = out.write(
        "asm error line " + line.to_string() + ": " + message + "\n"
    ).get()

export def main() -> Int:
    let lines = read_lines(stdin()).get()
    var source = List[String]()
    var input = List[Int]()
    var in_input = False

    for raw in lines:
        if in_input:
            for token in split_words(raw):
                if let v = input_value(token):
                    input.append(v)
        elif raw == "====":
            in_input = True
        else:
            source.append(raw)

    var parsed = List[Line]()
    for i in 0..source.length():
        parsed.append(split_line(i + 1, source[i]))

    var asm = Assembly(
        syms: Symbols(
            labels: Map[String, Int](), equs: Map[String, String](),
            defined_equs: Map[String, Bool]()
        ),
        items: List[Item](),
        in_data: False,
        instr_count: 0,
        data_ptr: 0,
        budget: DEFAULT_BUDGET,
        entry: 0
    )
    preload_equs(var asm, parsed)

    for line in parsed:
        let r = pass1_line(var asm, line)

        if r.is_error():
            report(line.number, r.err().text)
            return 0

    var image = List[Int]()
    for _i in 0..MEMORY_SIZE:
        image.append(0)

    var program = List[Instr]()

    for item in asm.items:
        let r = build_item(item, asm.syms, asm.instr_count, var program, var image)

        if r.is_error():
            report(item.line, r.err().text)
            return 0

    let output = run(program, image, asm.entry, asm.budget, input)
    var out = stdout()
    let _ = out.write_bytes(output).get()
    let _ = out.flush().get()
    return 0
