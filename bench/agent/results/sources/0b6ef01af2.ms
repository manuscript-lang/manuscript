import read_all from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"
import from_scalars from "@std/string.ms"
import bit_and, bit_or, bit_xor, bit_not, shift_left, shift_right, shift_right_unsigned from "@std/math/math.ms"

// ---------- records ----------

type Sym:
    kind: Int      // 0 = text label, 1 = data label, 2 = .equ
    value: Int
    expr: String   // .equ expression text

type Opnd:
    kind: Int      // 0 = register (or absent), 1 = immediate, 2 = memory
    reg: Int       // register index; memory base register (-1 for none)
    expr: String   // immediate expression, or memory displacement expression

type Pend:
    kind: Int      // 0 = instruction, 1 = data word
    line: Int
    op: Int
    a: Opnd
    b: Opnd
    addr: Int      // data word address
    expr: String   // data word expression

type Code:
    op: Int
    line: Int
    ka: Int
    ra: Int
    va: Int
    kb: Int
    rb: Int
    vb: Int

type Asm:
    section: Int   // 0 = text, 1 = data
    tcount: Int
    daddr: Int
    budget: Int
    syms: Map[String, Sym]
    pend: List[Pend]
    err: String

// ---------- small helpers ----------

fn wrap(x: Int) Int:
    let u = bit_and(x, 4294967295)
    if u >= 2147483648:
        return u - 4294967296
    return u

fn asm_err(lineno: Int, msg: String) String:
    return "asm error line " + lineno.to_string_radix(10) + ": " + msg

fn none_opnd() Opnd:
    return Opnd(kind: 0, reg: -1, expr: "")

fn reg_index(name: String) Int:
    let names = ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]
    if let i = names.index_of(name):
        return i
    return -1

fn is_digit(c: String) Bool:
    return "0123456789".contains(c)

fn is_alpha(c: String) Bool:
    return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_".contains(c)

fn is_ident_char(c: String) Bool:
    return is_alpha(c) or is_digit(c) or c == "."

fn is_ident(s: String) Bool:
    if s.is_empty():
        return false
    let cs = s.chars()
    if not is_alpha(cs[0]):
        return false
    for i in 1..cs.length():
        if not is_ident_char(cs[i]):
            return false
    return true

fn is_all_digits(s: String) Bool:
    if s.is_empty():
        return false
    for c in s.chars():
        if not is_digit(c):
            return false
    return true

fn digit_value(c: String) Int:
    if let i = "0123456789abcdef".index_of(c.lower()):
        return i
    return 99

// Byte value of a one-character escape (after the backslash), or -1.
fn escape_byte(c: String) Int:
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

fn char_bytes(c: String) List[Int]:
    var out = List[Int]()
    for b in c.to_bytes().values():
        out.append(b.to_int())
    return out

fn mem_trap(addr: Int) String:
    return "memory access out of range: " + addr.to_string_radix(10)

// Splits an expression into signed terms: each entry is a sign ("+" or "-") followed by term text.
fn split_signed(text: String) List[String]:
    var out = List[String]()
    var sign = "+"
    var cur = ""
    var quote = ""
    var esc = false
    var pos = 0
    for c in text.chars():
        if quote != "":
            cur = cur + c
            if esc:
                esc = false
            else if c == "\\":
                esc = true
            else if c == quote:
                quote = ""
        else if c == "'":
            quote = c.clone()
            cur = cur + c
        else if c == "+" or c == "-":
            if pos == 0:
                sign = c
            else:
                out.append(sign + cur)
                sign = c
                cur = ""
        else:
            cur = cur + c
        pos += 1
    out.append(sign + cur)
    return out

// Splits operands at commas that are outside brackets, character literals and strings.
fn split_commas(text: String) List[String]:
    var out = List[String]()
    let t = text.trim()
    if t == "":
        return out
    var cur = ""
    var quote = ""
    var esc = false
    var depth = 0
    for c in t.chars():
        if quote != "":
            cur = cur + c
            if esc:
                esc = false
            else if c == "\\":
                esc = true
            else if c == quote:
                quote = ""
        else if c == "'" or c == "\"":
            quote = c.clone()
            cur = cur + c
        else if c == "[":
            depth += 1
            cur = cur + c
        else if c == "]":
            depth -= 1
            cur = cur + c
        else if c == "," and depth == 0:
            out.append(cur.trim())
            cur = ""
        else:
            cur = cur + c
    out.append(cur.trim())
    return out

// Removes a ';' comment that is not inside a string or character literal.
fn strip_comment(raw: String) String:
    var cur = ""
    var quote = ""
    var esc = false
    for c in raw.chars():
        if quote != "":
            cur = cur + c
            if esc:
                esc = false
            else if c == "\\":
                esc = true
            else if c == quote:
                quote = ""
        else if c == ";":
            return cur
        else if c == "'" or c == "\"":
            quote = c.clone()
            cur = cur + c
        else:
            cur = cur + c
    return cur

// Index of the ':' ending a leading label, or -1.
fn label_end(s: String) Int:
    let cs = s.chars()
    if cs.is_empty() or not is_alpha(cs[0]):
        return -1
    var i = 1
    while i < cs.length() and is_ident_char(cs[i]):
        i += 1
    if i < cs.length() and cs[i] == ":":
        return i
    return -1

fn first_word(s: String) String:
    var w = ""
    for c in s.chars():
        if c == " " or c == "\t":
            return w
        w = w + c
    return w

// ---------- expressions ----------

// Value of a character literal such as 'a' or '\n', or -1.
fn char_value(t: String) Int:
    let cs = t.chars()
    if cs.length() == 3 and cs[0] == "'" and cs[2] == "'" and cs[1] != "\\":
        let bs = char_bytes(cs[1])
        if bs.length() == 1:
            return bs[0]
        return -1
    if cs.length() == 4 and cs[0] == "'" and cs[1] == "\\" and cs[3] == "'":
        return escape_byte(cs[2])
    return -1

// Parses a decimal, 0x or 0b literal. status: 0 ok, 1 malformed, 2 out of range.
fn parse_number(t: String, var status: Int) Int:
    let cs = t.chars()
    let n = cs.length()
    var base = 10
    var start = 0
    if n >= 2 and cs[0] == "0" and (cs[1] == "x" or cs[1] == "X"):
        base = 16
        start = 2
    else if n >= 2 and cs[0] == "0" and (cs[1] == "b" or cs[1] == "B"):
        base = 2
        start = 2
    if start == n:
        status = 1
        return 0
    var acc = 0
    var big = false
    for i in start..n:
        let d = digit_value(cs[i])
        if d >= base:
            status = 1
            return 0
        if not big:
            acc = acc * base + d
            if acc > 4294967295:
                big = true
    if big:
        status = 2
        return 0
    return acc

fn eval_term(t: String, whole: String, syms: Map[String, Sym], visiting: List[String], var err: String) Int:
    let cs = t.chars()
    let c0 = cs[0]
    if c0 == "'":
        let v = char_value(t)
        if v < 0:
            err = "invalid expression '" + whole + "'"
            return 0
        return v
    if is_digit(c0):
        var status = 0
        let v = parse_number(t, var status)
        if status == 1:
            err = "invalid expression '" + whole + "'"
            return 0
        if status == 2:
            err = "immediate out of range"
            return 0
        return v
    if is_alpha(c0):
        if not is_ident(t):
            err = "invalid expression '" + whole + "'"
            return 0
        if let s = syms.get(t):
            if s.kind == 2:
                if visiting.contains(t):
                    err = "circular definition of '" + t + "'"
                    return 0
                var nv = visiting.clone()
                nv.append(t.clone())
                return eval_expr(s.expr, syms, nv, var err)
            return s.value
        err = "undefined symbol '" + t + "'"
        return 0
    err = "invalid expression '" + whole + "'"
    return 0

fn eval_expr(text: String, syms: Map[String, Sym], visiting: List[String], var err: String) Int:
    let whole = text.trim()
    var acc = 0
    for e in split_signed(whole):
        let t = e.drop(1).trim()
        if t == "":
            err = "invalid expression '" + whole + "'"
            return 0
        let v = eval_term(t, whole, syms, visiting, var err)
        if err != "":
            return 0
        if e.take(1) == "-":
            acc = wrap(acc - v)
        else:
            acc = wrap(acc + v)
    return acc

fn eval_opnd(o: Opnd, syms: Map[String, Sym], var err: String) Int:
    if o.kind == 0:
        return 0
    return eval_expr(o.expr, syms, List[String](), var err)

// ---------- operands and instruction table ----------

// Operand syntax. Kinds: 0 register, 1 immediate, 2 memory.
fn parse_operand(p: String, var err: String) Opnd:
    if p == "":
        err = "invalid operand ''"
        return none_opnd()
    if p.starts_with("["):
        if p.length() < 2 or not p.ends_with("]"):
            err = "invalid operand '" + p + "'"
            return none_opnd()
        let inner = p.drop(1).take(p.length() - 2).trim()
        if inner == "":
            err = "invalid operand '" + p + "'"
            return none_opnd()
        var base = -1
        var disp = ""
        for e in split_signed(inner):
            let sign = e.take(1)
            let t = e.drop(1).trim()
            if t == "" or t.contains("[") or t.contains("]"):
                err = "invalid operand '" + p + "'"
                return none_opnd()
            let r = reg_index(t)
            if r >= 0:
                if sign == "-" or base >= 0:
                    err = "invalid operand '" + p + "'"
                    return none_opnd()
                base = r
            else:
                disp = disp + sign + t
        if disp == "":
            disp = "0"
        return Opnd(kind: 2, reg: base, expr: disp)
    if p.contains("[") or p.contains("]"):
        err = "invalid operand '" + p + "'"
        return none_opnd()
    let r = reg_index(p)
    if r >= 0:
        return Opnd(kind: 0, reg: r, expr: "")
    return Opnd(kind: 1, reg: -1, expr: p)

// Opcode numbers: 0 mov, 1 add, 2 sub, 3 mul, 4 div, 5 mod, 6 and, 7 or, 8 xor, 9 shl, 10 shr,
// 11 sar, 12 cmp, 13 neg, 14 not, 15 inc, 16 dec, 17 lea, 18 push, 19 pop, 20 je, 21 jne, 22 jl,
// 23 jle, 24 jg, 25 jge, 26 jmp, 27 call, 28 ret, 29 in, 30 out, 31 outc, 32 halt, 33 nop.
fn opcode(name: String) Int:
    let names = ["mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar", "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "je", "jne", "jl", "jle", "jg", "jge", "jmp", "call", "ret", "in", "out", "outc", "halt", "nop", "jz", "jnz"]
    let codes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 20, 21]
    if let i = names.index_of(name):
        return codes[i]
    return -1

fn arity(op: Int) Int:
    if op <= 12 or op == 17:
        return 2
    if op == 28 or op == 32 or op == 33:
        return 0
    return 1

// Operand classes for an instruction whose operand count already matches.
fn classes_ok(op: Int, ka: Int, kb: Int) Bool:
    if op == 0:
        if ka == 0:
            return true
        if ka == 2:
            return kb != 2
        return false
    if op <= 12:
        return ka == 0
    if op == 17:
        return ka == 0 and kb == 2
    if op >= 13 and op <= 16:
        return ka == 0
    if op == 19 or op == 29:
        return ka == 0
    if op >= 20 and op <= 27:
        return ka == 1
    return true

// ---------- pass 1: labels, directives, instruction shapes ----------

fn parse_string(rest: String, var err: String) List[Int]:
    var out = List[Int]()
    let cs = rest.trim().chars()
    if cs.length() < 2 or cs[0] != "\"" or cs[cs.length() - 1] != "\"":
        err = "invalid string"
        return out
    let last = cs.length() - 1
    var esc = false
    for i in 1..last:
        let c = cs[i]
        if esc:
            let v = escape_byte(c)
            if v < 0:
                err = "invalid string"
                return out
            out.append(v)
            esc = false
        else if c == "\\":
            esc = true
        else if c == "\"":
            err = "invalid string"
            return out
        else:
            for b in char_bytes(c):
                out.append(b)
    if esc:
        err = "invalid string"
    return out

fn pass1_directive(var st: Asm, lineno: Int, word: String, rest: String) Unit:
    if word == ".text" or word == ".data":
        if rest != "":
            st.err = asm_err(lineno, "invalid operand '" + rest + "'")
            return
        if word == ".text":
            st.section = 0
        else:
            st.section = 1
        return
    if word == ".equ":
        let parts = split_commas(rest)
        if parts.length() != 2:
            st.err = asm_err(lineno, "wrong number of operands for '.equ'")
            return
        let name = parts[0].clone()
        if not is_ident(name):
            st.err = asm_err(lineno, "invalid operand '" + name + "'")
            return
        if reg_index(name) >= 0:
            st.err = asm_err(lineno, "reserved name '" + name + "'")
            return
        if st.syms.contains(name):
            st.err = asm_err(lineno, "duplicate symbol '" + name + "'")
            return
        st.syms.add(name.clone(), Sym(kind: 2, value: 0, expr: parts[1].clone()))
        return
    if word == ".budget":
        var status = 0
        var v = 0
        let digits = is_all_digits(rest)
        if digits:
            v = parse_number(rest, var status)
        if not digits or status != 0 or v < 1 or v > 10000000:
            st.err = asm_err(lineno, "invalid operand '" + rest + "'")
            return
        st.budget = v
        return
    if word == ".word" or word == ".ascii" or word == ".asciz" or word == ".space":
        if st.section != 1:
            st.err = asm_err(lineno, "data directive in text section")
            return
    if word == ".word":
        let parts = split_commas(rest)
        if parts.length() == 0:
            st.err = asm_err(lineno, "wrong number of operands for '.word'")
            return
        if st.daddr + parts.length() > 4096:
            st.err = asm_err(lineno, "data section too large")
            return
        for p in parts:
            st.pend.append(Pend(kind: 1, line: lineno, op: 0, a: none_opnd(), b: none_opnd(), addr: st.daddr, expr: p.clone()))
            st.daddr += 1
        return
    if word == ".ascii" or word == ".asciz":
        var err = ""
        var bytes = parse_string(rest, var err)
        if err != "":
            st.err = asm_err(lineno, err)
            return
        if word == ".asciz":
            bytes.append(0)
        if st.daddr + bytes.length() > 4096:
            st.err = asm_err(lineno, "data section too large")
            return
        for b in bytes:
            st.pend.append(Pend(kind: 1, line: lineno, op: 0, a: none_opnd(), b: none_opnd(), addr: st.daddr, expr: b.to_string_radix(10)))
            st.daddr += 1
        return
    if word == ".space":
        let parts = split_commas(rest)
        if parts.length() != 1 and parts.length() != 2:
            st.err = asm_err(lineno, "wrong number of operands for '.space'")
            return
        var err = ""
        let n = eval_expr(parts[0], st.syms, List[String](), var err)
        if err != "":
            st.err = asm_err(lineno, err)
            return
        if n < 0:
            st.err = asm_err(lineno, "invalid operand '" + parts[0] + "'")
            return
        if st.daddr + n > 4096:
            st.err = asm_err(lineno, "data section too large")
            return
        var fill = "0"
        if parts.length() == 2:
            fill = parts[1].clone()
        for i in 0..n:
            st.pend.append(Pend(kind: 1, line: lineno, op: 0, a: none_opnd(), b: none_opnd(), addr: st.daddr, expr: fill.clone()))
            st.daddr += 1
        return
    st.err = asm_err(lineno, "unknown directive '" + word + "'")

fn pass1_instr(var st: Asm, lineno: Int, word: String, rest: String) Unit:
    if st.section == 1:
        st.err = asm_err(lineno, "instruction in data section")
        return
    let op = opcode(word)
    if op < 0:
        st.err = asm_err(lineno, "unknown mnemonic '" + word + "'")
        return
    var opnds = List[Opnd]()
    var err = ""
    for p in split_commas(rest):
        let o = parse_operand(p, var err)
        if err != "":
            st.err = asm_err(lineno, err)
            return
        opnds.append(o)
    if opnds.length() != arity(op):
        st.err = asm_err(lineno, "wrong number of operands for '" + word + "'")
        return
    var a = none_opnd()
    var b = none_opnd()
    if opnds.length() >= 1:
        a = opnds[0].clone()
    if opnds.length() >= 2:
        b = opnds[1].clone()
    if not classes_ok(op, a.kind, b.kind):
        st.err = asm_err(lineno, "invalid operands for '" + word + "'")
        return
    st.pend.append(Pend(kind: 0, line: lineno, op: op, a: a, b: b, addr: 0, expr: ""))
    st.tcount += 1

fn pass1_line(var st: Asm, lineno: Int, raw: String) Unit:
    var s = strip_comment(raw).trim()
    var e = label_end(s)
    while e >= 0:
        let name = s.take(e)
        if reg_index(name) >= 0:
            st.err = asm_err(lineno, "reserved name '" + name + "'")
            return
        if st.syms.contains(name):
            st.err = asm_err(lineno, "duplicate symbol '" + name + "'")
            return
        if st.section == 0:
            st.syms.add(name.clone(), Sym(kind: 0, value: st.tcount, expr: ""))
        else:
            st.syms.add(name.clone(), Sym(kind: 1, value: st.daddr, expr: ""))
        s = s.drop(e + 1).trim()
        e = label_end(s)
    if s == "":
        return
    let word = first_word(s)
    let rest = s.drop(word.length()).trim()
    if word.starts_with("."):
        pass1_directive(var st, lineno, word, rest)
    else:
        pass1_instr(var st, lineno, word, rest)

// ---------- pass 2: evaluate expressions, build code and data ----------

fn pass2(st: Asm, var mem: List[Int], var code: List[Code]) String:
    var err = ""
    for p in st.pend:
        if p.kind == 1:
            let v = eval_expr(p.expr, st.syms, List[String](), var err)
            if err != "":
                return asm_err(p.line, err)
            mem[p.addr] = v
        else:
            let va = eval_opnd(p.a, st.syms, var err)
            if err != "":
                return asm_err(p.line, err)
            let vb = eval_opnd(p.b, st.syms, var err)
            if err != "":
                return asm_err(p.line, err)
            if p.op >= 20 and p.op <= 27 and (va < 0 or va >= st.tcount):
                return asm_err(p.line, "invalid jump target")
            code.append(Code(op: p.op, line: p.line, ka: p.a.kind, ra: p.a.reg, va: va, kb: p.b.kind, rb: p.b.reg, vb: vb))
    return ""

fn start_pc(st: Asm) Int:
    if let s = st.syms.get("main"):
        if s.kind == 0:
            return s.value
    return 0

// ---------- input section ----------

fn is_int_token(t: String) Bool:
    let cs = t.chars()
    var i = 0
    if cs.length() > 0 and cs[0] == "-":
        i = 1
    if i >= cs.length():
        return false
    for j in i..cs.length():
        if not is_digit(cs[j]):
            return false
    return true

fn parse_int_token(t: String) Int:
    let cs = t.chars()
    var i = 0
    var neg = false
    if cs[0] == "-":
        neg = true
        i = 1
    var acc = 0
    for j in i..cs.length():
        acc = bit_and(acc * 10 + digit_value(cs[j]), 4294967295)
    if neg:
        return wrap(0 - acc)
    return wrap(acc)

// ---------- execution ----------

// Operand read. kind 0 register, 1 immediate value, 2 memory at [base + disp].
fn ea(reg: Int, disp: Int, regs: List[Int]) Int:
    var base = 0
    if reg >= 0:
        base = regs[reg]
    return wrap(base + disp)

fn read_op(kind: Int, reg: Int, val: Int, regs: List[Int], mem: List[Int], var trap: String) Int:
    if kind == 0:
        return regs[reg]
    if kind == 1:
        return val
    let addr = ea(reg, val, regs)
    if addr < 0 or addr >= 4096:
        trap = mem_trap(addr)
        return 0
    return mem[addr]

fn write_op(kind: Int, reg: Int, val: Int, value: Int, var regs: List[Int], var mem: List[Int], var trap: String) Unit:
    if kind == 0:
        regs[reg] = value
        return
    let addr = ea(reg, val, regs)
    if addr < 0 or addr >= 4096:
        trap = mem_trap(addr)
        return
    mem[addr] = value

fn push_val(value: Int, var regs: List[Int], var mem: List[Int], var trap: String) Unit:
    if regs[8] <= 0:
        trap = "stack overflow"
        return
    regs[8] = regs[8] - 1
    let addr = regs[8]
    if addr < 0 or addr >= 4096:
        trap = mem_trap(addr)
        return
    mem[addr] = value

fn pop_val(var regs: List[Int], mem: List[Int], var trap: String) Int:
    if regs[8] >= 4096:
        trap = "stack underflow"
        return 0
    let addr = regs[8]
    if addr < 0 or addr >= 4096:
        trap = mem_trap(addr)
        return 0
    let v = mem[addr]
    regs[8] = regs[8] + 1
    return v

fn alu(op: Int, a: Int, b: Int, var trap: String) Int:
    if op == 1:
        return wrap(a + b)
    if op == 2:
        return wrap(a - b)
    if op == 3:
        return wrap(a * b)
    if op == 4 or op == 5:
        if b == 0:
            trap = "division by zero"
            return 0
        var qa = a
        if qa < 0:
            qa = 0 - qa
        var qb = b
        if qb < 0:
            qb = 0 - qb
        var q = qa / qb
        if (a < 0 and b >= 0) or (a >= 0 and b < 0):
            q = 0 - q
        if op == 4:
            return wrap(q)
        return wrap(a - b * q)
    if op == 6:
        return wrap(bit_and(a, b))
    if op == 7:
        return wrap(bit_or(a, b))
    if op == 8:
        return wrap(bit_xor(a, b))
    let c = bit_and(b, 31)
    if op == 9:
        return wrap(shift_left(bit_and(a, 4294967295), c))
    if op == 10:
        return wrap(shift_right_unsigned(bit_and(a, 4294967295), c))
    return wrap(shift_right(a, c))

fn run(code: List[Code], var mem: List[Int], budget: Int, start: Int, inputs: List[Int]) String:
    var regs = [0, 0, 0, 0, 0, 0, 0, 0, 4096, 0]
    var pc = start
    var steps = 0
    var zf = false
    var lf = false
    var ip = 0
    var trap = ""
    var halted = false
    var outs = List[String]()
    let n = code.length()
    while true:
        if pc < 0 or pc >= n:
            trap = "pc out of range"
            break
        if steps == budget:
            trap = "budget exceeded"
            break
        let c = code[pc]
        var next = pc + 1
        let op = c.op
        if op == 0:
            let v = read_op(c.kb, c.rb, c.vb, regs, mem, var trap)
            if trap != "":
                break
            write_op(c.ka, c.ra, c.va, v, var regs, var mem, var trap)
        else if op <= 11:
            let a = regs[c.ra]
            let b = read_op(c.kb, c.rb, c.vb, regs, mem, var trap)
            if trap != "":
                break
            let r = alu(op, a, b, var trap)
            if trap != "":
                break
            regs[c.ra] = r
        else if op == 12:
            let a = regs[c.ra]
            let b = read_op(c.kb, c.rb, c.vb, regs, mem, var trap)
            if trap != "":
                break
            zf = a == b
            lf = a < b
        else if op == 13:
            regs[c.ra] = wrap(0 - regs[c.ra])
        else if op == 14:
            regs[c.ra] = wrap(bit_not(regs[c.ra]))
        else if op == 15:
            regs[c.ra] = wrap(regs[c.ra] + 1)
        else if op == 16:
            regs[c.ra] = wrap(regs[c.ra] - 1)
        else if op == 17:
            regs[c.ra] = ea(c.rb, c.vb, regs)
        else if op == 18:
            let v = read_op(c.ka, c.ra, c.va, regs, mem, var trap)
            if trap != "":
                break
            push_val(v, var regs, var mem, var trap)
            if trap != "":
                break
        else if op == 19:
            let v = pop_val(var regs, mem, var trap)
            if trap != "":
                break
            regs[c.ra] = v
        else if op >= 20 and op <= 27:
            var take = true
            if op == 20:
                take = zf
            else if op == 21:
                take = not zf
            else if op == 22:
                take = lf
            else if op == 23:
                take = lf or zf
            else if op == 24:
                take = not lf and not zf
            else if op == 25:
                take = not lf
            if op == 27:
                push_val(pc + 1, var regs, var mem, var trap)
                if trap != "":
                    break
            if take:
                next = c.va
        else if op == 28:
            let v = pop_val(var regs, mem, var trap)
            if trap != "":
                break
            next = v
        else if op == 29:
            if ip >= inputs.length():
                trap = "input exhausted"
                break
            regs[c.ra] = inputs[ip]
            ip += 1
        else if op == 30:
            let v = read_op(c.ka, c.ra, c.va, regs, mem, var trap)
            if trap != "":
                break
            outs.append(v.to_string_radix(10) + "\n")
        else if op == 31:
            let v = read_op(c.ka, c.ra, c.va, regs, mem, var trap)
            if trap != "":
                break
            if v < 0 or v > 127:
                trap = "invalid character"
                break
            outs.append(from_scalars([v]).get())
        else if op == 32:
            halted = true
        // op 33 (nop): nothing to do
        steps += 1
        pc = next
        if halted:
            break

    var text = outs.join("")
    if text != "" and not text.ends_with("\n"):
        text = text + "\n"
    var where = "-"
    if trap != "" and trap != "pc out of range":
        where = code[pc].line.to_string_radix(10)
    if trap == "":
        text = text + "-- halted after " + steps.to_string_radix(10) + " steps\n"
    else:
        text = text + "-- trap: " + trap + " (pc=" + pc.to_string_radix(10) + " line=" + where + ") after " + steps.to_string_radix(10) + " steps\n"
    let names = ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]
    var rs = "regs:"
    for i in 0..10:
        rs = rs + " " + names[i] + "=" + regs[i].to_string_radix(10)
    var zs = "0"
    if zf:
        zs = "1"
    var ls = "0"
    if lf:
        ls = "1"
    text = text + rs + "\n" + "flags: Z=" + zs + " L=" + ls
    return text

// ---------- entry point ----------

export fn main() Int:
    var raw = List[String]()
    if let text = read_all(stdin()).get().decode_utf8():
        raw = text.lines()
    var src = List[String]()
    var inp = List[String]()
    var in_input = false
    for line in raw:
        if in_input:
            inp.append(line.clone())
        else if line == "====":
            in_input = true
        else:
            src.append(line.clone())

    var st = Asm(section: 0, tcount: 0, daddr: 0, budget: 100000, syms: Map[String, Sym](), pend: List[Pend](), err: "")
    for i in 0..src.length():
        pass1_line(var st, i + 1, src[i])
        if st.err != "":
            break
    if st.err != "":
        print(st.err)
        return 0

    var mem = List[Int]()
    for i in 0..4096:
        mem.append(0)
    var code = List[Code]()
    let perr = pass2(st, var mem, var code)
    if perr != "":
        print(perr)
        return 0

    var inputs = List[Int]()
    for line in inp:
        for tok in line.fields():
            if is_int_token(tok):
                inputs.append(parse_int_token(tok))

    print(run(code, var mem, st.budget, start_pc(st), inputs))
    return 0
