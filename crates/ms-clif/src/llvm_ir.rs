//! Translation of Cranelift IR functions to textual LLVM IR.
//!
//! Release builds reuse the whole MIR lowering (layout, glue, checks, runtime calls) and hand the
//! resulting Cranelift functions to LLVM's optimizer. The translation is one-to-one: Cranelift
//! block parameters become `phi`s, `*_overflow` ops become `llvm.*.with.overflow`, stack slots
//! become entry-block `alloca`s, and `trap` becomes `unreachable`. Integer widths and float
//! semantics are unchanged (no fast-math), so the output matches the Cranelift build.

use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::{
    self, Block, ExtFuncData, ExternalName, Function, GlobalValueData, Inst, InstructionData,
    Opcode, Type, Value, types,
};
use std::collections::{BTreeMap, HashMap};
use std::fmt::Write as _;

/// Resolves the symbol a Cranelift external name refers to.
pub trait Symbols {
    /// Symbol of the user-named function or data object `(namespace, index)`.
    fn symbol(&self, namespace: u32, index: u32) -> String;
}

/// An LLVM module under construction.
#[derive(Default)]
pub struct LlvmModule {
    /// Function definitions.
    pub body: String,
    /// `declare` lines of external functions, by symbol.
    decls: BTreeMap<String, String>,
    /// External data symbols referenced.
    data: BTreeMap<String, ()>,
    /// Symbols defined in this module.
    defined: Vec<String>,
}

fn llty(t: Type) -> &'static str {
    match t {
        types::I8 => "i8",
        types::I16 => "i16",
        types::I32 => "i32",
        types::I64 => "i64",
        types::F64 => "double",
        _ => panic!("unsupported type {t}"),
    }
}

/// `i8` parameters and returns are zero-extended (the runtime is compiled by rustc).
fn attr(t: Type) -> &'static str {
    if t == types::I8 { " zeroext" } else { "" }
}

fn ret_ty(rets: &[ir::AbiParam]) -> String {
    match rets {
        [] => "void".into(),
        [r] => format!("{}{}", llty(r.value_type), attr(r.value_type)),
        rs => {
            let ts: Vec<_> = rs.iter().map(|r| llty(r.value_type)).collect();
            format!("{{ {} }}", ts.join(", "))
        }
    }
}

fn sig_params(sig: &ir::Signature) -> String {
    sig.params
        .iter()
        .map(|p| format!("{}{}", llty(p.value_type), attr(p.value_type)))
        .collect::<Vec<_>>()
        .join(", ")
}

fn icc(cc: IntCC) -> &'static str {
    match cc {
        IntCC::Equal => "eq",
        IntCC::NotEqual => "ne",
        IntCC::SignedLessThan => "slt",
        IntCC::SignedGreaterThanOrEqual => "sge",
        IntCC::SignedGreaterThan => "sgt",
        IntCC::SignedLessThanOrEqual => "sle",
        IntCC::UnsignedLessThan => "ult",
        IntCC::UnsignedGreaterThanOrEqual => "uge",
        IntCC::UnsignedGreaterThan => "ugt",
        IntCC::UnsignedLessThanOrEqual => "ule",
    }
}

fn fcc(cc: FloatCC) -> &'static str {
    match cc {
        FloatCC::Ordered => "ord",
        FloatCC::Unordered => "uno",
        FloatCC::Equal => "oeq",
        FloatCC::NotEqual => "une",
        FloatCC::OrderedNotEqual => "one",
        FloatCC::UnorderedOrEqual => "ueq",
        FloatCC::LessThan => "olt",
        FloatCC::LessThanOrEqual => "ole",
        FloatCC::GreaterThan => "ogt",
        FloatCC::GreaterThanOrEqual => "oge",
        FloatCC::UnorderedOrLessThan => "ult",
        FloatCC::UnorderedOrLessThanOrEqual => "ule",
        FloatCC::UnorderedOrGreaterThan => "ugt",
        FloatCC::UnorderedOrGreaterThanOrEqual => "uge",
    }
}

fn double_lit(bits: u64) -> String {
    format!("0x{bits:016X}")
}

struct Edge {
    /// Block the phi sees as predecessor.
    from: String,
    /// Operand per target block parameter.
    args: Vec<String>,
}

struct Tr<'a> {
    f: &'a Function,
    syms: &'a dyn Symbols,
    out: String,
    /// Operand text of each Cranelift value.
    ops: HashMap<Value, String>,
    tmp: usize,
    /// Incoming edges per Cranelift block.
    incoming: HashMap<Block, Vec<Edge>>,
    /// Trampoline blocks to append after the instructions: (label, target, args).
    tramps: Vec<(String, Block, Vec<String>)>,
    cur: String,
    decls: &'a mut BTreeMap<String, String>,
    data: &'a mut BTreeMap<String, ()>,
}

impl<'a> Tr<'a> {
    fn t(&mut self) -> String {
        self.tmp += 1;
        format!("%t{}", self.tmp)
    }

    fn op(&self, v: Value) -> String {
        self.ops
            .get(&v)
            .unwrap_or_else(|| panic!("value {v} used before definition"))
            .clone()
    }

    fn ty(&self, v: Value) -> Type {
        self.f.dfg.value_type(v)
    }

    fn line(&mut self, s: impl AsRef<str>) {
        self.out.push_str("  ");
        self.out.push_str(s.as_ref());
        self.out.push('\n');
    }

    /// `%d = <rhs>` with a fresh name; returns the name.
    fn def(&mut self, rhs: String) -> String {
        let d = self.t();
        self.line(format!("{d} = {rhs}"));
        d
    }

    fn set(&mut self, inst: Inst, idx: usize, text: String) {
        let r = self.f.dfg.inst_results(inst)[idx];
        self.ops.insert(r, text);
    }

    fn ext_func(&self, fr: ir::FuncRef) -> &ExtFuncData {
        &self.f.dfg.ext_funcs[fr]
    }

    fn name_of(&self, n: &ExternalName) -> String {
        match n {
            ExternalName::User(r) => {
                let u = &self.f.params.user_named_funcs()[*r];
                self.syms.symbol(u.namespace, u.index)
            }
            other => panic!("unsupported external name {other:?}"),
        }
    }

    fn to_i1(&mut self, v: Value) -> String {
        let o = self.op(v);
        if o == "0" {
            return "false".into();
        }
        if o == "1" {
            return "true".into();
        }
        let t = llty(self.ty(v));
        self.def(format!("icmp ne {t} {o}, 0"))
    }

    fn ptr(&mut self, v: Value, off: i32) -> String {
        let o = self.op(v);
        let p = self.def(format!("inttoptr i64 {o} to ptr"));
        if off == 0 {
            p
        } else {
            self.def(format!("getelementptr inbounds i8, ptr {p}, i64 {off}"))
        }
    }

    fn label(&self, b: Block) -> String {
        format!("b{}", b.as_u32())
    }

    /// The branch target text for a block call, creating a trampoline when it carries arguments.
    fn target(&mut self, bc: ir::BlockCall) -> String {
        let pool = &self.f.dfg.value_lists;
        let blk = bc.block(pool);
        let args: Vec<String> = bc
            .args(pool)
            .map(|a| self.op(a.as_value().expect("value block arg")))
            .collect();
        if args.is_empty() {
            let from = self.cur.clone();
            self.incoming.entry(blk).or_default().push(Edge { from, args });
            return self.label(blk);
        }
        let l = format!("e{}", self.tramps.len());
        self.tramps.push((l.clone(), blk, args));
        l
    }

    fn inst(&mut self, inst: Inst) {
        let dfg = &self.f.dfg;
        let data = dfg.insts[inst].clone();
        let opc = data.opcode();
        match data {
            InstructionData::UnaryImm { imm, .. } => {
                let t = dfg.ctrl_typevar(inst);
                let bits = imm.bits();
                // Normalise to the signed value of the type's width.
                let v = match t {
                    types::I8 => bits as i8 as i64,
                    types::I16 => bits as i16 as i64,
                    types::I32 => bits as i32 as i64,
                    _ => bits,
                };
                self.set(inst, 0, v.to_string());
            }
            InstructionData::UnaryIeee64 { imm, .. } => {
                self.set(inst, 0, double_lit(imm.bits()));
            }
            InstructionData::Binary { args, .. } => self.binary(inst, opc, args),
            InstructionData::IntCompare { args, cond, .. } => {
                let (a, b) = (self.op(args[0]), self.op(args[1]));
                let t = llty(self.ty(args[0]));
                let c = self.def(format!("icmp {} {t} {a}, {b}", icc(cond)));
                let z = self.def(format!("zext i1 {c} to i8"));
                self.set(inst, 0, z);
            }
            InstructionData::FloatCompare { args, cond, .. } => {
                let (a, b) = (self.op(args[0]), self.op(args[1]));
                let c = self.def(format!("fcmp {} double {a}, {b}", fcc(cond)));
                let z = self.def(format!("zext i1 {c} to i8"));
                self.set(inst, 0, z);
            }
            InstructionData::Unary { arg, .. } => self.unary(inst, opc, arg),
            InstructionData::Ternary { args, .. } => {
                assert_eq!(opc, Opcode::Select, "ternary {opc}");
                let c = self.to_i1(args[0]);
                let (a, b) = (self.op(args[1]), self.op(args[2]));
                let t = llty(self.ty(args[1]));
                let r = self.def(format!("select i1 {c}, {t} {a}, {t} {b}"));
                self.set(inst, 0, r);
            }
            InstructionData::Load { arg, flags, offset, .. } => {
                let t = dfg.ctrl_typevar(inst);
                let p = self.ptr(arg, offset.into());
                let al = if self.f.dfg.mem_flags[flags].aligned() { t.bytes().max(1) } else { 1 };
                let r = self.def(format!("load {}, ptr {p}, align {al}", llty(t)));
                self.set(inst, 0, r);
            }
            InstructionData::Store { args, flags, offset, .. } => {
                let t = self.ty(args[0]);
                let p = self.ptr(args[1], offset.into());
                let v = self.op(args[0]);
                let al = if self.f.dfg.mem_flags[flags].aligned() { t.bytes().max(1) } else { 1 };
                self.line(format!("store {} {v}, ptr {p}, align {al}", llty(t)));
            }
            InstructionData::LoadNoOffset { arg, .. } => {
                // The only use is the cancellation poll (`atomic_load`).
                assert_eq!(opc, Opcode::AtomicLoad, "load-no-offset {opc}");
                let t = dfg.ctrl_typevar(inst);
                let p = self.ptr(arg, 0);
                let r = self.def(format!(
                    "load atomic {}, ptr {p} monotonic, align {}",
                    llty(t),
                    t.bytes()
                ));
                self.set(inst, 0, r);
            }
            InstructionData::StackAddr { stack_slot, offset, .. } => {
                let off: i32 = offset.into();
                let base = format!("%ss{}", stack_slot.as_u32());
                let p = if off == 0 {
                    base
                } else {
                    self.def(format!("getelementptr inbounds i8, ptr {base}, i64 {off}"))
                };
                let i = self.def(format!("ptrtoint ptr {p} to i64"));
                self.set(inst, 0, i);
            }
            InstructionData::UnaryGlobalValue { global_value, .. } => {
                let sym = match &self.f.global_values[global_value] {
                    GlobalValueData::Symbol { name, offset, .. } => {
                        let off: i64 = (*offset).into();
                        (self.name_of(name), off)
                    }
                    other => panic!("unsupported global value {other:?}"),
                };
                self.data.insert(sym.0.clone(), ());
                let base = format!("@\"{}\"", sym.0);
                let p = if sym.1 == 0 {
                    base
                } else {
                    self.def(format!("getelementptr inbounds i8, ptr {base}, i64 {}", sym.1))
                };
                let i = self.def(format!("ptrtoint ptr {p} to i64"));
                self.set(inst, 0, i);
            }
            InstructionData::FuncAddr { func_ref, .. } => {
                let name = self.callee(func_ref);
                let i = self.def(format!("ptrtoint ptr @\"{name}\" to i64"));
                self.set(inst, 0, i);
            }
            InstructionData::NullAry { .. } => {
                assert_eq!(opc, Opcode::GetStackPointer, "null-ary {opc}");
                let p = self.def("call ptr @llvm.frameaddress.p0(i32 0)".into());
                let i = self.def(format!("ptrtoint ptr {p} to i64"));
                self.set(inst, 0, i);
            }
            InstructionData::Call { args, func_ref, .. } => {
                let name = self.callee(func_ref);
                let sigref = self.ext_func(func_ref).signature;
                let vals: Vec<Value> = args.as_slice(&self.f.dfg.value_lists).to_vec();
                self.call(inst, sigref, &format!("@\"{name}\""), &vals);
            }
            InstructionData::CallIndirect { args, sig_ref, .. } => {
                let vals: Vec<Value> = args.as_slice(&self.f.dfg.value_lists).to_vec();
                let callee = self.op(vals[0]);
                let p = self.def(format!("inttoptr i64 {callee} to ptr"));
                self.call(inst, sig_ref, &p, &vals[1..]);
            }
            InstructionData::Jump { destination, .. } => {
                let t = self.target(destination);
                self.line(format!("br label %{t}"));
            }
            InstructionData::Brif { arg, blocks, .. } => {
                let c = self.to_i1(arg);
                let (t, e) = (self.target(blocks[0]), self.target(blocks[1]));
                self.line(format!("br i1 {c}, label %{t}, label %{e}"));
            }
            InstructionData::BranchTable { arg, table, .. } => {
                let jt = &self.f.stencil.dfg.jump_tables[table];
                let default = self.target(jt.default_block());
                let mut cases = String::new();
                for (i, bc) in jt.as_slice().iter().enumerate() {
                    let t = self.target(*bc);
                    let _ = write!(cases, " i32 {i}, label %{t}");
                }
                let a = self.op(arg);
                self.line(format!("switch i32 {a}, label %{default} [{cases} ]"));
            }
            InstructionData::MultiAry { args, .. } => {
                assert_eq!(opc, Opcode::Return, "multi-ary {opc}");
                let vals: Vec<Value> = args.as_slice(&self.f.dfg.value_lists).to_vec();
                self.ret(&vals);
            }
            InstructionData::Trap { .. } => {
                self.line("call void @llvm.trap()");
                self.line("unreachable");
            }
            other => panic!("unsupported instruction {other:?}"),
        }
    }

    fn ret(&mut self, vals: &[Value]) {
        match vals {
            [] => self.line("ret void"),
            [v] => {
                let (t, o) = (self.ty(*v), self.op(*v));
                self.line(format!("ret {}{} {o}", llty(t), attr(t)));
            }
            vs => {
                let ts: Vec<_> = vs.iter().map(|v| llty(self.ty(*v))).collect();
                let agg_t = format!("{{ {} }}", ts.join(", "));
                let mut agg = "undef".to_string();
                for (i, v) in vs.iter().enumerate() {
                    let o = self.op(*v);
                    agg = self.def(format!(
                        "insertvalue {agg_t} {agg}, {} {o}, {i}",
                        llty(self.ty(*v))
                    ));
                }
                self.line(format!("ret {agg_t} {agg}"));
            }
        }
    }

    fn callee(&mut self, fr: ir::FuncRef) -> String {
        let data = self.ext_func(fr);
        let name = self.name_of(&data.name);
        let sig = &self.f.dfg.signatures[data.signature];
        let decl = format!(
            "declare {} @\"{name}\"({})",
            ret_ty(&sig.returns),
            sig_params(sig)
        );
        self.decls.entry(name.clone()).or_insert(decl);
        name
    }

    fn call(&mut self, inst: Inst, sigref: ir::SigRef, callee: &str, args: &[Value]) {
        let sig = self.f.dfg.signatures[sigref].clone();
        let a: Vec<String> = args
            .iter()
            .map(|v| {
                let t = self.ty(*v);
                format!("{}{} {}", llty(t), attr(t), self.op(*v))
            })
            .collect();
        let rt = ret_ty(&sig.returns);
        let rhs = format!("call {rt} {callee}({})", a.join(", "));
        match sig.returns.len() {
            0 => {
                self.line(rhs);
                if self.is_noreturn_follow(inst) {
                    // A call followed by `trap` is already terminated by the trap.
                }
            }
            1 => {
                let d = self.def(rhs);
                self.set(inst, 0, d);
            }
            n => {
                let agg = self.def(rhs);
                for i in 0..n {
                    let e = self.def(format!("extractvalue {rt} {agg}, {i}"));
                    self.set(inst, i, e);
                }
            }
        }
    }

    fn is_noreturn_follow(&self, _inst: Inst) -> bool {
        false
    }

    fn binary(&mut self, inst: Inst, opc: Opcode, args: [Value; 2]) {
        let (a, b) = (self.op(args[0]), self.op(args[1]));
        let t = self.ty(args[0]);
        let lt = llty(t);
        let simple = |s: &str| format!("{s} {lt} {a}, {b}");
        let rhs = match opc {
            Opcode::Iadd => simple("add"),
            Opcode::Isub => simple("sub"),
            Opcode::Imul => simple("mul"),
            Opcode::Sdiv => simple("sdiv"),
            Opcode::Srem => simple("srem"),
            Opcode::Band => simple("and"),
            Opcode::Bor => simple("or"),
            Opcode::Bxor => simple("xor"),
            Opcode::Fadd => format!("fadd double {a}, {b}"),
            Opcode::Fsub => format!("fsub double {a}, {b}"),
            Opcode::Fmul => format!("fmul double {a}, {b}"),
            Opcode::Fdiv => format!("fdiv double {a}, {b}"),
            Opcode::Ishl | Opcode::Sshr | Opcode::Ushr => {
                // Cranelift masks the shift amount to the type width; LLVM makes oversize shifts poison.
                let mask = t.bits() - 1;
                let m = self.def(format!("and {} {b}, {mask}", llty(self.ty(args[1]))));
                let m = if self.ty(args[1]) == t {
                    m
                } else if self.ty(args[1]).bits() > t.bits() {
                    self.def(format!("trunc {} {m} to {lt}", llty(self.ty(args[1]))))
                } else {
                    self.def(format!("zext {} {m} to {lt}", llty(self.ty(args[1]))))
                };
                let op = match opc {
                    Opcode::Ishl => "shl",
                    Opcode::Sshr => "ashr",
                    _ => "lshr",
                };
                format!("{op} {lt} {a}, {m}")
            }
            Opcode::SaddOverflow | Opcode::SsubOverflow | Opcode::SmulOverflow => {
                let name = match opc {
                    Opcode::SaddOverflow => "sadd",
                    Opcode::SsubOverflow => "ssub",
                    _ => "smul",
                };
                let st = format!("{{ {lt}, i1 }}");
                let r = self.def(format!(
                    "call {st} @llvm.{name}.with.overflow.{lt}({lt} {a}, {lt} {b})"
                ));
                let v = self.def(format!("extractvalue {st} {r}, 0"));
                let o = self.def(format!("extractvalue {st} {r}, 1"));
                let z = self.def(format!("zext i1 {o} to i8"));
                self.set(inst, 0, v);
                self.set(inst, 1, z);
                return;
            }
            Opcode::UsubOverflow | Opcode::UaddOverflow | Opcode::UmulOverflow => {
                let name = match opc {
                    Opcode::UaddOverflow => "uadd",
                    Opcode::UsubOverflow => "usub",
                    _ => "umul",
                };
                let st = format!("{{ {lt}, i1 }}");
                let r = self.def(format!(
                    "call {st} @llvm.{name}.with.overflow.{lt}({lt} {a}, {lt} {b})"
                ));
                let v = self.def(format!("extractvalue {st} {r}, 0"));
                let o = self.def(format!("extractvalue {st} {r}, 1"));
                let z = self.def(format!("zext i1 {o} to i8"));
                self.set(inst, 0, v);
                self.set(inst, 1, z);
                return;
            }
            other => panic!("unsupported binary op {other}"),
        };
        let d = self.def(rhs);
        self.set(inst, 0, d);
    }

    fn unary(&mut self, inst: Inst, opc: Opcode, arg: Value) {
        let a = self.op(arg);
        let t = self.ty(arg);
        let rt = self.f.dfg.ctrl_typevar(inst);
        let rhs = match opc {
            Opcode::Ineg => format!("sub {} 0, {a}", llty(t)),
            Opcode::Fneg => format!("fneg double {a}"),
            Opcode::Fabs => format!("call double @llvm.fabs.f64(double {a})"),
            Opcode::Sqrt => format!("call double @llvm.sqrt.f64(double {a})"),
            Opcode::Uextend => format!("zext {} {a} to {}", llty(t), llty(rt)),
            Opcode::Sextend => format!("sext {} {a} to {}", llty(t), llty(rt)),
            Opcode::Ireduce => format!("trunc {} {a} to {}", llty(t), llty(rt)),
            Opcode::FcvtFromSint => format!("sitofp {} {a} to double", llty(t)),
            Opcode::FcvtToSintSat => {
                format!(
                    "call {0} @llvm.fptosi.sat.{0}.f64(double {a})",
                    llty(rt)
                )
            }
            Opcode::Bnot => format!("xor {} {a}, -1", llty(t)),
            other => panic!("unsupported unary op {other}"),
        };
        let d = self.def(rhs);
        self.set(inst, 0, d);
    }
}

impl LlvmModule {
    /// Appends the definition of `f` named `name`; `local` makes the symbol internal.
    pub fn add_function(
        &mut self,
        name: &str,
        f: &Function,
        syms: &dyn Symbols,
        hidden: bool,
        cold_blocks: &[Block],
    ) {
        let _ = cold_blocks;
        let blocks: Vec<Block> = f.layout.blocks().collect();
        let entry = blocks[0];
        let mut tr = Tr {
            f,
            syms,
            out: String::new(),
            ops: HashMap::new(),
            tmp: 0,
            incoming: HashMap::new(),
            tramps: Vec::new(),
            cur: String::new(),
            decls: &mut self.decls,
            data: &mut self.data,
        };
        // Entry parameters are the function parameters; other block parameters are phis.
        let mut params = Vec::new();
        for (i, p) in f.dfg.block_params(entry).iter().enumerate() {
            let t = f.dfg.value_type(*p);
            tr.ops.insert(*p, format!("%a{i}"));
            params.push(format!("{}{} %a{i}", llty(t), attr(t)));
        }
        for b in &blocks[1..] {
            for (i, p) in f.dfg.block_params(*b).iter().enumerate() {
                tr.ops.insert(*p, format!("%p{}_{i}", b.as_u32()));
            }
        }
        // Pre-assign operands to every instruction result so that uses before definitions in
        // layout order (loops) resolve: each result is named after its value.
        let mut body = String::new();
        for b in &blocks {
            tr.out.clear();
            tr.cur = tr.label(*b);
            let _ = writeln!(body, "{}:", tr.cur);
            let start = body.len();
            let _ = start;
            for inst in f.layout.block_insts(*b) {
                tr.inst(inst);
            }
            body.push_str(&tr.out);
        }
        // Trampolines carry arguments into phis.
        let tramps = std::mem::take(&mut tr.tramps);
        let mut tbody = String::new();
        for (l, blk, args) in &tramps {
            let _ = writeln!(tbody, "{l}:\n  br label %{}", tr.label(*blk));
            tr.incoming
                .entry(*blk)
                .or_default()
                .push(Edge { from: l.clone(), args: args.clone() });
        }
        // Phis: now the full incoming set is known.
        let mut text = String::new();
        let mut final_body = String::new();
        for line in body.lines() {
            if let Some(lab) = line.strip_suffix(':').filter(|l| !l.starts_with(' ')) {
                final_body.push_str(line);
                final_body.push('\n');
                if let Some(bn) = lab.strip_prefix('b').and_then(|n| n.parse::<u32>().ok()) {
                    let blk = Block::from_u32(bn);
                    if blk != entry {
                        let edges = tr.incoming.get(&blk).map(Vec::as_slice).unwrap_or(&[]);
                        for (i, p) in f.dfg.block_params(blk).iter().enumerate() {
                            let t = llty(f.dfg.value_type(*p));
                            let ins: Vec<String> = edges
                                .iter()
                                .map(|e| format!("[ {}, %{} ]", e.args[i], e.from))
                                .collect();
                            let _ = writeln!(
                                final_body,
                                "  %p{bn}_{i} = phi {t} {}",
                                ins.join(", ")
                            );
                        }
                    }
                }
                continue;
            }
            final_body.push_str(line);
            final_body.push('\n');
        }
        text.push_str(&final_body);
        text.push_str(&tbody);
        let mut allocas = String::new();
        for (ss, data) in f.sized_stack_slots.iter() {
            let _ = writeln!(
                allocas,
                "  %ss{} = alloca [{} x i8], align {}",
                ss.as_u32(),
                data.size.max(1),
                1u32 << data.align_shift
            );
        }
        // Allocas must sit in the entry block, right after its label.
        let (first, rest) = text.split_once('\n').expect("entry label");
        let vis = if hidden { "hidden " } else { "" };
        let header = format!(
            "define {vis}{} @\"{name}\"({}) #0 {{\n",
            ret_ty(&f.signature.returns),
            params.join(", ")
        );
        self.body.push_str(&header);
        self.body.push_str(first);
        self.body.push('\n');
        self.body.push_str(&allocas);
        self.body.push_str(rest);
        self.body.push_str("}\n\n");
        self.defined.push(name.to_string());
    }

    /// The finished module text.
    pub fn finish(&self, triple: &str) -> String {
        let mut s = String::new();
        let _ = writeln!(s, "target triple = \"{triple}\"");
        s.push_str(&self.body);
        for (name, decl) in &self.decls {
            if !self.defined.contains(name) {
                s.push_str(decl);
                s.push('\n');
            }
        }
        for name in self.data.keys() {
            if !self.defined.contains(name) {
                let _ = writeln!(s, "@\"{name}\" = external global i8");
            }
        }
        s.push_str(
            "declare void @llvm.trap() cold noreturn nounwind\n\
             declare ptr @llvm.frameaddress.p0(i32)\n\
             declare double @llvm.fabs.f64(double)\n\
             declare double @llvm.sqrt.f64(double)\n\
             declare i64 @llvm.fptosi.sat.i64.f64(double)\n",
        );
        for op in ["sadd", "ssub", "smul", "uadd", "usub", "umul"] {
            for t in ["i64", "i32", "i8"] {
                let _ = writeln!(
                    s,
                    "declare {{ {t}, i1 }} @llvm.{op}.with.overflow.{t}({t}, {t})"
                );
            }
        }
        s.push_str("attributes #0 = { \"frame-pointer\"=\"all\" nounwind }\n");
        s
    }
}
