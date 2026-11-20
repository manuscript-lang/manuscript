//! Standalone QBE backend for MIR: writes QBE's SSA text straight from MIR and depends on
//! nothing but the MIR crate. The caller runs QBE on the text, assembles its output and links.
//!
//! The emitter covers the scalar subset (`Int`, `Bool`, `Float`, integer and float arithmetic,
//! checked integer arithmetic, comparisons, calls, branches); a function that uses anything else
//! is reported by [`emit`] so the caller can list what is still missing. QBE has no overflow
//! flags, so checked arithmetic is written as the sign test of the wrapped result.

use ms_mir::ir::{Block, Cc, FaultKind, Func, Imm, Module, Op, Term, Value};
use ms_mir::types::Ty;
use std::collections::HashMap;
use std::fmt::Write;

/// A failure to emit: every function or operation the emitter cannot write yet.
#[derive(Debug)]
pub struct Error(pub String);

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

/// The QBE base type that holds a value of `ty`, or `None` when the emitter does not handle it.
fn base(ty: Ty) -> Option<char> {
    match ty {
        Ty::INT | Ty::PTR => Some('l'),
        Ty::BOOL => Some('w'),
        Ty::FLOAT => Some('d'),
        _ => None,
    }
}

/// Emits `m` as QBE text. Fails with the list of everything the emitter cannot write.
pub fn emit(m: &Module) -> Result<String, Error> {
    let mut out = String::new();
    let mut missing = Vec::new();
    for (i, f) in m.funcs.iter().enumerate() {
        let export =
            f.linkage == ms_mir::ir::Linkage::Export || m.entry.is_some_and(|e| e.index() == i);
        if let Err(why) = function(m, f, export, &mut out) {
            missing.push(format!("{}: {why}", f.name));
        }
    }
    if missing.is_empty() {
        Ok(out)
    } else {
        Err(Error(format!(
            "the QBE emitter cannot write:\n{}",
            missing.join("\n")
        )))
    }
}

/// A QBE symbol for a function name; quoting lets any name through.
fn symbol(name: &str) -> String {
    format!("$\"{name}\"")
}

struct Fx<'a> {
    m: &'a Module,
    f: &'a Func,
    out: &'a mut String,
    next_label: usize,
}

impl Fx<'_> {
    fn v(&self, v: Value) -> String {
        format!("%v{}", v.0)
    }

    fn label(block: Block, part: usize) -> String {
        if part == 0 {
            format!("@b{}", block.0)
        } else {
            format!("@b{}_{part}", block.0)
        }
    }
}

fn function(m: &Module, f: &Func, export: bool, out: &mut String) -> Result<(), String> {
    let ret = if f.ret == Ty::VOID {
        None
    } else {
        Some(base(f.ret).ok_or("result type")?)
    };
    for p in &f.params {
        base(p.ty).ok_or("parameter type")?;
    }
    for v in &f.values {
        if *v != Ty::VOID {
            base(*v).ok_or("value type")?;
        }
    }
    // The pieces each block is split into by its checked operations.
    let splits: Vec<usize> = f
        .blocks
        .iter()
        .map(|b| b.insts.iter().filter(|i| is_checked(i.op)).count())
        .collect();
    // Incoming edges of every block: (predecessor label, arguments).
    let mut incoming: HashMap<Block, Vec<(String, Vec<Value>)>> = HashMap::new();
    for (i, b) in f.blocks.iter().enumerate() {
        let from = Fx::label(Block(i as u32), splits[i]);
        let mut seen = Vec::new();
        b.term.for_each_target(|t| {
            if !t.args.is_empty() && seen.contains(&t.block) {
                seen.push(Block(u32::MAX));
            }
            seen.push(t.block);
            incoming
                .entry(t.block)
                .or_default()
                .push((from.clone(), t.args.clone()));
        });
        if seen.contains(&Block(u32::MAX)) {
            return Err("one block reaches a target twice with arguments".into());
        }
    }
    let mut fx = Fx {
        m,
        f,
        out,
        next_label: 0,
    };
    let linkage = if export { "export " } else { "" };
    let params: Vec<String> = f
        .params
        .iter()
        .zip(&f.blocks[0].params)
        .map(|(p, bp)| format!("{} {}", base(p.ty).unwrap(), fx.v(bp.value)))
        .collect();
    let _ = writeln!(
        fx.out,
        "{linkage}function {}{} ({}) {{",
        ret.map(|c| format!("{c} ")).unwrap_or_default(),
        symbol(&f.name),
        params.join(", ")
    );
    for (i, b) in f.blocks.iter().enumerate() {
        let block = Block(i as u32);
        let _ = writeln!(fx.out, "{}", Fx::label(block, 0));
        if i > 0 {
            for p in &b.params {
                let ty = base(f.values[p.value.index()]).ok_or("block parameter type")?;
                let mut arms = Vec::new();
                let k = b.params.iter().position(|q| q.value == p.value).unwrap();
                for (from, args) in incoming.get(&block).map(Vec::as_slice).unwrap_or(&[]) {
                    arms.push(format!("{from} {}", fx.v(args[k])));
                }
                let _ = writeln!(fx.out, "\t{} ={ty} phi {}", fx.v(p.value), arms.join(", "));
            }
        }
        let mut part = 0;
        for inst in &b.insts {
            fx.inst(inst, block, &mut part)?;
        }
        fx.term(&b.term)?;
    }
    fx.out.push_str("}\n\n");
    Ok(())
}

fn is_checked(op: Op) -> bool {
    matches!(op, Op::IAddChk | Op::ISubChk | Op::INegChk)
}

impl Fx<'_> {
    fn ty(&self, v: Value) -> char {
        base(self.f.values[v.index()]).unwrap_or('l')
    }

    fn inst(&mut self, i: &ms_mir::ir::Inst, block: Block, part: &mut usize) -> Result<(), String> {
        let res = i.res.map(|r| (self.v(r), self.ty(r)));
        let args: Vec<String> = i.args.iter().map(|x| self.v(*x)).collect();
        let a = |k: usize| args[k].clone();
        let line = match (i.op, i.imm, &res) {
            (Op::IConst, Imm::Int(n), Some((r, t))) => format!("{r} ={t} copy {n}"),
            (Op::BConst, Imm::Bool(b), Some((r, t))) => format!("{r} ={t} copy {}", b as u8),
            (Op::FConst, Imm::Float(bits), Some((r, t))) => {
                format!("{r} ={t} copy d_{}", f64::from_bits(bits))
            }
            (Op::IAdd | Op::ISub | Op::IMul, _, Some((r, t))) => {
                let op = match i.op {
                    Op::IAdd => "add",
                    Op::ISub => "sub",
                    _ => "mul",
                };
                format!("{r} ={t} {op} {}, {}", a(0), a(1))
            }
            (Op::And | Op::Or | Op::Xor | Op::Shl | Op::Sshr | Op::Ushr, _, Some((r, t))) => {
                let op = match i.op {
                    Op::And => "and",
                    Op::Or => "or",
                    Op::Xor => "xor",
                    Op::Shl => "shl",
                    Op::Sshr => "sar",
                    _ => "shr",
                };
                format!("{r} ={t} {op} {}, {}", a(0), a(1))
            }
            (Op::Not, _, Some((r, t))) => format!("{r} ={t} xor {}, 1", a(0)),
            (Op::FAdd | Op::FSub | Op::FMul | Op::FDiv, _, Some((r, t))) => {
                let op = match i.op {
                    Op::FAdd => "add",
                    Op::FSub => "sub",
                    Op::FMul => "mul",
                    _ => "div",
                };
                format!("{r} ={t} {op} {}, {}", a(0), a(1))
            }
            (Op::FNeg, _, Some((r, t))) => format!("{r} ={t} neg {}", a(0)),
            (Op::SDiv | Op::SRem, _, Some((r, t))) => {
                format!(
                    "{r} ={t} {} {}, {}",
                    if i.op == Op::SDiv { "div" } else { "rem" },
                    a(0),
                    a(1)
                )
            }
            (Op::I2F, _, Some((r, t))) => format!("{r} ={t} sltof {}", a(0)),
            (Op::B2I, _, Some((r, t))) => format!("{r} ={t} extuw {}", a(0)),
            (Op::ICmp, Imm::Cc(cc), Some((r, _))) => {
                format!(
                    "{r} =w c{}{} {}, {}",
                    int_cc(cc),
                    self.ty(i.args[0]),
                    a(0),
                    a(1)
                )
            }
            (Op::UICmp, Imm::Cc(cc), Some((r, _))) => {
                format!(
                    "{r} =w c{}{} {}, {}",
                    uint_cc(cc),
                    self.ty(i.args[0]),
                    a(0),
                    a(1)
                )
            }
            (Op::FCmp, Imm::Cc(cc), Some((r, _))) => {
                let c = match cc {
                    Cc::Eq => "eq",
                    Cc::Ne => "ne",
                    Cc::Lt => "lt",
                    Cc::Le => "le",
                    Cc::Gt => "gt",
                    Cc::Ge => "ge",
                };
                format!("{r} =w c{c}d {}, {}", a(0), a(1))
            }
            (Op::Call, Imm::Func(callee), _) => {
                let c = &self.m.funcs[callee.index()];
                let list: Vec<String> = c
                    .params
                    .iter()
                    .zip(&args)
                    .map(|(p, v)| format!("{} {v}", base(p.ty).unwrap_or('l')))
                    .collect();
                let head = match &res {
                    Some((r, t)) => format!("{r} ={t} "),
                    None => String::new(),
                };
                format!("{head}call {}({})", symbol(&c.name), list.join(", "))
            }
            (Op::IAddChk | Op::ISubChk, _, Some((r, t))) => {
                let (x, y) = (a(0), a(1));
                let add = i.op == Op::IAddChk;
                let _ = writeln!(
                    self.out,
                    "\t{r} ={t} {} {x}, {y}",
                    if add { "add" } else { "sub" }
                );
                // add overflows when both operands differ in sign from the result; sub when the
                // operands differ in sign and the result differs from the first.
                let (p, q) = (x.clone(), y.clone());
                let n = self.next_label;
                self.next_label += 1;
                let (t1, t2, ov) = (format!("%o{n}a"), format!("%o{n}b"), format!("%o{n}c"));
                let _ = writeln!(self.out, "\t{t1} =l xor {p}, {r}");
                if add {
                    let _ = writeln!(self.out, "\t{t2} =l xor {q}, {r}");
                } else {
                    let _ = writeln!(self.out, "\t{t2} =l xor {p}, {q}");
                }
                let _ = writeln!(self.out, "\t{ov} =l and {t1}, {t2}");
                let _ = writeln!(self.out, "\t{ov}s =w csltl {ov}, 0");
                *part += 1;
                let (fault, cont) = (format!("@f{n}"), Fx::label(block, *part));
                let _ = writeln!(
                    self.out,
                    "\tjnz {ov}s, {fault}, {cont}\n{fault}\n\tcall $msrt_fault_int_overflow()\n\thlt\n{cont}"
                );
                return Ok(());
            }
            _ => return Err(format!("op {:?}", i.op)),
        };
        let _ = writeln!(self.out, "\t{line}");
        Ok(())
    }

    fn term(&mut self, t: &Term) -> Result<(), String> {
        match t {
            Term::Br(t) => {
                let _ = writeln!(self.out, "\tjmp {}", Fx::label(t.block, 0));
            }
            Term::CondBr { cond, then, els } => {
                let _ = writeln!(
                    self.out,
                    "\tjnz {}, {}, {}",
                    self.v(*cond),
                    Fx::label(then.block, 0),
                    Fx::label(els.block, 0)
                );
            }
            Term::Ret(None) => self.out.push_str("\tret\n"),
            Term::Ret(Some(v)) => {
                let _ = writeln!(self.out, "\tret {}", self.v(*v));
            }
            Term::Fault(FaultKind::IntOverflow) => {
                self.out
                    .push_str("\tcall $msrt_fault_int_overflow()\n\thlt\n");
            }
            Term::Unreachable => self.out.push_str("\thlt\n"),
            other => return Err(format!("terminator {other:?}")),
        }
        let _ = self.m;
        Ok(())
    }
}

fn int_cc(cc: Cc) -> &'static str {
    match cc {
        Cc::Eq => "eq",
        Cc::Ne => "ne",
        Cc::Lt => "slt",
        Cc::Le => "sle",
        Cc::Gt => "sgt",
        Cc::Ge => "sge",
    }
}

fn uint_cc(cc: Cc) -> &'static str {
    match cc {
        Cc::Eq => "eq",
        Cc::Ne => "ne",
        Cc::Lt => "ult",
        Cc::Le => "ule",
        Cc::Gt => "ugt",
        Cc::Ge => "uge",
    }
}
