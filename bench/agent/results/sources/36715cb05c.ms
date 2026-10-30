import read_all, stdin, stdout from "@std/io.ms"
import range from "@std/collections.ms"
import BytesBuilder from "@std/bytes.ms"
import bit_and, bit_or, bit_xor, bit_not, shift_left, shift_right from "@std/bits.ms"

let WORD = 4294967296
let HALF = 2147483648
let MEM_WORDS = 4096
let BUDGET_MAX = 10000000
let DEFAULT_BUDGET = 100000
let K_REG = 0
let K_IMM = 1
let K_MEM = 2
# Opcode numbers are the indexes into MNEMONICS; jz and jnz are aliases of je and jne.
let MNEMONICS = [
    "mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar",
    "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je", "jne", "jl",
    "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt", "nop"
]

type AsmError:
    msg: String

impl Error for AsmError:
    fn message() String:
        return self.msg

type Operand:
    kind: Int
    reg: Int
    text: String

type Item:
    ln: Int
    kind: Int
    opc: Int
    addr: Int
    ops: List[Operand]
    exprs: List[String]
    vals: List[Int]
    cnt: Int

type Asm:
    section: Int
    ninstr: Int
    dcount: Int
    budget: Int
    items: List[Item]
    symbols: Map[String, Int]
    equ_text: Map[String, String]
    busy: Set[String]
    text_labels: Set[String]
    seen_equ: Set[String]
    equ_val: Map[String, Int]

type Machine:
    code: List[Int]
    mem: List[Int]
    regs: List[Int]
    inputs: List[Int]
    budget: Int
    n: Int
    pc: Int
    steps: Int
    z: Int
    l: Int
    in_pos: Int
    outbuf: BytesBuilder
    last: Int

fn ch(s: String, i: Int) Int:
    return s.scalar_at(i, some(0))

fn sub(s: String, start: Int, end: Int) String:
    return s.slice(start, end).get("")

fn is_digit(c: Int) Bool:
    return c >= 48 and c <= 57

fn is_ident_start(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_ident_char(c: Int) Bool:
    return is_ident_start(c) or is_digit(c) or c == 46

fn is_ident(s: String) Bool:
    let n = s.length()
    if n == 0 or not is_ident_start(ch(s, 0)):
        return false

    for i in range(1, n):
        if not is_ident_char(ch(s, i)):
            return false
    return true

fn wrap32(v: Int) Int:
    var m = v % WORD
    if m < 0:
        m += WORD
    if m >= HALF:
        m -= WORD
    return m

fn bool_int(b: Bool) Int:
    if b:
        return 1

    return 0

# Register indexes: r0..r7 are 0..7, sp is 8, bp is 9. Returns -1 for any other text.
fn reg_index(name: String) Int:
    if name == "sp":
        return 8
    if name == "bp":
        return 9

    if name.length() == 2 and ch(name, 0) == 114:
        let d = ch(name, 1) - 48
        if d >= 0 and d <= 7:
            return d

    return -1

fn strip_cr(s: String) String:
    let n = s.length()
    if n > 0 and ch(s, n - 1) == 13:
        return sub(s, 0, n - 1)

    return s

# Removes a ';' comment that is not inside a string or character literal.
fn strip_comment(line: String) String:
    let n = line.length()
    var i = 0
    var quote = 0

    while i < n:
        let c = ch(line, i)

        if quote == 0:
            if c == 59:
                return sub(line, 0, i)

            if c == 34 or c == 39:
                quote = c
            i += 1
        else if c == 92:
            i += 2
        else:
            if c == quote:
                quote = 0
            i += 1

    return line

# Index just past the character literal that starts at i, or i + 1 if it is not terminated.
fn char_end(s: String, i: Int) Int:
    let n = s.length()
    var j = i + 1

    if j < n and ch(s, j) == 92:
        j += 2
    else:
        j += 1

    if j < n and ch(s, j) == 39:
        return j + 1

    return i + 1

# Index of the first space or tab at or after 0, or the length of s.
fn word_end(s: String) Int:
    var i = 0
    while i < s.length() and ch(s, i) != 32 and ch(s, i) != 9:
        i += 1
    return i

# Length of the label name if s starts with "name:", otherwise 0.
fn label_len(s: String) Int:
    let n = s.length()
    if n == 0 or not is_ident_start(ch(s, 0)):
        return 0

    var k = 0
    while k < n and is_ident_char(ch(s, k)):
        k += 1
    if k < n and ch(s, k) == 58:
        return k

    return 0

# Splits an operand list at commas outside brackets and character literals.
fn split_args(s: String) List[String]:
    var out = List[String]()
    let n = s.length()
    if n == 0:
        return out

    var depth = 0
    var start = 0
    var i = 0

    while i < n:
        let c = ch(s, i)

        if c == 39:
            i = char_end(s, i)
        else if c == 91:
            depth += 1
            i += 1
        else if c == 93:
            depth -= 1
            i += 1
        else if c == 44 and depth == 0:
            out.append(sub(s, start, i).trim())
            start = i + 1
            i += 1
        else:
            i += 1

    out.append(sub(s, start, n).trim())
    return out

# Splits an expression into signed terms such as "+a" and "-1". Each term keeps its sign as the first character.
fn split_terms(text: String) List[String]:
    var terms = List[String]()
    let n = text.length()
    var sign = "+"
    var start = 0
    var i = 0

    while i < n:
        let c = ch(text, i)

        if c == 39:
            i = char_end(text, i)
        else if c == 43 or c == 45:
            if i > 0:
                terms.append(sign.concat(sub(text, start, i).trim()))
            sign = sub(text, i, i + 1)
            start = i + 1
            i += 1
        else:
            i += 1

    terms.append(sign.concat(sub(text, start, n).trim()))
    return terms

fn escape_value(c: Int) Int:
    if c == 110:
        return 10
    if c == 116:
        return 9
    if c == 48:
        return 0
    if c == 92 or c == 39 or c == 34:
        return c

    return -1

fn char_value(body: String, full: String) Result[Int, AsmError]:
    let n = body.length()

    if n >= 3 and ch(body, n - 1) == 39:
        let inner = sub(body, 1, n - 1)
        if (
            inner.length() == 1
            and ch(inner, 0) != 92
            and ch(inner, 0) != 39
            and ch(inner, 0) < 128
        ):
            return ok(ch(inner, 0))

        if inner.length() == 2 and ch(inner, 0) == 92:
            let v = escape_value(ch(inner, 1))
            if v >= 0:
                return ok(v)

    return error(AsmError(msg: "invalid expression '{full}'"))

fn digit_value(c: Int) Int:
    if c >= 48 and c <= 57:
        return c - 48
    if c >= 97 and c <= 102:
        return c - 87
    if c >= 65 and c <= 70:
        return c - 55

    return -1

fn number_value(body: String, full: String) Result[Int, AsmError]:
    let n = body.length()
    var base = 10
    var start = 0

    if n > 2 and ch(body, 0) == 48 and ch(body, 1) == 120:
        base = 16
        start = 2
    else if n > 2 and ch(body, 0) == 48 and ch(body, 1) == 98:
        base = 2
        start = 2

    for i in range(start, n):
        let d = digit_value(ch(body, i))
        if d < 0 or d >= base:
            return error(AsmError(msg: "invalid expression '{full}'"))

    var v = 0

    for i in range(start, n):
        v = v * base + digit_value(ch(body, i))
        if v > 4294967295:
            return error(AsmError(msg: "immediate out of range"))

    return ok(v)

fn symbol_value(var a: Asm, name: String) Result[Int, AsmError]:
    if a.symbols.contains(name):
        return ok(a.symbols.get_or(name, 0))
    if a.equ_val.contains(name):
        return ok(a.equ_val.get_or(name, 0))

    if a.equ_text.contains(name):
        if a.busy.contains(name):
            return error(AsmError(msg: "circular definition of '{name}'"))

        a.busy.add(name)

        let text = a.equ_text.get_or(name, "")
        let v = try eval_expr(var a, text)
        a.equ_val.add(name, v)
        return ok(v)

    return error(AsmError(msg: "undefined symbol '{name}'"))

fn term_value(var a: Asm, body: String, full: String) Result[Int, AsmError]:
    let c = ch(body, 0)
    if c == 39:
        return char_value(body, full)
    if is_digit(c):
        return number_value(body, full)
    if is_ident(body):
        return symbol_value(var a, body)

    return error(AsmError(msg: "invalid expression '{full}'"))

fn eval_expr(var a: Asm, text: String) Result[Int, AsmError]:
    let full = text.trim()
    var total = 0

    for t in split_terms(full):
        let body = sub(t, 1, t.length())
        if body.length() == 0:
            return error(AsmError(msg: "invalid expression '{full}'"))

        let v = try term_value(var a, body, full)

        if ch(t, 0) == 45:
            total -= v
        else:
            total += v

    return ok(wrap32(total))

fn parse_string(s: String) Result[List[Int], AsmError]:
    let n = s.length()
    var out = List[Int]()
    if n < 2 or ch(s, 0) != 34 or ch(s, n - 1) != 34:
        return error(AsmError(msg: "invalid string"))

    var i = 1

    while i < n - 1:
        let c = ch(s, i)

        if c == 92:
            if i + 1 >= n - 1:
                return error(AsmError(msg: "invalid string"))

            let v = escape_value(ch(s, i + 1))
            if v < 0:
                return error(AsmError(msg: "invalid string"))

            out.append(v)
            i += 2
        else if c == 34:
            return error(AsmError(msg: "invalid string"))
        else:
            let bytes = sub(s, i, i + 1).to_bytes()
            for j in range(0, bytes.length()):
                out.append(bytes.get(j))
            i += 1

    return ok(out)

fn parse_budget(s: String) Int:
    let n = s.length()
    if n == 0:
        return -1

    var v = 0

    for i in range(0, n):
        let c = ch(s, i)
        if not is_digit(c):
            return -1

        v = v * 10 + (c - 48)
        if v > BUDGET_MAX:
            return -1

    if v < 1:
        return -1

    return v

fn is_int_token(t: String) Bool:
    let n = t.length()
    var start = 0
    if n > 0 and ch(t, 0) == 45:
        start = 1
    if start >= n:
        return false

    for i in range(start, n):
        if not is_digit(ch(t, i)):
            return false
    return true

# Value of a token accepted by is_int_token, wrapped to 32 bits.
fn int_value(t: String) Int:
    var neg = false
    var start = 0

    if ch(t, 0) == 45:
        neg = true
        start = 1

    var acc = 0
    for i in range(start, t.length()):
        acc = (acc * 10 + (ch(t, i) - 48)) % WORD
    if neg:
        acc = (WORD - acc) % WORD
    return wrap32(acc)

fn parse_operand(arg: String) Result[Operand, AsmError]:
    if arg.length() == 0:
        return error(AsmError(msg: "invalid operand ''"))

    let r = reg_index(arg)
    if r >= 0:
        return ok(Operand(kind: K_REG, reg: r, text: ""))
    if ch(arg, 0) != 91:
        return ok(Operand(kind: K_IMM, reg: -1, text: arg))

    let n = arg.length()
    if n < 2 or ch(arg, n - 1) != 93:
        return error(AsmError(msg: "invalid operand '{arg}'"))

    let content = sub(arg, 1, n - 1).trim()
    if content.length() == 0:
        return error(AsmError(msg: "invalid operand '{arg}'"))

    var base = -1
    var exprs = List[String]()

    for t in split_terms(content):
        let body = sub(t, 1, t.length())
        let idx = reg_index(body)
        if body.length() == 0 or (idx >= 0 and (ch(t, 0) == 45 or base >= 0)):
            return error(AsmError(msg: "invalid operand '{arg}'"))

        if idx >= 0:
            base = idx
        else:
            exprs.append(t)

    return ok(Operand(kind: K_MEM, reg: base, text: exprs.join("")))

fn opcode_of(name: String) Int:
    if name == "jz":
        return 21
    if name == "jnz":
        return 22

    for i in range(0, MNEMONICS.length()):
        if MNEMONICS.get(i) == name:
            return i
    return -1

fn arity(opc: Int) Int:
    if opc <= 12 or opc == 17:
        return 2
    if opc == 28 or opc == 32 or opc == 33:
        return 0

    return 1

# Operand classes allowed for an instruction, checked after the operand count.
fn shape_ok(opc: Int, ops: List[Operand]) Bool:
    if arity(opc) == 0:
        return true

    let k0 = ops.get(0).kind

    if arity(opc) == 2:
        let k1 = ops.get(1).kind
        if opc == 0:
            return k0 != K_IMM and not (k0 == K_MEM and k1 == K_MEM)
        if opc == 17:
            return k0 == K_REG and k1 == K_MEM

        return k0 == K_REG

    if opc == 18 or opc == 30 or opc == 31:
        return true
    if opc >= 20 and opc <= 27:
        return k0 == K_IMM

    return k0 == K_REG

fn defined(a: Asm, name: String) Bool:
    return a.symbols.contains(name) or a.seen_equ.contains(name)

fn check_data_size(a: Asm) Result[Int, AsmError]:
    if a.dcount > MEM_WORDS:
        return error(AsmError(msg: "data section too large"))

    return ok(0)

fn instruction(var a: Asm, ln: Int, name: String, rest: String) Result[Int, AsmError]:
    if a.section == 1:
        return error(AsmError(msg: "instruction in data section"))

    let opc = opcode_of(name)
    if opc < 0:
        return error(AsmError(msg: "unknown mnemonic '{name}'"))

    let args = split_args(rest)
    var ops = List[Operand]()

    for arg in args:
        let o = try parse_operand(arg)
        ops.append(o)

    if ops.length() != arity(opc):
        return error(AsmError(msg: "wrong number of operands for '{name}'"))
    if not shape_ok(opc, ops):
        return error(AsmError(msg: "invalid operands for '{name}'"))

    a.items.append(
        Item(
            ln: ln, kind: 0, opc: opc, addr: a.ninstr, ops: ops, exprs: List[String](),
            vals: List[Int](), cnt: 0
        )
    )
    a.ninstr += 1
    return ok(0)

fn data_word(var a: Asm, ln: Int, rest: String) Result[Int, AsmError]:
    if a.section == 0:
        return error(AsmError(msg: "data directive in text section"))

    let exprs = split_args(rest)
    let words = exprs.length()
    if words == 0:
        return error(AsmError(msg: "wrong number of operands for '.word'"))

    a.items.append(
        Item(
            ln: ln, kind: 1, opc: 0, addr: a.dcount, ops: List[Operand](), exprs: exprs,
            vals: List[Int](), cnt: 0
        )
    )
    a.dcount += words
    return check_data_size(a)

fn data_string(var a: Asm, ln: Int, zero_term: Bool, rest: String) Result[Int, AsmError]:
    if a.section == 0:
        return error(AsmError(msg: "data directive in text section"))

    var vals = try parse_string(rest)
    if zero_term:
        vals.append(0)

    let words = vals.length()
    a.items.append(
        Item(
            ln: ln, kind: 2, opc: 0, addr: a.dcount, ops: List[Operand](),
            exprs: List[String](), vals: vals, cnt: 0
        )
    )
    a.dcount += words
    return check_data_size(a)

fn data_space(var a: Asm, ln: Int, rest: String) Result[Int, AsmError]:
    if a.section == 0:
        return error(AsmError(msg: "data directive in text section"))

    let args = split_args(rest)
    if args.length() == 0 or args.length() > 2:
        return error(AsmError(msg: "wrong number of operands for '.space'"))

    let count = try eval_expr(var a, args.get(0))
    if count < 0:
        return error(AsmError(msg: "invalid operand '{args.get(0)}'"))

    var fill = "0"
    if args.length() == 2:
        fill = args.get(1)

    var fills = List[String]()
    fills.append(fill)
    a.items.append(
        Item(
            ln: ln, kind: 3, opc: 0, addr: a.dcount, ops: List[Operand](), exprs: fills,
            vals: List[Int](), cnt: count
        )
    )
    a.dcount += count
    return check_data_size(a)

fn directive(var a: Asm, ln: Int, word: String, rest: String) Result[Int, AsmError]:
    if word == ".text" or word == ".data":
        if rest.length() > 0:
            return error(AsmError(msg: "invalid operand '{rest}'"))

        if word == ".text":
            a.section = 0
        else:
            a.section = 1

        return ok(0)

    if word == ".budget":
        let v = parse_budget(rest)
        if v < 0:
            return error(AsmError(msg: "invalid operand '{rest}'"))

        a.budget = v
        return ok(0)

    if word == ".equ":
        let args = split_args(rest)
        if args.length() != 2:
            return error(AsmError(msg: "wrong number of operands for '.equ'"))

        let nm = args.get(0)
        if not is_ident(nm):
            return error(AsmError(msg: "invalid operand '{nm}'"))
        if reg_index(nm) >= 0:
            return error(AsmError(msg: "reserved name '{nm}'"))
        if defined(a, nm):
            return error(AsmError(msg: "duplicate symbol '{nm}'"))

        a.seen_equ.add(nm)
        return ok(0)

    if word == ".word":
        return data_word(var a, ln, rest)
    if word == ".ascii":
        return data_string(var a, ln, false, rest)
    if word == ".asciz":
        return data_string(var a, ln, true, rest)
    if word == ".space":
        return data_space(var a, ln, rest)

    return error(AsmError(msg: "unknown directive '{word}'"))

fn line_pass1(var a: Asm, ln: Int, raw: String) Result[Int, AsmError]:
    var body = raw.trim()
    var k = label_len(body)

    while k > 0:
        let name = sub(body, 0, k)
        if reg_index(name) >= 0:
            return error(AsmError(msg: "reserved name '{name}'"))
        if defined(a, name):
            return error(AsmError(msg: "duplicate symbol '{name}'"))

        if a.section == 0:
            a.symbols.add(name, a.ninstr)
            a.text_labels.add(name)
        else:
            a.symbols.add(name, a.dcount)

        body = sub(body, k + 1, body.length()).trim()
        k = label_len(body)

    if body.length() == 0:
        return ok(0)

    let e = word_end(body)
    let word = sub(body, 0, e)
    let rest = sub(body, e, body.length()).trim()
    if ch(word, 0) == 46:
        return directive(var a, ln, word, rest)

    return instruction(var a, ln, word, rest)

# Value of an operand's expression: the immediate, or the memory displacement.
fn operand_value(var a: Asm, o: Operand) Result[Int, AsmError]:
    if o.kind == K_MEM and o.text.length() == 0:
        return ok(0)

    return eval_expr(var a, o.text)

fn is_jump(opc: Int) Bool:
    return opc >= 20 and opc <= 27

# Pass 2 for one item. Instructions append 8 slots to code: op, line, then (kind, reg, value) for two operands.
fn item_pass2(var a: Asm, var code: List[Int], var mem: List[Int], item: Item) Result[
    Int, AsmError
]:
    if item.kind == 0:
        code.append(item.opc)
        code.append(item.ln)

        for j in range(0, 2):
            if j < item.ops.length():
                let o = item.ops.get(j)
                var v = 0
                if o.kind != K_REG:
                    v = try operand_value(var a, o)
                if is_jump(item.opc) and (v < 0 or v >= a.ninstr):
                    return error(AsmError(msg: "invalid jump target"))

                code.append(o.kind)
                code.append(o.reg)
                code.append(v)
            else:
                code.append(0)
                code.append(0)
                code.append(0)

        return ok(0)

    if item.kind == 1:
        for j in range(0, item.exprs.length()):
            let v = try eval_expr(var a, item.exprs.get(j))
            mem.set(item.addr + j, v)

        return ok(0)

    if item.kind == 2:
        for j in range(0, item.vals.length()):
            mem.set(item.addr + j, item.vals.get(j))
        return ok(0)

    let fill = try eval_expr(var a, item.exprs.get(0))
    for j in range(0, item.cnt):
        mem.set(item.addr + j, fill)
    return ok(0)

fn alu(opc: Int, x: Int, y: Int) Result[Int, AsmError]:
    if opc == 1:
        return ok(wrap32(x + y))
    if opc == 2:
        return ok(wrap32(x - y))
    if opc == 3:
        return ok(wrap32(x * y))

    if opc == 4 or opc == 5:
        if y == 0:
            return error(AsmError(msg: "division by zero"))
        if opc == 4:
            return ok(wrap32(x / y))

        return ok(wrap32(x % y))

    if opc == 6:
        return ok(bit_and(x, y))
    if opc == 7:
        return ok(bit_or(x, y))
    if opc == 8:
        return ok(bit_xor(x, y))

    let c = bit_and(y, 31)
    if opc == 9:
        return ok(wrap32(shift_left(x, c)))
    if opc == 10:
        return ok(wrap32(shift_right(bit_and(x, 4294967295), c)))

    return ok(shift_right(x, c))

fn mem_read(var vm: Machine, addr: Int) Result[Int, AsmError]:
    if addr < 0 or addr >= MEM_WORDS:
        return error(AsmError(msg: "memory access out of range: {addr}"))

    return ok(vm.mem.get(addr))

fn mem_write(var vm: Machine, addr: Int, value: Int) Result[Int, AsmError]:
    if addr < 0 or addr >= MEM_WORDS:
        return error(AsmError(msg: "memory access out of range: {addr}"))

    vm.mem.set(addr, value)
    return ok(0)

# Effective address of operand slot s in the instruction at base.
fn ea(var vm: Machine, base: Int, s: Int) Int:
    let r = vm.code.get(base + 3 + 3 * s)
    var addr = vm.code.get(base + 4 + 3 * s)
    if r >= 0:
        addr += vm.regs.get(r)
    return wrap32(addr)

fn read_op(var vm: Machine, base: Int, s: Int) Result[Int, AsmError]:
    let k = vm.code.get(base + 2 + 3 * s)
    if k == K_REG:
        return ok(vm.regs.get(vm.code.get(base + 3 + 3 * s)))
    if k == K_IMM:
        return ok(vm.code.get(base + 4 + 3 * s))

    let addr = ea(var vm, base, s)
    return mem_read(var vm, addr)

fn write_op(var vm: Machine, base: Int, s: Int, value: Int) Result[Int, AsmError]:
    let k = vm.code.get(base + 2 + 3 * s)

    if k == K_REG:
        vm.regs.set(vm.code.get(base + 3 + 3 * s), value)
        return ok(0)

    let addr = ea(var vm, base, s)
    return mem_write(var vm, addr, value)

fn jump_taken(opc: Int, z: Int, l: Int) Bool:
    if opc == 20:
        return true
    if opc == 21:
        return z == 1
    if opc == 22:
        return z == 0
    if opc == 23:
        return l == 1
    if opc == 24:
        return l == 1 or z == 1
    if opc == 25:
        return l == 0 and z == 0

    return l == 0

# Executes one instruction. Ok(1) means halt; an error is a trap message.
fn step(var vm: Machine) Result[Int, AsmError]:
    let base = vm.pc * 8
    let opc = vm.code.get(base)
    var next = vm.pc + 1

    if opc == 0:
        let v = try read_op(var vm, base, 1)
        let stored = try write_op(var vm, base, 0, v)
    else if opc <= 11:
        let src = try read_op(var vm, base, 1)
        let dst = vm.code.get(base + 3)
        let res = try alu(opc, vm.regs.get(dst), src)
        vm.regs.set(dst, res)
    else if opc == 12:
        let src = try read_op(var vm, base, 1)
        let x = vm.regs.get(vm.code.get(base + 3))
        vm.z = bool_int(x == src)
        vm.l = bool_int(x < src)
    else if opc >= 13 and opc <= 16:
        let dst = vm.code.get(base + 3)
        let x = vm.regs.get(dst)

        if opc == 13:
            vm.regs.set(dst, wrap32(0 - x))
        else if opc == 14:
            vm.regs.set(dst, bit_not(x))
        else if opc == 15:
            vm.regs.set(dst, wrap32(x + 1))
        else:
            vm.regs.set(dst, wrap32(x - 1))
    else if opc == 17:
        let addr = ea(var vm, base, 1)
        vm.regs.set(vm.code.get(base + 3), addr)
    else if opc == 18:
        let v = try read_op(var vm, base, 0)
        let sp = vm.regs.get(8)
        if sp <= 0:
            return error(AsmError(msg: "stack overflow"))

        vm.regs.set(8, sp - 1)

        let stored = try mem_write(var vm, sp - 1, v)
    else if opc == 19:
        let sp = vm.regs.get(8)
        if sp >= MEM_WORDS:
            return error(AsmError(msg: "stack underflow"))

        let v = try mem_read(var vm, sp)
        vm.regs.set(8, sp + 1)

        let stored = try write_op(var vm, base, 0, v)
    else if opc >= 20 and opc <= 26:
        let target = try read_op(var vm, base, 0)
        if jump_taken(opc, vm.z, vm.l):
            next = target
    else if opc == 27:
        let target = try read_op(var vm, base, 0)
        let sp = vm.regs.get(8)
        if sp <= 0:
            return error(AsmError(msg: "stack overflow"))

        let ret_addr = vm.pc + 1
        vm.regs.set(8, sp - 1)

        let stored = try mem_write(var vm, sp - 1, ret_addr)
        next = target
    else if opc == 28:
        let sp = vm.regs.get(8)
        if sp >= MEM_WORDS:
            return error(AsmError(msg: "stack underflow"))

        next = try mem_read(var vm, sp)
        vm.regs.set(8, sp + 1)
    else if opc == 29:
        if vm.in_pos >= vm.inputs.length():
            return error(AsmError(msg: "input exhausted"))

        let v = vm.inputs.get(vm.in_pos)
        vm.in_pos += 1

        let stored = try write_op(var vm, base, 0, v)
    else if opc == 30:
        let v = try read_op(var vm, base, 0)
        vm.outbuf.concat(v.to_string_radix(10).to_bytes())
        vm.outbuf.append(10)
        vm.last = 10
    else if opc == 31:
        let v = try read_op(var vm, base, 0)
        if v < 0 or v > 127:
            return error(AsmError(msg: "invalid character"))

        vm.outbuf.append(v)
        vm.last = v
    else if opc == 32:
        vm.steps += 1
        return ok(1)

    vm.pc = next
    vm.steps += 1
    return ok(0)

fn trap_text(vm: Machine, msg: String) String:
    var line = "-"
    if vm.pc >= 0 and vm.pc < vm.n:
        line = "{vm.code.get(vm.pc * 8 + 1)}"
    return "-- trap: {msg} (pc={vm.pc} line={line}) after {vm.steps} steps"

# Runs until halt or trap and returns the first summary line.
fn run(var vm: Machine) String:
    while true:
        if vm.steps == vm.budget:
            return trap_text(vm, "budget exceeded")
        if vm.pc < 0 or vm.pc >= vm.n:
            return "-- trap: pc out of range (pc={vm.pc} line=-) after {vm.steps} steps"

        let r = step(var vm)
        if r.is_error():
            return trap_text(vm, r.err().msg)
        if r.get(0) == 1:
            return "-- halted after {vm.steps} steps"

    return ""

# Records every .equ name and expression before pass 1, so .space counts can use constants defined further down.
fn prescan_equ(var a: Asm, raw: String) Int:
    var body = raw.trim()
    var k = label_len(body)

    while k > 0:
        body = sub(body, k + 1, body.length()).trim()
        k = label_len(body)

    let e = word_end(body)
    if sub(body, 0, e) != ".equ":
        return 0

    let args = split_args(sub(body, e, body.length()).trim())
    if (
        args.length() == 2
        and is_ident(args.get(0))
        and not a.equ_text.contains(args.get(0))
    ):
        a.equ_text.add(args.get(0), args.get(1))
    return 0

fn report(ln: Int, msg: String) Int:
    stdout().write("asm error line {ln}: {msg}\n")
    stdout().flush()
    return 0

export fn main() Int:
    let data = read_all(stdin()).get()
    let lines = data.decode_utf8().get("").split("\n")
    var src_end = lines.length()
    for i in range(0, lines.length()):
        if src_end == lines.length() and strip_cr(lines.get(i)) == "====":
            src_end = i

    var inputs = List[Int]()
    for i in range(src_end + 1, lines.length()):
        for piece in lines.get(i).replace("\t", " ").replace("\r", " ").split(" "):
            if is_int_token(piece):
                inputs.append(int_value(piece))

    var a = Asm(
        section: 0, ninstr: 0, dcount: 0, budget: DEFAULT_BUDGET, items: List[Item](),
        symbols: Map[String, Int](), equ_text: Map[String, String](),
        busy: Set[String](), text_labels: Set[String](), seen_equ: Set[String](),
        equ_val: Map[String, Int]()
    )
    for i in range(0, src_end):
        prescan_equ(var a, strip_comment(strip_cr(lines.get(i))))

    for i in range(0, src_end):
        let r1 = line_pass1(var a, i + 1, strip_comment(strip_cr(lines.get(i))))
        if r1.is_error():
            return report(i + 1, r1.err().msg)

    var code = List[Int]()
    var mem = List[Int]()
    for m in range(0, MEM_WORDS):
        mem.append(0)

    for i in range(0, a.items.length()):
        let item = a.items.get(i).clone()
        let r2 = item_pass2(var a, var code, var mem, item)
        if r2.is_error():
            return report(item.ln, r2.err().msg)

    var start = 0
    if a.text_labels.contains("main"):
        start = a.symbols.get_or("main", 0)

    var regs = List[Int]()
    for r in range(0, 10):
        regs.append(0)
    regs.set(8, MEM_WORDS)

    var vm = Machine(
        code: code, mem: mem, regs: regs, inputs: inputs, budget: a.budget, n: a.ninstr,
        pc: start, steps: 0, z: 0, l: 0, in_pos: 0, outbuf: BytesBuilder(), last: -1
    )
    let status = run(var vm)
    if vm.last != -1 and vm.last != 10:
        vm.outbuf.append(10)

    let body = vm.outbuf.build()
    stdout().write_bytes(body)

    let rv = vm.regs
    let summary = "{status}\nregs: r0={rv.get(0)} r1={rv.get(1)} r2={rv.get(2)} r3={rv.get(3)} r4={rv.get(4)} r5={rv.get(5)} r6={rv.get(6)} r7={rv.get(7)} sp={rv.get(8)} bp={rv.get(9)}\nflags: Z={vm.z} L={vm.l}\n"
    stdout().write(summary)
    stdout().flush()
    return 0
