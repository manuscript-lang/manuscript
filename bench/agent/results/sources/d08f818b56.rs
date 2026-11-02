use std::collections::HashMap;
use std::io::{self, Read, Write};

const MEM_WORDS: usize = 4096;
const REG_NAMES: [&str; 10] = ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"];
const SP: usize = 8;

/// (line number, message) of an assembler error.
type AsmErr = (usize, String);

fn err<T>(line: usize, msg: impl Into<String>) -> Result<T, AsmErr> {
    Err((line, msg.into()))
}

fn reg_index(s: &str) -> Option<usize> {
    REG_NAMES.iter().position(|&n| n == s)
}

fn is_ident_start(c: char) -> bool {
    c.is_ascii_alphabetic() || c == '_'
}

fn is_ident_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_' || c == '.'
}

fn is_ident(s: &str) -> bool {
    let mut it = s.chars();
    matches!(it.next(), Some(c) if is_ident_start(c)) && it.all(is_ident_char)
}

/// Byte length of the identifier at the start of `s` (0 if none).
fn ident_prefix_len(s: &str) -> usize {
    let mut end = 0;
    for (i, c) in s.char_indices() {
        let ok = if i == 0 { is_ident_start(c) } else { is_ident_char(c) };
        if !ok {
            break;
        }
        end = i + c.len_utf8();
    }
    end
}

/// Removes a `;` comment, ignoring semicolons inside string/char literals.
fn strip_comment(line: &str) -> &str {
    let mut quote: Option<char> = None;
    let mut esc = false;
    for (i, c) in line.char_indices() {
        match quote {
            Some(q) => {
                if esc {
                    esc = false;
                } else if c == '\\' {
                    esc = true;
                } else if c == q {
                    quote = None;
                }
            }
            None => {
                if c == '"' || c == '\'' {
                    quote = Some(c);
                } else if c == ';' {
                    return &line[..i];
                }
            }
        }
    }
    line
}

/// Splits at commas outside brackets and literals. Empty text gives no pieces.
fn split_top(s: &str) -> Vec<&str> {
    if s.trim().is_empty() {
        return vec![];
    }
    let mut out = Vec::new();
    let mut quote: Option<char> = None;
    let mut esc = false;
    let mut depth = 0i32;
    let mut start = 0;
    for (i, c) in s.char_indices() {
        if let Some(q) = quote {
            if esc {
                esc = false;
            } else if c == '\\' {
                esc = true;
            } else if c == q {
                quote = None;
            }
            continue;
        }
        match c {
            '"' | '\'' => quote = Some(c),
            '[' => depth += 1,
            ']' => depth -= 1,
            ',' if depth <= 0 => {
                out.push(&s[start..i]);
                start = i + 1;
            }
            _ => {}
        }
    }
    out.push(&s[start..]);
    out
}

/// Parses a double-quoted string literal into bytes.
fn parse_string(s: &str) -> Option<Vec<u8>> {
    let s = s.trim();
    if s.len() < 2 || !s.starts_with('"') || !s.ends_with('"') {
        return None;
    }
    let inner = &s[1..s.len() - 1];
    let mut out = Vec::new();
    let mut it = inner.chars();
    while let Some(c) = it.next() {
        match c {
            '\\' => {
                let e = it.next()?;
                let b = match e {
                    'n' => b'\n',
                    't' => b'\t',
                    '0' => 0,
                    '\\' => b'\\',
                    '\'' => b'\'',
                    '"' => b'"',
                    _ => return None,
                };
                out.push(b);
            }
            '"' => return None,
            _ => {
                let mut buf = [0u8; 4];
                out.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
            }
        }
    }
    Some(out)
}

enum NumErr {
    Invalid,
    Range,
}

fn parse_number(s: &str) -> Result<u64, NumErr> {
    let (radix, digits) = if let Some(r) = s.strip_prefix("0x") {
        (16u32, r)
    } else if let Some(r) = s.strip_prefix("0b") {
        (2u32, r)
    } else {
        (10u32, s)
    };
    if digits.is_empty() || !digits.chars().all(|c| c.is_digit(radix)) {
        return Err(NumErr::Invalid);
    }
    let mut v: u64 = 0;
    for c in digits.chars() {
        v = v * radix as u64 + c.to_digit(radix).unwrap() as u64;
        if v > 0xFFFF_FFFF {
            return Err(NumErr::Range);
        }
    }
    Ok(v)
}

enum Sym {
    Label { text: bool, value: i32 },
    Equ(String),
}

type Syms = HashMap<String, Sym>;

fn skip_ws(chars: &[char], p: &mut usize) {
    while *p < chars.len() && (chars[*p] == ' ' || chars[*p] == '\t') {
        *p += 1;
    }
}

/// Evaluates an expression. Errors are full messages without a line number.
fn eval(text: &str, syms: &Syms, stack: &mut Vec<String>) -> Result<i32, String> {
    let chars: Vec<char> = text.chars().collect();
    let mut p = 0;
    skip_ws(&chars, &mut p);
    let mut sign: i32 = 1;
    if p < chars.len() && (chars[p] == '+' || chars[p] == '-') {
        if chars[p] == '-' {
            sign = -1;
        }
        p += 1;
    }
    let mut total: i32 = 0;
    loop {
        skip_ws(&chars, &mut p);
        let v = eval_term(&chars, &mut p, syms, stack, text)?;
        total = total.wrapping_add(sign.wrapping_mul(v));
        skip_ws(&chars, &mut p);
        if p >= chars.len() {
            return Ok(total);
        }
        sign = match chars[p] {
            '+' => 1,
            '-' => -1,
            _ => return Err(format!("invalid expression '{}'", text.trim())),
        };
        p += 1;
    }
}

fn eval_term(
    chars: &[char],
    p: &mut usize,
    syms: &Syms,
    stack: &mut Vec<String>,
    text: &str,
) -> Result<i32, String> {
    let invalid = || format!("invalid expression '{}'", text.trim());
    let c = match chars.get(*p) {
        Some(&c) => c,
        None => return Err(invalid()),
    };
    if c == '\'' {
        *p += 1;
        let ch = match chars.get(*p).copied() {
            Some(ch) => ch,
            None => return Err(invalid()),
        };
        let val: i32 = if ch == '\\' {
            *p += 1;
            match chars.get(*p).copied() {
                Some('n') => 10,
                Some('t') => 9,
                Some('0') => 0,
                Some('\\') => 92,
                Some('\'') => 39,
                Some('"') => 34,
                _ => return Err(invalid()),
            }
        } else if ch == '\'' || !ch.is_ascii() {
            return Err(invalid());
        } else {
            ch as u8 as i32
        };
        *p += 1;
        if chars.get(*p).copied() != Some('\'') {
            return Err(invalid());
        }
        *p += 1;
        return Ok(val);
    }
    if c.is_ascii_digit() {
        let start = *p;
        while *p < chars.len() && chars[*p].is_ascii_alphanumeric() {
            *p += 1;
        }
        let run: String = chars[start..*p].iter().collect();
        return match parse_number(&run) {
            Ok(v) => Ok(v as u32 as i32),
            Err(NumErr::Invalid) => Err(invalid()),
            Err(NumErr::Range) => Err("immediate out of range".to_string()),
        };
    }
    if is_ident_start(c) {
        let start = *p;
        while *p < chars.len() && is_ident_char(chars[*p]) {
            *p += 1;
        }
        let name: String = chars[start..*p].iter().collect();
        return match syms.get(&name) {
            None => Err(format!("undefined symbol '{}'", name)),
            Some(Sym::Label { value, .. }) => Ok(*value),
            Some(Sym::Equ(t)) => {
                if stack.contains(&name) {
                    return Err(format!("circular definition '{}'", name));
                }
                stack.push(name.clone());
                let r = eval(t, syms, stack);
                stack.pop();
                r
            }
        };
    }
    Err(invalid())
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Op {
    Mov,
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    And,
    Or,
    Xor,
    Shl,
    Shr,
    Sar,
    Cmp,
    Neg,
    Not,
    Inc,
    Dec,
    Lea,
    Push,
    Pop,
    Jmp,
    Je,
    Jne,
    Jl,
    Jle,
    Jg,
    Jge,
    Call,
    Ret,
    In,
    Out,
    Outc,
    Halt,
    Nop,
}

fn lookup_op(s: &str) -> Option<Op> {
    Some(match s {
        "mov" => Op::Mov,
        "add" => Op::Add,
        "sub" => Op::Sub,
        "mul" => Op::Mul,
        "div" => Op::Div,
        "mod" => Op::Mod,
        "and" => Op::And,
        "or" => Op::Or,
        "xor" => Op::Xor,
        "shl" => Op::Shl,
        "shr" => Op::Shr,
        "sar" => Op::Sar,
        "cmp" => Op::Cmp,
        "neg" => Op::Neg,
        "not" => Op::Not,
        "inc" => Op::Inc,
        "dec" => Op::Dec,
        "lea" => Op::Lea,
        "push" => Op::Push,
        "pop" => Op::Pop,
        "jmp" => Op::Jmp,
        "je" | "jz" => Op::Je,
        "jne" | "jnz" => Op::Jne,
        "jl" => Op::Jl,
        "jle" => Op::Jle,
        "jg" => Op::Jg,
        "jge" => Op::Jge,
        "call" => Op::Call,
        "ret" => Op::Ret,
        "in" => Op::In,
        "out" => Op::Out,
        "outc" => Op::Outc,
        "halt" => Op::Halt,
        "nop" => Op::Nop,
        _ => return None,
    })
}

fn arity(op: Op) -> usize {
    match op {
        Op::Mov
        | Op::Add
        | Op::Sub
        | Op::Mul
        | Op::Div
        | Op::Mod
        | Op::And
        | Op::Or
        | Op::Xor
        | Op::Shl
        | Op::Shr
        | Op::Sar
        | Op::Cmp
        | Op::Lea => 2,
        Op::Ret | Op::Halt | Op::Nop => 0,
        _ => 1,
    }
}

fn is_jump(op: Op) -> bool {
    matches!(
        op,
        Op::Jmp | Op::Je | Op::Jne | Op::Jl | Op::Jle | Op::Jg | Op::Jge | Op::Call
    )
}

/// `cls` holds one class char per operand: R register, I immediate, M memory.
fn class_ok(op: Op, cls: &[char]) -> bool {
    match op {
        Op::Mov => (cls[0] == 'R' && "RIM".contains(cls[1])) || (cls[0] == 'M' && "RI".contains(cls[1])),
        Op::Add
        | Op::Sub
        | Op::Mul
        | Op::Div
        | Op::Mod
        | Op::And
        | Op::Or
        | Op::Xor
        | Op::Shl
        | Op::Shr
        | Op::Sar
        | Op::Cmp => cls[0] == 'R' && "RIM".contains(cls[1]),
        Op::Lea => cls[0] == 'R' && cls[1] == 'M',
        Op::Neg | Op::Not | Op::Inc | Op::Dec | Op::Pop | Op::In => cls[0] == 'R',
        Op::Push | Op::Out | Op::Outc => "RIM".contains(cls[0]),
        Op::Jmp | Op::Je | Op::Jne | Op::Jl | Op::Jle | Op::Jg | Op::Jge | Op::Call => cls[0] == 'I',
        Op::Ret | Op::Halt | Op::Nop => true,
    }
}

#[derive(Clone, Debug)]
enum Opnd {
    Reg(usize),
    Imm(String),
    Mem { reg: Option<usize>, terms: Vec<(bool, String)> },
}

enum Stmt {
    Words { line: usize, exprs: Vec<String>, addr: usize },
    Bytes { bytes: Vec<u8>, addr: usize },
    Space { line: usize, count: usize, fill: Option<String>, addr: usize },
    Instr { line: usize, op: Op, opnds: Vec<Opnd> },
}

/// Parses a memory operand `[...]`. `t` is the trimmed operand text.
fn parse_mem(t: &str) -> Result<Opnd, String> {
    let bad = || format!("invalid operand '{}'", t);
    if t.len() < 2 || !t.ends_with(']') {
        return Err(bad());
    }
    let inner = &t[1..t.len() - 1];

    // Split into a leading segment and segments that each follow a sign.
    let mut first = String::new();
    let mut rest: Vec<(bool, String)> = Vec::new();
    let mut cur = String::new();
    let mut quote: Option<char> = None;
    let mut esc = false;
    let mut cur_neg: Option<bool> = None;
    for c in inner.chars() {
        if let Some(q) = quote {
            cur.push(c);
            if esc {
                esc = false;
            } else if c == '\\' {
                esc = true;
            } else if c == q {
                quote = None;
            }
            continue;
        }
        if c == '+' || c == '-' {
            match cur_neg {
                None => first = std::mem::take(&mut cur),
                Some(neg) => rest.push((neg, std::mem::take(&mut cur))),
            }
            cur_neg = Some(c == '-');
        } else {
            if c == '"' || c == '\'' {
                quote = Some(c);
            }
            cur.push(c);
        }
    }
    match cur_neg {
        None => first = cur,
        Some(neg) => rest.push((neg, cur)),
    }

    let mut all: Vec<(bool, String)> = Vec::new();
    let f = first.trim();
    if !f.is_empty() {
        all.push((false, f.to_string()));
    } else if rest.is_empty() {
        return Err(bad());
    }
    for (neg, s) in rest {
        let s = s.trim();
        if s.is_empty() {
            return Err(bad());
        }
        all.push((neg, s.to_string()));
    }

    let mut reg = None;
    let mut terms = Vec::new();
    for (neg, s) in all {
        if let Some(r) = reg_index(&s) {
            if neg || reg.is_some() {
                return Err(bad());
            }
            reg = Some(r);
        } else {
            terms.push((neg, s));
        }
    }
    Ok(Opnd::Mem { reg, terms })
}

struct Pass1 {
    syms: Syms,
    stmts: Vec<Stmt>,
    in_data: bool,
    ninstr: usize,
    daddr: usize,
    budget: u64,
}

impl Pass1 {
    fn line(&mut self, ln: usize, raw: &str) -> Result<(), AsmErr> {
        let mut rest = strip_comment(raw).trim();
        loop {
            let end = ident_prefix_len(rest);
            if end > 0 && rest[end..].starts_with(':') {
                self.define_label(ln, &rest[..end])?;
                rest = rest[end + 1..].trim_start();
                continue;
            }
            break;
        }
        if rest.is_empty() {
            return Ok(());
        }
        let (word, args) = match rest.find(char::is_whitespace) {
            Some(i) => (&rest[..i], rest[i..].trim()),
            None => (rest, ""),
        };
        if word.starts_with('.') {
            self.directive(ln, word, args)
        } else {
            self.instruction(ln, word, args)
        }
    }

    fn define_label(&mut self, ln: usize, name: &str) -> Result<(), AsmErr> {
        if reg_index(name).is_some() {
            return err(ln, format!("reserved name '{}'", name));
        }
        if self.syms.contains_key(name) {
            return err(ln, format!("duplicate symbol '{}'", name));
        }
        let sym = if self.in_data {
            Sym::Label { text: false, value: self.daddr as i32 }
        } else {
            Sym::Label { text: true, value: self.ninstr as i32 }
        };
        self.syms.insert(name.to_string(), sym);
        Ok(())
    }

    fn reserve(&self, ln: usize, n: usize) -> Result<(), AsmErr> {
        if self.daddr + n > MEM_WORDS {
            err(ln, "data section too large")
        } else {
            Ok(())
        }
    }

    fn directive(&mut self, ln: usize, word: &str, args: &str) -> Result<(), AsmErr> {
        match word {
            ".text" | ".data" => {
                if !args.is_empty() {
                    return err(ln, format!("invalid operand '{}'", args));
                }
                self.in_data = word == ".data";
                Ok(())
            }
            ".equ" => {
                let ops = split_top(args);
                if ops.len() != 2 {
                    return err(ln, "wrong number of operands for '.equ'");
                }
                let name = ops[0].trim();
                if !is_ident(name) {
                    return err(ln, format!("invalid operand '{}'", name));
                }
                if reg_index(name).is_some() {
                    return err(ln, format!("reserved name '{}'", name));
                }
                if self.syms.contains_key(name) {
                    return err(ln, format!("duplicate symbol '{}'", name));
                }
                self.syms
                    .insert(name.to_string(), Sym::Equ(ops[1].trim().to_string()));
                Ok(())
            }
            ".budget" => {
                let valid = !args.is_empty() && args.chars().all(|c| c.is_ascii_digit());
                let val = if valid {
                    args.parse::<u64>()
                        .ok()
                        .filter(|v| (1..=10_000_000).contains(v))
                } else {
                    None
                };
                match val {
                    Some(v) => {
                        self.budget = v;
                        Ok(())
                    }
                    None => err(ln, format!("invalid operand '{}'", args)),
                }
            }
            ".word" | ".ascii" | ".asciz" | ".space" => {
                if !self.in_data {
                    return err(ln, "data directive in text section");
                }
                match word {
                    ".word" => {
                        let ops = split_top(args);
                        if ops.is_empty() {
                            return err(ln, "wrong number of operands for '.word'");
                        }
                        let n = ops.len();
                        self.reserve(ln, n)?;
                        let exprs: Vec<String> = ops.iter().map(|s| s.trim().to_string()).collect();
                        self.stmts.push(Stmt::Words { line: ln, exprs, addr: self.daddr });
                        self.daddr += n;
                        Ok(())
                    }
                    ".ascii" | ".asciz" => {
                        let Some(mut bytes) = parse_string(args) else {
                            return err(ln, "invalid string");
                        };
                        if word == ".asciz" {
                            bytes.push(0);
                        }
                        let n = bytes.len();
                        self.reserve(ln, n)?;
                        self.stmts.push(Stmt::Bytes { bytes, addr: self.daddr });
                        self.daddr += n;
                        Ok(())
                    }
                    _ => {
                        let ops = split_top(args);
                        if ops.is_empty() || ops.len() > 2 {
                            return err(ln, "wrong number of operands for '.space'");
                        }
                        let ntext = ops[0].trim();
                        let nval = eval(ntext, &self.syms, &mut Vec::new()).map_err(|m| (ln, m))?;
                        if nval < 0 {
                            return err(ln, format!("invalid operand '{}'", ntext));
                        }
                        let count = nval as usize;
                        self.reserve(ln, count)?;
                        let fill = ops.get(1).map(|s| s.trim().to_string());
                        self.stmts.push(Stmt::Space { line: ln, count, fill, addr: self.daddr });
                        self.daddr += count;
                        Ok(())
                    }
                }
            }
            _ => err(ln, format!("unknown directive '{}'", word)),
        }
    }

    fn instruction(&mut self, ln: usize, word: &str, args: &str) -> Result<(), AsmErr> {
        if self.in_data {
            return err(ln, "instruction in data section");
        }
        let Some(op) = lookup_op(word) else {
            return err(ln, format!("unknown mnemonic '{}'", word));
        };
        let mut opnds = Vec::new();
        for p in split_top(args) {
            let t = p.trim();
            if t.is_empty() {
                return err(ln, "invalid operand ''");
            }
            if t.starts_with('[') {
                opnds.push(parse_mem(t).map_err(|m| (ln, m))?);
            } else if let Some(r) = reg_index(t) {
                opnds.push(Opnd::Reg(r));
            } else {
                opnds.push(Opnd::Imm(t.to_string()));
            }
        }
        if opnds.len() != arity(op) {
            return err(ln, format!("wrong number of operands for '{}'", word));
        }
        let cls: Vec<char> = opnds
            .iter()
            .map(|o| match o {
                Opnd::Reg(_) => 'R',
                Opnd::Imm(_) => 'I',
                Opnd::Mem { .. } => 'M',
            })
            .collect();
        if !class_ok(op, &cls) {
            return err(ln, format!("invalid operands for '{}'", word));
        }
        self.stmts.push(Stmt::Instr { line: ln, op, opnds });
        self.ninstr += 1;
        Ok(())
    }
}

#[derive(Clone, Copy, Debug)]
enum Res {
    Reg(usize),
    Imm(i32),
    Mem { base: Option<usize>, disp: i32 },
}

struct Ins {
    op: Op,
    args: Vec<Res>,
    target: usize,
    line: usize,
}

fn pass2(st: &Pass1) -> Result<(Vec<Ins>, Vec<i32>), AsmErr> {
    let mut mem = vec![0i32; MEM_WORDS];
    let mut prog = Vec::with_capacity(st.ninstr);
    let ev = |t: &str| eval(t, &st.syms, &mut Vec::new());
    for s in &st.stmts {
        match s {
            Stmt::Words { line, exprs, addr } => {
                for (i, e) in exprs.iter().enumerate() {
                    mem[addr + i] = ev(e).map_err(|m| (*line, m))?;
                }
            }
            Stmt::Bytes { bytes, addr } => {
                for (i, b) in bytes.iter().enumerate() {
                    mem[addr + i] = *b as i32;
                }
            }
            Stmt::Space { line, count, fill, addr } => {
                let fv = match fill {
                    Some(f) => ev(f).map_err(|m| (*line, m))?,
                    None => 0,
                };
                for i in 0..*count {
                    mem[addr + i] = fv;
                }
            }
            Stmt::Instr { line, op, opnds } => {
                let mut args = Vec::with_capacity(opnds.len());
                for o in opnds {
                    let r = match o {
                        Opnd::Reg(r) => Res::Reg(*r),
                        Opnd::Imm(t) => Res::Imm(ev(t).map_err(|m| (*line, m))?),
                        Opnd::Mem { reg, terms } => {
                            let mut disp = 0i32;
                            for (neg, t) in terms {
                                let v = ev(t).map_err(|m| (*line, m))?;
                                disp = disp.wrapping_add(if *neg { v.wrapping_neg() } else { v });
                            }
                            Res::Mem { base: *reg, disp }
                        }
                    };
                    args.push(r);
                }
                let mut target = 0usize;
                if is_jump(*op) {
                    if let Res::Imm(t) = args[0] {
                        if t < 0 || t as usize >= st.ninstr {
                            return Err((*line, "invalid jump target".to_string()));
                        }
                        target = t as usize;
                    }
                }
                prog.push(Ins { op: *op, args, target, line: *line });
            }
        }
    }
    Ok((prog, mem))
}

struct Machine {
    regs: [i32; 10],
    mem: Vec<i32>,
    z: bool,
    l: bool,
    out: Vec<u8>,
    input: Vec<i32>,
    inpos: usize,
    steps: u64,
}

enum Flow {
    Next,
    Jump(i64),
    Halt,
}

enum Outcome {
    Halted,
    Trap(String, i64, Option<usize>),
}

fn ea(regs: &[i32; 10], base: Option<usize>, disp: i32) -> i32 {
    base.map_or(0, |b| regs[b]).wrapping_add(disp)
}

fn mem_index(a: i32) -> Result<usize, String> {
    if a >= 0 && (a as usize) < MEM_WORDS {
        Ok(a as usize)
    } else {
        Err(format!("memory access out of range: {}", a))
    }
}

impl Machine {
    fn read(&self, r: Res) -> Result<i32, String> {
        match r {
            Res::Reg(i) => Ok(self.regs[i]),
            Res::Imm(v) => Ok(v),
            Res::Mem { base, disp } => {
                let i = mem_index(ea(&self.regs, base, disp))?;
                Ok(self.mem[i])
            }
        }
    }

    fn write(&mut self, r: Res, v: i32) -> Result<(), String> {
        match r {
            Res::Reg(i) => self.regs[i] = v,
            Res::Mem { base, disp } => {
                let i = mem_index(ea(&self.regs, base, disp))?;
                self.mem[i] = v;
            }
            Res::Imm(_) => {}
        }
        Ok(())
    }
}

fn exec(m: &mut Machine, ins: &Ins, pc: usize) -> Result<Flow, String> {
    let a = &ins.args;
    match ins.op {
        Op::Mov => {
            let v = m.read(a[1])?;
            m.write(a[0], v)?;
            Ok(Flow::Next)
        }
        Op::Add
        | Op::Sub
        | Op::Mul
        | Op::Div
        | Op::Mod
        | Op::And
        | Op::Or
        | Op::Xor
        | Op::Shl
        | Op::Shr
        | Op::Sar => {
            let s = m.read(a[1])?;
            let d = m.read(a[0])?;
            let r = match ins.op {
                Op::Add => d.wrapping_add(s),
                Op::Sub => d.wrapping_sub(s),
                Op::Mul => d.wrapping_mul(s),
                Op::Div => {
                    if s == 0 {
                        return Err("division by zero".to_string());
                    }
                    d.wrapping_div(s)
                }
                Op::Mod => {
                    if s == 0 {
                        return Err("division by zero".to_string());
                    }
                    d.wrapping_rem(s)
                }
                Op::And => d & s,
                Op::Or => d | s,
                Op::Xor => d ^ s,
                Op::Shl => ((d as u32) << ((s & 31) as u32)) as i32,
                Op::Shr => ((d as u32) >> ((s & 31) as u32)) as i32,
                _ => d >> ((s & 31) as u32),
            };
            m.write(a[0], r)?;
            Ok(Flow::Next)
        }
        Op::Cmp => {
            let s = m.read(a[1])?;
            let d = m.read(a[0])?;
            m.z = d == s;
            m.l = d < s;
            Ok(Flow::Next)
        }
        Op::Neg | Op::Not | Op::Inc | Op::Dec => {
            let d = m.read(a[0])?;
            let r = match ins.op {
                Op::Neg => d.wrapping_neg(),
                Op::Not => !d,
                Op::Inc => d.wrapping_add(1),
                _ => d.wrapping_sub(1),
            };
            m.write(a[0], r)?;
            Ok(Flow::Next)
        }
        Op::Lea => {
            if let Res::Mem { base, disp } = a[1] {
                let v = ea(&m.regs, base, disp);
                m.write(a[0], v)?;
            }
            Ok(Flow::Next)
        }
        Op::Push => {
            let v = m.read(a[0])?;
            let sp = m.regs[SP];
            if sp <= 0 {
                return Err("stack overflow".to_string());
            }
            let sp = sp.wrapping_sub(1);
            m.regs[SP] = sp;
            let i = mem_index(sp)?;
            m.mem[i] = v;
            Ok(Flow::Next)
        }
        Op::Pop => {
            let sp = m.regs[SP];
            if sp >= MEM_WORDS as i32 {
                return Err("stack underflow".to_string());
            }
            let i = mem_index(sp)?;
            let v = m.mem[i];
            m.regs[SP] = sp + 1;
            m.write(a[0], v)?;
            Ok(Flow::Next)
        }
        Op::Jmp | Op::Je | Op::Jne | Op::Jl | Op::Jle | Op::Jg | Op::Jge => {
            let take = match ins.op {
                Op::Jmp => true,
                Op::Je => m.z,
                Op::Jne => !m.z,
                Op::Jl => m.l,
                Op::Jle => m.l || m.z,
                Op::Jg => !m.l && !m.z,
                _ => !m.l,
            };
            Ok(if take { Flow::Jump(ins.target as i64) } else { Flow::Next })
        }
        Op::Call => {
            let sp = m.regs[SP];
            if sp <= 0 {
                return Err("stack overflow".to_string());
            }
            let sp = sp.wrapping_sub(1);
            m.regs[SP] = sp;
            let i = mem_index(sp)?;
            m.mem[i] = (pc + 1) as i32;
            Ok(Flow::Jump(ins.target as i64))
        }
        Op::Ret => {
            let sp = m.regs[SP];
            if sp >= MEM_WORDS as i32 {
                return Err("stack underflow".to_string());
            }
            let i = mem_index(sp)?;
            let v = m.mem[i];
            m.regs[SP] = sp + 1;
            Ok(Flow::Jump(v as i64))
        }
        Op::In => {
            if m.inpos >= m.input.len() {
                return Err("input exhausted".to_string());
            }
            let v = m.input[m.inpos];
            m.inpos += 1;
            m.write(a[0], v)?;
            Ok(Flow::Next)
        }
        Op::Out => {
            let v = m.read(a[0])?;
            m.out.extend_from_slice(format!("{}\n", v).as_bytes());
            Ok(Flow::Next)
        }
        Op::Outc => {
            let v = m.read(a[0])?;
            if !(0..=127).contains(&v) {
                return Err("invalid character".to_string());
            }
            m.out.push(v as u8);
            Ok(Flow::Next)
        }
        Op::Halt => Ok(Flow::Halt),
        Op::Nop => Ok(Flow::Next),
    }
}

fn run(prog: &[Ins], m: &mut Machine, budget: u64, entry: usize) -> Outcome {
    let mut pc = entry as i64;
    loop {
        let valid = pc >= 0 && (pc as usize) < prog.len();
        if m.steps == budget {
            let line = if valid { Some(prog[pc as usize].line) } else { None };
            return Outcome::Trap("budget exceeded".to_string(), pc, line);
        }
        if !valid {
            return Outcome::Trap("pc out of range".to_string(), pc, None);
        }
        let ins = &prog[pc as usize];
        match exec(m, ins, pc as usize) {
            Ok(Flow::Next) => {
                pc += 1;
                m.steps += 1;
            }
            Ok(Flow::Jump(t)) => {
                pc = t;
                m.steps += 1;
            }
            Ok(Flow::Halt) => {
                m.steps += 1;
                return Outcome::Halted;
            }
            Err(msg) => return Outcome::Trap(msg, pc, Some(ins.line)),
        }
    }
}

/// Parses whitespace-separated decimal integers; invalid tokens are skipped.
fn parse_inputs(s: &str) -> Vec<i32> {
    s.split_whitespace()
        .filter_map(|t| {
            let (neg, digits) = match t.strip_prefix('-') {
                Some(d) => (true, d),
                None => (false, t),
            };
            if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
                return None;
            }
            let mut v: u32 = 0;
            for b in digits.bytes() {
                v = v.wrapping_mul(10).wrapping_add((b - b'0') as u32);
            }
            let v = v as i32;
            Some(if neg { v.wrapping_neg() } else { v })
        })
        .collect()
}

fn assemble_and_run(lines: &[&str], input_text: &str) -> Result<Vec<u8>, AsmErr> {
    let mut st = Pass1 {
        syms: HashMap::new(),
        stmts: Vec::new(),
        in_data: false,
        ninstr: 0,
        daddr: 0,
        budget: 100_000,
    };
    for (idx, raw) in lines.iter().enumerate() {
        st.line(idx + 1, raw)?;
    }
    let (prog, mem) = pass2(&st)?;
    let entry = match st.syms.get("main") {
        Some(Sym::Label { text: true, value }) => *value as usize,
        _ => 0,
    };

    let mut m = Machine {
        regs: [0; 10],
        mem,
        z: false,
        l: false,
        out: Vec::new(),
        input: parse_inputs(input_text),
        inpos: 0,
        steps: 0,
    };
    m.regs[SP] = MEM_WORDS as i32;
    let outcome = run(&prog, &mut m, st.budget, entry);

    let mut out = std::mem::take(&mut m.out);
    if out.last().is_some_and(|&b| b != b'\n') {
        out.push(b'\n');
    }
    let summary = match outcome {
        Outcome::Halted => format!("-- halted after {} steps\n", m.steps),
        Outcome::Trap(msg, pc, line) => {
            let l = match line {
                Some(l) => l.to_string(),
                None => "-".to_string(),
            };
            format!("-- trap: {} (pc={} line={}) after {} steps\n", msg, pc, l, m.steps)
        }
    };
    out.extend_from_slice(summary.as_bytes());

    let mut regs = String::from("regs:");
    for i in 0..8 {
        regs.push_str(&format!(" r{}={}", i, m.regs[i]));
    }
    regs.push_str(&format!(" sp={} bp={}\n", m.regs[SP], m.regs[9]));
    out.extend_from_slice(regs.as_bytes());
    out.extend_from_slice(format!("flags: Z={} L={}\n", m.z as i32, m.l as i32).as_bytes());
    Ok(out)
}

fn main() {
    let mut bytes = Vec::new();
    let _ = io::stdin().read_to_end(&mut bytes);
    let text = String::from_utf8_lossy(&bytes);

    let mut src_lines: Vec<&str> = Vec::new();
    let mut input_text = String::new();
    let mut in_section = false;
    for raw in text.split('\n') {
        let line = raw.strip_suffix('\r').unwrap_or(raw);
        if in_section {
            input_text.push_str(line);
            input_text.push('\n');
        } else if line == "====" {
            in_section = true;
        } else {
            src_lines.push(line);
        }
    }

    let out = match assemble_and_run(&src_lines, &input_text) {
        Ok(o) => o,
        Err((ln, msg)) => format!("asm error line {}: {}\n", ln, msg).into_bytes(),
    };
    let stdout = io::stdout();
    let mut lock = stdout.lock();
    let _ = lock.write_all(&out);
    let _ = lock.flush();
}
