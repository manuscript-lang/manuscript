use std::collections::{HashMap, HashSet};
use std::io::{Read, Write};

#[derive(Clone, Copy, PartialEq, Debug)]
enum Op {
    Mov, Add, Sub, Mul, Div, Mod, And, Or, Xor, Shl, Shr, Sar, Cmp,
    Neg, Not, Inc, Dec, Lea, Push, Pop,
    Jmp, Je, Jne, Jl, Jle, Jg, Jge, Call, Ret, In, Out, Outc, Halt, Nop,
}

fn mnemonic(s: &str) -> Option<Op> {
    use Op::*;
    Some(match s {
        "mov" => Mov, "add" => Add, "sub" => Sub, "mul" => Mul, "div" => Div, "mod" => Mod,
        "and" => And, "or" => Or, "xor" => Xor, "shl" => Shl, "shr" => Shr, "sar" => Sar,
        "cmp" => Cmp, "neg" => Neg, "not" => Not, "inc" => Inc, "dec" => Dec, "lea" => Lea,
        "push" => Push, "pop" => Pop, "jmp" => Jmp, "je" | "jz" => Je, "jne" | "jnz" => Jne,
        "jl" => Jl, "jle" => Jle, "jg" => Jg, "jge" => Jge, "call" => Call, "ret" => Ret,
        "in" => In, "out" => Out, "outc" => Outc, "halt" => Halt, "nop" => Nop,
        _ => return None,
    })
}

fn reg_of(s: &str) -> Option<usize> {
    match s {
        "r0" => Some(0), "r1" => Some(1), "r2" => Some(2), "r3" => Some(3),
        "r4" => Some(4), "r5" => Some(5), "r6" => Some(6), "r7" => Some(7),
        "sp" => Some(8), "bp" => Some(9),
        _ => None,
    }
}

fn is_ident(s: &str) -> bool {
    let b = s.as_bytes();
    if b.is_empty() || !(b[0].is_ascii_alphabetic() || b[0] == b'_') { return false; }
    b.iter().all(|c| c.is_ascii_alphanumeric() || *c == b'_' || *c == b'.')
}

fn char_lit_len(b: &[u8], i: usize) -> Option<usize> {
    if b[i] != b'\'' { return None; }
    if i + 3 < b.len() + 0 && b[i + 1] == b'\\' && b[i + 3] == b'\'' { return Some(4); }
    if i + 2 < b.len() && b[i + 1] != b'\\' && b[i + 1] != b'\'' && b[i + 2] == b'\'' { return Some(3); }
    None
}

fn strip_comment(s: &str) -> &str {
    let b = s.as_bytes();
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            b';' => return &s[..i],
            b'"' => {
                i += 1;
                while i < b.len() && b[i] != b'"' {
                    if b[i] == b'\\' { i += 1; }
                    i += 1;
                }
                i += 1;
            }
            b'\'' => {
                if let Some(l) = char_lit_len(b, i) { i += l; } else { i += 1; }
            }
            _ => i += 1,
        }
    }
    s
}

fn split_commas(s: &str) -> Vec<String> {
    let b = s.as_bytes();
    let mut out = vec![];
    let mut depth = 0i32;
    let mut start = 0;
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            b'\'' => { if let Some(l) = char_lit_len(b, i) { i += l; continue; } }
            b'[' => depth += 1,
            b']' => depth -= 1,
            b',' if depth <= 0 => {
                out.push(s[start..i].trim().to_string());
                start = i + 1;
            }
            _ => {}
        }
        i += 1;
    }
    out.push(s[start..].trim().to_string());
    out
}

// split into (negative, term) pieces
fn split_terms(s: &str) -> Option<Vec<(bool, String)>> {
    let s = s.trim();
    let b = s.as_bytes();
    let mut i = 0;
    let mut neg = false;
    if i < b.len() && (b[i] == b'+' || b[i] == b'-') { neg = b[i] == b'-'; i += 1; }
    let mut out = vec![];
    loop {
        let st = i;
        while i < b.len() && b[i] != b'+' && b[i] != b'-' {
            if b[i] == b'\'' { if let Some(l) = char_lit_len(b, i) { i += l; continue; } }
            i += 1;
        }
        let t = s[st..i].trim();
        if t.is_empty() { return None; }
        out.push((neg, t.to_string()));
        if i >= b.len() { break; }
        neg = b[i] == b'-';
        i += 1;
    }
    Some(out)
}

struct Syms {
    labels: HashMap<String, i32>,
    equs: HashMap<String, String>,
}

fn eval_term(t: &str, syms: &Syms, busy: &mut HashSet<String>, whole: &str) -> Result<i32, String> {
    let inv = || format!("invalid expression '{}'", whole);
    let b = t.as_bytes();
    if b[0] == b'\'' {
        if b.len() == 3 && b[1] != b'\\' && b[1] != b'\'' { return Ok(b[1] as i32); }
        if b.len() == 4 && b[1] == b'\\' && b[3] == b'\'' {
            return match b[2] {
                b'n' => Ok(10), b't' => Ok(9), b'0' => Ok(0), b'\\' => Ok(92),
                b'\'' => Ok(39), b'"' => Ok(34),
                _ => Err(inv()),
            };
        }
        return Err(inv());
    }
    if b[0].is_ascii_digit() {
        let (digits, radix) = if t.starts_with("0x") { (&t[2..], 16) }
            else if t.starts_with("0b") { (&t[2..], 2) } else { (t, 10) };
        if digits.is_empty() { return Err(inv()); }
        let mut v: u128 = 0;
        for c in digits.chars() {
            let d = c.to_digit(radix).ok_or_else(inv)?;
            v = (v * radix as u128 + d as u128).min(1u128 << 100);
        }
        if v > 0xFFFF_FFFF { return Err("immediate out of range".to_string()); }
        return Ok(v as u32 as i32);
    }
    if is_ident(t) {
        if let Some(v) = syms.labels.get(t) { return Ok(*v); }
        if let Some(e) = syms.equs.get(t) {
            if busy.contains(t) { return Err(format!("circular definition of '{}'", t)); }
            busy.insert(t.to_string());
            let r = eval_expr_inner(e, syms, busy);
            busy.remove(t);
            return r;
        }
        return Err(format!("undefined symbol '{}'", t));
    }
    Err(inv())
}

fn eval_expr_inner(s: &str, syms: &Syms, busy: &mut HashSet<String>) -> Result<i32, String> {
    let s = s.trim();
    let terms = split_terms(s).ok_or_else(|| format!("invalid expression '{}'", s))?;
    let mut acc = 0i32;
    for (neg, t) in terms {
        let v = eval_term(&t, syms, busy, s)?;
        acc = if neg { acc.wrapping_sub(v) } else { acc.wrapping_add(v) };
    }
    Ok(acc)
}

fn eval_expr(s: &str, syms: &Syms) -> Result<i32, String> {
    eval_expr_inner(s, syms, &mut HashSet::new())
}

#[derive(Clone)]
enum POp {
    Reg(usize),
    Imm(String),
    Mem(Option<usize>, Vec<(bool, String)>),
}

#[derive(Clone)]
enum Opnd {
    Reg(usize),
    Imm(i32),
    Mem(Option<usize>, i32),
}

enum Item {
    Data { line: usize, addr: usize, texts: Vec<String>, space: Option<usize> },
    Instr(usize),
}

struct PInstr {
    op: Op,
    ops: Vec<POp>,
    line: usize,
}

struct Instr {
    op: Op,
    ops: Vec<Opnd>,
    line: usize,
}

fn parse_operand(s: &str) -> Result<POp, String> {
    let bad = || format!("invalid operand '{}'", s);
    if s.is_empty() { return Err(bad()); }
    if let Some(r) = reg_of(s) { return Ok(POp::Reg(r)); }
    if s.starts_with('[') {
        if !s.ends_with(']') || s.len() < 2 { return Err(bad()); }
        let inner = &s[1..s.len() - 1];
        if inner.contains('[') || inner.contains(']') { return Err(bad()); }
        let terms = split_terms(inner).ok_or_else(bad)?;
        let mut reg = None;
        let mut rest = vec![];
        for (neg, t) in terms {
            if let Some(r) = reg_of(&t) {
                if neg || reg.is_some() { return Err(bad()); }
                reg = Some(r);
            } else {
                rest.push((neg, t));
            }
        }
        return Ok(POp::Mem(reg, rest));
    }
    Ok(POp::Imm(s.to_string()))
}

fn eval_mem(reg: Option<usize>, terms: &[(bool, String)], syms: &Syms) -> Result<i32, String> {
    let mut acc = 0i32;
    for (neg, t) in terms {
        let v = eval_expr(t, syms)?;
        acc = if *neg { acc.wrapping_sub(v) } else { acc.wrapping_add(v) };
    }
    let _ = reg;
    Ok(acc)
}

fn parse_string(s: &str) -> Option<Vec<u8>> {
    let b = s.as_bytes();
    if b.len() < 2 || b[0] != b'"' || b[b.len() - 1] != b'"' { return None; }
    let inner = &b[1..b.len() - 1];
    let mut out = vec![];
    let mut i = 0;
    while i < inner.len() {
        match inner[i] {
            b'"' => return None,
            b'\\' => {
                i += 1;
                if i >= inner.len() { return None; }
                out.push(match inner[i] {
                    b'n' => 10, b't' => 9, b'0' => 0, b'\\' => 92, b'\'' => 39, b'"' => 34,
                    _ => return None,
                });
            }
            c => out.push(c),
        }
        i += 1;
    }
    Some(out)
}

fn assemble(lines: &[String]) -> Result<(Vec<Instr>, Vec<i32>, i64, usize), (usize, String)> {
    let mut syms = Syms { labels: HashMap::new(), equs: HashMap::new() };
    let mut text_labels: HashSet<String> = HashSet::new();
    let mut items: Vec<Item> = vec![];
    let mut pinstrs: Vec<PInstr> = vec![];
    let mut dsize = 0usize;
    let mut in_data = false;
    let mut budget: i64 = 100000;

    for (li, raw) in lines.iter().enumerate() {
        let ln = li + 1;
        let e = |m: String| (ln, m);
        let mut rest = strip_comment(raw).trim();
        // labels
        loop {
            let b = rest.as_bytes();
            let mut j = 0;
            while j < b.len() && (b[j].is_ascii_alphanumeric() || b[j] == b'_' || b[j] == b'.') { j += 1; }
            if j > 0 && j < b.len() && b[j] == b':' && is_ident(&rest[..j]) {
                let name = &rest[..j];
                if reg_of(name).is_some() { return Err(e(format!("reserved name '{}'", name))); }
                if syms.labels.contains_key(name) || syms.equs.contains_key(name) {
                    return Err(e(format!("duplicate symbol '{}'", name)));
                }
                if in_data {
                    syms.labels.insert(name.to_string(), dsize as i32);
                } else {
                    syms.labels.insert(name.to_string(), pinstrs.len() as i32);
                    text_labels.insert(name.to_string());
                }
                rest = rest[j + 1..].trim_start();
            } else { break; }
        }
        if rest.is_empty() { continue; }
        let (word, args) = match rest.find(|c: char| c.is_whitespace()) {
            Some(p) => (&rest[..p], rest[p..].trim()),
            None => (rest, ""),
        };
        if word.starts_with('.') {
            match word {
                ".text" | ".data" => {
                    if !args.is_empty() { return Err(e(format!("invalid operand '{}'", args))); }
                    in_data = word == ".data";
                }
                ".equ" => {
                    let ops = split_commas(args);
                    if args.is_empty() || ops.len() != 2 {
                        return Err(e("wrong number of operands for '.equ'".into()));
                    }
                    if !is_ident(&ops[0]) { return Err(e(format!("invalid operand '{}'", ops[0]))); }
                    if reg_of(&ops[0]).is_some() { return Err(e(format!("reserved name '{}'", ops[0]))); }
                    if syms.labels.contains_key(&ops[0]) || syms.equs.contains_key(&ops[0]) {
                        return Err(e(format!("duplicate symbol '{}'", ops[0])));
                    }
                    syms.equs.insert(ops[0].clone(), ops[1].clone());
                }
                ".budget" => {
                    let ok = !args.is_empty() && args.len() <= 9 && args.bytes().all(|c| c.is_ascii_digit());
                    let v: i64 = if ok { args.parse().unwrap() } else { 0 };
                    if !ok || v < 1 || v > 10000000 { return Err(e(format!("invalid operand '{}'", args))); }
                    budget = v;
                }
                ".word" | ".ascii" | ".asciz" | ".space" => {
                    if !in_data { return Err(e("data directive in text section".into())); }
                    let overflow = || e("data section too large".to_string());
                    match word {
                        ".word" => {
                            if args.is_empty() { return Err(e("wrong number of operands for '.word'".into())); }
                            let ops = split_commas(args);
                            if dsize + ops.len() > 4096 { return Err(overflow()); }
                            let n = ops.len();
                            items.push(Item::Data { line: ln, addr: dsize, texts: ops, space: None });
                            dsize += n;
                        }
                        ".space" => {
                            let ops = if args.is_empty() { vec![] } else { split_commas(args) };
                            if ops.is_empty() || ops.len() > 2 {
                                return Err(e("wrong number of operands for '.space'".into()));
                            }
                            let n = eval_expr(&ops[0], &syms).map_err(|m| e(m))?;
                            if n < 0 { return Err(e(format!("invalid operand '{}'", ops[0]))); }
                            let n = n as usize;
                            if dsize + n > 4096 { return Err(overflow()); }
                            let fill = if ops.len() == 2 { ops[1].clone() } else { "0".to_string() };
                            items.push(Item::Data { line: ln, addr: dsize, texts: vec![fill], space: Some(n) });
                            dsize += n;
                        }
                        _ => {
                            let s = parse_string(args).ok_or_else(|| e("invalid string".into()))?;
                            let mut n = s.len();
                            let mut vals: Vec<String> = s.iter().map(|c| c.to_string()).collect();
                            if word == ".asciz" { n += 1; vals.push("0".into()); }
                            if dsize + n > 4096 { return Err(overflow()); }
                            items.push(Item::Data { line: ln, addr: dsize, texts: vals, space: None });
                            dsize += n;
                        }
                    }
                }
                _ => return Err(e(format!("unknown directive '{}'", word))),
            }
            continue;
        }
        if in_data { return Err(e("instruction in data section".into())); }
        let op = mnemonic(word).ok_or_else(|| e(format!("unknown mnemonic '{}'", word)))?;
        let raw_ops = if args.is_empty() { vec![] } else { split_commas(args) };
        let mut ops = vec![];
        for r in &raw_ops { ops.push(parse_operand(r).map_err(|m| e(m))?); }
        use Op::*;
        let want = match op {
            Mov | Add | Sub | Mul | Div | Mod | And | Or | Xor | Shl | Shr | Sar | Cmp | Lea => 2,
            Neg | Not | Inc | Dec | Push | Pop | Jmp | Je | Jne | Jl | Jle | Jg | Jge | Call | In | Out | Outc => 1,
            Ret | Halt | Nop => 0,
        };
        if ops.len() != want { return Err(e(format!("wrong number of operands for '{}'", word))); }
        let cls = |o: &POp| match o { POp::Reg(_) => 'R', POp::Imm(_) => 'I', POp::Mem(..) => 'M' };
        let c: Vec<char> = ops.iter().map(cls).collect();
        let ok = match op {
            Mov => (c[0] == 'R') || (c[0] == 'M' && c[1] != 'M'),
            Add | Sub | Mul | Div | Mod | And | Or | Xor | Shl | Shr | Sar | Cmp => c[0] == 'R',
            Lea => c[0] == 'R' && c[1] == 'M',
            Neg | Not | Inc | Dec | Pop | In => c[0] == 'R',
            Jmp | Je | Jne | Jl | Jle | Jg | Jge | Call => c[0] == 'I',
            Push | Out | Outc => true,
            Ret | Halt | Nop => true,
        };
        if !ok { return Err(e(format!("invalid operands for '{}'", word))); }
        items.push(Item::Instr(pinstrs.len()));
        pinstrs.push(PInstr { op, ops, line: ln });
    }

    // pass 2
    let n = pinstrs.len();
    let mut mem = vec![0i32; dsize];
    let mut code: Vec<Option<Instr>> = (0..n).map(|_| None).collect();
    for it in &items {
        match it {
            Item::Data { line, addr, texts, space } => {
                let mut vals = vec![];
                for t in texts {
                    vals.push(eval_expr(t, &syms).map_err(|m| (*line, m))?);
                }
                match space {
                    Some(cnt) => { for k in 0..*cnt { mem[addr + k] = vals[0]; } }
                    None => { for (k, v) in vals.iter().enumerate() { mem[addr + k] = *v; } }
                }
            }
            Item::Instr(idx) => {
                let p = &pinstrs[*idx];
                let mut ops = vec![];
                for o in &p.ops {
                    let r = match o {
                        POp::Reg(r) => Opnd::Reg(*r),
                        POp::Imm(s) => Opnd::Imm(eval_expr(s, &syms).map_err(|m| (p.line, m))?),
                        POp::Mem(r, t) => Opnd::Mem(*r, eval_mem(*r, t, &syms).map_err(|m| (p.line, m))?),
                    };
                    ops.push(r);
                }
                use Op::*;
                if matches!(p.op, Jmp | Je | Jne | Jl | Jle | Jg | Jge | Call) {
                    if let Opnd::Imm(t) = ops[0] {
                        if t < 0 || t as usize >= n { return Err((p.line, "invalid jump target".into())); }
                    }
                }
                code[*idx] = Some(Instr { op: p.op, ops, line: p.line });
            }
        }
    }
    let code: Vec<Instr> = code.into_iter().map(|x| x.unwrap()).collect();
    let start = match syms.labels.get("main") {
        Some(v) if text_labels.contains("main") => *v as usize,
        _ => 0,
    };
    Ok((code, mem, budget, start))
}

struct Vm {
    r: [i32; 10],
    mem: Vec<i32>,
    z: bool,
    l: bool,
}

impl Vm {
    fn rd(&self, a: i32) -> Result<i32, String> {
        if a < 0 || a >= 4096 { return Err(format!("memory access out of range: {}", a)); }
        Ok(self.mem[a as usize])
    }
    fn wr(&mut self, a: i32, v: i32) -> Result<(), String> {
        if a < 0 || a >= 4096 { return Err(format!("memory access out of range: {}", a)); }
        self.mem[a as usize] = v;
        Ok(())
    }
    fn ea(&self, o: &Opnd) -> i32 {
        match o {
            Opnd::Mem(r, off) => r.map_or(0, |r| self.r[r]).wrapping_add(*off),
            _ => 0,
        }
    }
    fn val(&self, o: &Opnd) -> Result<i32, String> {
        match o {
            Opnd::Reg(r) => Ok(self.r[*r]),
            Opnd::Imm(v) => Ok(*v),
            Opnd::Mem(..) => self.rd(self.ea(o)),
        }
    }
}

fn run(code: &[Instr], mem: Vec<i32>, budget: i64, start: usize, input: Vec<i32>, out: &mut Vec<u8>) -> (Result<(), (String, i64, Option<usize>)>, i64, Vm) {
    let mut vm = Vm { r: [0; 10], mem: vec![0; 4096], z: false, l: false };
    for (i, v) in mem.iter().enumerate() { vm.mem[i] = *v; }
    vm.r[8] = 4096;
    let mut pc = start as i64;
    let mut steps = 0i64;
    let mut inp = input.into_iter();
    let n = code.len() as i64;
    loop {
        if pc < 0 || pc >= n {
            return (Err(("pc out of range".into(), pc, None)), steps, vm);
        }
        let ins = &code[pc as usize];
        let line = ins.line;
        if steps == budget {
            return (Err(("budget exceeded".into(), pc, Some(line))), steps, vm);
        }
        let mut next = pc + 1;
        let res: Result<(), String> = (|| {
            use Op::*;
            let o = &ins.ops;
            match ins.op {
                Mov => {
                    let v = vm.val(&o[1])?;
                    match &o[0] {
                        Opnd::Reg(r) => vm.r[*r] = v,
                        m => { let a = vm.ea(m); vm.wr(a, v)?; }
                    }
                }
                Add | Sub | Mul | Div | Mod | And | Or | Xor | Shl | Shr | Sar => {
                    let s = vm.val(&o[1])?;
                    let d = match o[0] { Opnd::Reg(r) => r, _ => 0 };
                    let a = vm.r[d];
                    vm.r[d] = match ins.op {
                        Add => a.wrapping_add(s),
                        Sub => a.wrapping_sub(s),
                        Mul => a.wrapping_mul(s),
                        Div => { if s == 0 { return Err("division by zero".into()); } a.wrapping_div(s) }
                        Mod => { if s == 0 { return Err("division by zero".into()); } a.wrapping_rem(s) }
                        And => a & s,
                        Or => a | s,
                        Xor => a ^ s,
                        Shl => ((a as u32) << (s & 31)) as i32,
                        Shr => ((a as u32) >> (s & 31)) as i32,
                        _ => a >> (s & 31),
                    };
                }
                Cmp => {
                    let s = vm.val(&o[1])?;
                    let a = vm.val(&o[0])?;
                    vm.z = a == s;
                    vm.l = a < s;
                }
                Neg | Not | Inc | Dec => {
                    if let Opnd::Reg(r) = o[0] {
                        let a = vm.r[r];
                        vm.r[r] = match ins.op {
                            Neg => a.wrapping_neg(), Not => !a, Inc => a.wrapping_add(1), _ => a.wrapping_sub(1),
                        };
                    }
                }
                Lea => {
                    if let Opnd::Reg(r) = o[0] { vm.r[r] = vm.ea(&o[1]); }
                }
                Push | Call => {
                    let v = if ins.op == Push { vm.val(&o[0])? } else { (pc + 1) as i32 };
                    if vm.r[8] <= 0 { return Err("stack overflow".into()); }
                    let sp = vm.r[8].wrapping_sub(1);
                    vm.wr(sp, v)?;
                    vm.r[8] = sp;
                    if ins.op == Call {
                        if let Opnd::Imm(t) = o[0] { next = t as i64; }
                    }
                }
                Pop | Ret => {
                    if vm.r[8] >= 4096 { return Err("stack underflow".into()); }
                    let v = vm.rd(vm.r[8])?;
                    vm.r[8] = vm.r[8].wrapping_add(1);
                    if ins.op == Pop {
                        if let Opnd::Reg(r) = o[0] { vm.r[r] = v; }
                    } else { next = v as i64; }
                }
                Jmp | Je | Jne | Jl | Jle | Jg | Jge => {
                    let c = match ins.op {
                        Jmp => true, Je => vm.z, Jne => !vm.z, Jl => vm.l, Jle => vm.l || vm.z,
                        Jg => !vm.l && !vm.z, _ => !vm.l,
                    };
                    if c { if let Opnd::Imm(t) = o[0] { next = t as i64; } }
                }
                In => {
                    match inp.next() {
                        Some(v) => { if let Opnd::Reg(r) = o[0] { vm.r[r] = v; } }
                        None => return Err("input exhausted".into()),
                    }
                }
                Out => {
                    let v = vm.val(&o[0])?;
                    out.extend_from_slice(v.to_string().as_bytes());
                    out.push(b'\n');
                }
                Outc => {
                    let v = vm.val(&o[0])?;
                    if !(0..=127).contains(&v) { return Err("invalid character".into()); }
                    out.push(v as u8);
                }
                Halt | Nop => {}
            }
            Ok(())
        })();
        if let Err(m) = res {
            return (Err((m, pc, Some(line))), steps, vm);
        }
        steps += 1;
        if ins.op == Op::Halt { return (Ok(()), steps, vm); }
        pc = next;
    }
}

fn latin(s: &[u8]) -> String { s.iter().map(|&c| c as char).collect() }
fn unlatin(s: &str) -> Vec<u8> { s.chars().map(|c| c as u32 as u8).collect() }

fn main() {
    let mut data = vec![];
    std::io::stdin().read_to_end(&mut data).unwrap();
    let all: Vec<String> = data.split(|&c| c == b'\n').map(|l| {
        let l = if l.last() == Some(&b'\r') { &l[..l.len() - 1] } else { l };
        latin(l)
    }).collect();
    let mut src_end = all.len();
    for (i, l) in all.iter().enumerate() {
        if l == "====" { src_end = i; break; }
    }
    let src: Vec<String> = all[..src_end].to_vec();
    let mut input = vec![];
    if src_end < all.len() {
        for l in &all[src_end + 1..] {
            for tok in l.split_whitespace() {
                let (neg, d) = match tok.strip_prefix('-') { Some(d) => (true, d), None => (false, tok) };
                if d.is_empty() || !d.bytes().all(|c| c.is_ascii_digit()) { continue; }
                let mut v: u32 = 0;
                for c in d.bytes() { v = v.wrapping_mul(10).wrapping_add((c - b'0') as u32); }
                let v = v as i32;
                input.push(if neg { v.wrapping_neg() } else { v });
            }
        }
    }
    let mut stdout = std::io::stdout();
    match assemble(&src) {
        Err((ln, m)) => {
            let mut o = format!("asm error line {}: ", ln).into_bytes();
            o.extend(unlatin(&m));
            o.push(b'\n');
            stdout.write_all(&o).unwrap();
        }
        Ok((code, mem, budget, start)) => {
            let mut out = vec![];
            let (res, steps, vm) = run(&code, mem, budget as i64, start, input, &mut out);
            if !out.is_empty() && out.last() != Some(&b'\n') { out.push(b'\n'); }
            let summary = match res {
                Ok(()) => format!("-- halted after {} steps\n", steps),
                Err((m, pc, line)) => format!("-- trap: {} (pc={} line={}) after {} steps\n", m, pc,
                    line.map_or("-".to_string(), |l| l.to_string()), steps),
            };
            out.extend(unlatin(&summary));
            let r = &vm.r;
            let regs = format!("regs: r0={} r1={} r2={} r3={} r4={} r5={} r6={} r7={} sp={} bp={}\nflags: Z={} L={}\n",
                r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], vm.z as u8, vm.l as u8);
            out.extend(regs.into_bytes());
            stdout.write_all(&out).unwrap();
        }
    }
}
