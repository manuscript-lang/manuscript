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
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fmt::Write as _;

/// Resolves the symbol a Cranelift external name refers to.
pub trait Symbols {
    /// Symbol of the user-named function or data object `(namespace, index)`.
    fn symbol(&self, namespace: u32, index: u32) -> String;
    /// Source `(file index, line)` behind a Cranelift source-location value.
    fn loc(&self, bits: u32) -> Option<(u32, u32, u32)>;
    /// Inlined-callee scope `idx` (1-based): `(name, file, parent, call_line)`.
    fn scope(&self, idx: u32) -> Option<(String, u32, u32, u32)>;
}

/// An LLVM module under construction.
pub struct LlvmModule {
    di: DebugInfo,
    /// Fault call sites numbered so far (unique across the module).
    sites: u32,
    /// Function definitions in emission order.
    defs: Vec<Def>,
    /// `declare` lines of external functions, by symbol.
    decls: BTreeMap<String, String>,
    /// External data symbols referenced.
    data: BTreeMap<String, ()>,
    /// Symbols defined in this module.
    defined: Vec<String>,
}

/// Symbol of the empty function every module starts with: the fault and profile tables address
/// all LLVM-built code as offsets from it, so the functions themselves need no visible symbol.
pub const TEXT_ANCHOR: &str = "ms.text.base";

/// A finished function definition; its linkage is chosen once the whole module is known.
struct Def {
    name: String,
    /// Part of the program's external interface (exported or entry), so it stays visible.
    public: bool,
    /// `define ` is followed by the linkage, then this: return type, name, parameters, attributes.
    header: String,
    /// The entry label, the stack slots, then the rest of the body.
    body: String,
}

/// Line-table metadata under construction.
struct DebugInfo {
    /// Metadata nodes after the fixed ones, one per line.
    meta: Vec<String>,
    /// Source files (`m.files`); `None` entries are unusable paths.
    files: Vec<Option<String>>,
    cwd: String,
    /// Location node per `(file, line, scope)`.
    locs: HashMap<(usize, u32, u32, u32), usize>,
    /// Subprogram per inlined-callee scope.
    scope_sp: HashMap<u32, usize>,
    /// `inlinedAt` location per inlined-callee scope.
    scope_at: HashMap<u32, usize>,
    /// File-switching scope per `(subprogram, file)`.
    lexical: HashMap<(usize, u32), usize>,
}

impl DebugInfo {
    fn push(&mut self, text: String) -> usize {
        self.meta.push(text);
        self.meta.len() - 1
    }

    fn file_node(&self, file: u32) -> usize {
        FIRST_FILE + (file as usize).min(self.files.len().saturating_sub(1))
    }

    /// Subprogram for inlined scope `idx`, creating it and its enclosing chain.
    fn scope_sp(&mut self, syms: &dyn Symbols, idx: u32, fn_sp: usize) -> usize {
        if let Some(&n) = self.scope_sp.get(&idx) {
            return n;
        }
        let (name, file, ..) = syms.scope(idx).unwrap_or_default();
        let fnode = self.file_node(file);
        let n = self.push(format!(
            "distinct !DISubprogram(name: \"{}\", scope: !{fnode}, file: !{fnode}, line: 1, type: !4, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !0)",
            name.replace(['"', '\\'], "'")
        ));
        self.scope_sp.insert(idx, n);
        let _ = fn_sp;
        n
    }

    /// `inlinedAt` location for scope `idx` (the call site in its parent).
    fn scope_at(&mut self, syms: &dyn Symbols, idx: u32, fn_sp: usize) -> usize {
        if let Some(&n) = self.scope_at.get(&idx) {
            return n;
        }
        let (_, _, parent, call_line) = syms.scope(idx).unwrap_or_default();
        let (scope, outer) = if parent == 0 {
            (fn_sp, None)
        } else {
            (
                self.scope_sp(syms, parent, fn_sp),
                Some(self.scope_at(syms, parent, fn_sp)),
            )
        };
        let text = match outer {
            Some(o) => format!("!DILocation(line: {call_line}, scope: !{scope}, inlinedAt: !{o})"),
            None => format!("!DILocation(line: {call_line}, scope: !{scope})"),
        };
        let n = self.push(text);
        self.scope_at.insert(idx, n);
        n
    }

    /// The location node for source location `bits` inside function subprogram `fn_sp`.
    fn location(
        &mut self,
        syms: &dyn Symbols,
        bits: u32,
        fn_sp: usize,
        fn_file: u32,
    ) -> Option<usize> {
        let (file, line, scope) = syms.loc(bits)?;
        if let Some(&n) = self.locs.get(&(fn_sp, file, line, scope)) {
            return Some(n);
        }
        let (sp, sp_file, at) = if scope == 0 {
            (fn_sp, fn_file, None)
        } else {
            let sp = self.scope_sp(syms, scope, fn_sp);
            let at = self.scope_at(syms, scope, fn_sp);
            let sf = syms.scope(scope).map_or(file, |s| s.1);
            (sp, sf, Some(at))
        };
        let scope_node = if file == sp_file {
            sp
        } else if let Some(&n) = self.lexical.get(&(sp, file)) {
            n
        } else {
            let f = self.file_node(file);
            let n = self.push(format!(
                "distinct !DILexicalBlockFile(scope: !{sp}, file: !{f}, discriminator: 0)"
            ));
            self.lexical.insert((sp, file), n);
            n
        };
        let text = match at {
            Some(a) => format!("!DILocation(line: {line}, scope: !{scope_node}, inlinedAt: !{a})"),
            None => format!("!DILocation(line: {line}, scope: !{scope_node})"),
        };
        let n = self.push(text);
        self.locs.insert((fn_sp, file, line, scope), n);
        Some(n)
    }
}

/// Metadata ids fixed by [`LlvmModule::finish`]: compile unit, two module flags, the empty
/// type list and the subroutine type; file `i` is `FIRST_FILE + i`.
const FIRST_FILE: usize = 5;

impl LlvmModule {
    /// A module whose debug info names `files` relative to `cwd`.
    pub fn new(mut files: Vec<Option<String>>, cwd: String) -> Self {
        if files.is_empty() {
            files.push(None);
        }
        let nfiles = files.len();
        let mut m = LlvmModule {
            sites: 0,
            di: DebugInfo {
                meta: Vec::new(),
                files,
                cwd,
                locs: HashMap::new(),
                scope_sp: HashMap::new(),
                scope_at: HashMap::new(),
                lexical: HashMap::new(),
            },
            defs: Vec::new(),
            decls: BTreeMap::new(),
            data: BTreeMap::new(),
            defined: Vec::new(),
        };
        // Placeholder slots for the fixed ids and one `DIFile` per file.
        m.di.meta.resize(FIRST_FILE + nfiles, String::new());
        m
    }
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

/// These runtime entry points terminate or unwind; none returns to its caller.
fn fault_function(name: &str) -> bool {
    matches!(
        name,
        "msrt_fault"
            | "msrt_fault_string"
            | "msrt_fault_depth"
            | "msrt_fault_unwrap_none"
            | "msrt_fault_result_get"
            | "msrt_fault_result_err"
            | "msrt_fault_int_overflow"
            | "msrt_fault_div_zero"
            | "msrt_fault_rem_zero"
            | "msrt_fault_div_overflow"
            | "msrt_index_fault"
            | "msrt_list_index_fault"
            | "msrt_cancelled"
    )
}

fn ret_ty(rets: &[ir::AbiParam]) -> String {
    match rets {
        [] => "void".into(),
        [r] => format!(
            "{}{}",
            attr(r.value_type).trim_start(),
            if attr(r.value_type).is_empty() {
                llty(r.value_type).to_string()
            } else {
                format!(" {}", llty(r.value_type))
            }
        ),
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
    /// Debug location (`!dbg !N`) applied to emitted lines.
    dbg: Option<usize>,
    /// Fault call sites met so far.
    sites: u32,
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
        if let Some(d) = self.dbg {
            let _ = write!(self.out, ", !dbg !{d}");
        }
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

    fn cond_i1(&mut self, v: Value) -> String {
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
            self.incoming
                .entry(blk)
                .or_default()
                .push(Edge { from, args });
            return self.label(blk);
        }
        let l = format!("e{}", self.tramps.len());
        self.tramps.push((l.clone(), blk, args));
        l
    }

    fn inst(&mut self, inst: Inst) {
        let dfg = &self.f.dfg;
        let data = dfg.insts[inst];
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
                let c = self.cond_i1(args[0]);
                let (a, b) = (self.op(args[1]), self.op(args[2]));
                let t = llty(self.ty(args[1]));
                let r = self.def(format!("select i1 {c}, {t} {a}, {t} {b}"));
                self.set(inst, 0, r);
            }
            InstructionData::Load {
                arg, flags, offset, ..
            } => {
                let t = dfg.ctrl_typevar(inst);
                let p = self.ptr(arg, offset.into());
                let al = if self.f.dfg.mem_flags[flags].aligned() {
                    t.bytes().max(1)
                } else {
                    1
                };
                let r = self.def(format!("load {}, ptr {p}, align {al}", llty(t)));
                self.set(inst, 0, r);
            }
            InstructionData::Store {
                args,
                flags,
                offset,
                ..
            } => {
                let t = self.ty(args[0]);
                let p = self.ptr(args[1], offset.into());
                let v = self.op(args[0]);
                let al = if self.f.dfg.mem_flags[flags].aligned() {
                    t.bytes().max(1)
                } else {
                    1
                };
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
            InstructionData::StackAddr {
                stack_slot, offset, ..
            } => {
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
                    self.def(format!(
                        "getelementptr inbounds i8, ptr {base}, i64 {}",
                        sym.1
                    ))
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
            InstructionData::Call { args, func_ref, .. }
                if matches!(
                    self.ext_func(func_ref).name,
                    ExternalName::LibCall(
                        ir::LibCall::Memcpy | ir::LibCall::Memmove | ir::LibCall::Memset
                    )
                ) =>
            {
                let vals: Vec<Value> = args.as_slice(&self.f.dfg.value_lists).to_vec();
                let ExternalName::LibCall(lc) = self.ext_func(func_ref).name.clone() else {
                    unreachable!()
                };
                let dst = self.ptr(vals[0], 0);
                let n = self.op(vals[2]);
                match lc {
                    ir::LibCall::Memset => {
                        let v = self.op(vals[1]);
                        let b = self.def(format!("trunc i32 {v} to i8"));
                        self.line(format!(
                            "call void @llvm.memset.p0.i64(ptr {dst}, i8 {b}, i64 {n}, i1 false)"
                        ));
                    }
                    _ => {
                        let src = self.ptr(vals[1], 0);
                        let f = if lc == ir::LibCall::Memcpy {
                            "memcpy"
                        } else {
                            "memmove"
                        };
                        self.line(format!(
                            "call void @llvm.{f}.p0.p0.i64(ptr {dst}, ptr {src}, i64 {n}, i1 false)"
                        ));
                    }
                }
                if !self.f.dfg.inst_results(inst).is_empty() {
                    let d = self.op(vals[0]);
                    self.set(inst, 0, d);
                }
            }
            InstructionData::Call { args, func_ref, .. } => {
                let name = self.callee(func_ref);
                if fault_function(&name) {
                    // Keeps fault sites distinct, so LLVM neither merges them (which drops the
                    // line of a fault in a trace) nor hoists them.
                    self.sites += 1;
                    self.line(format!(
                        "call void asm sideeffect \"\", \"i\"(i32 {})",
                        self.sites
                    ));
                }
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
                let c = self.cond_i1(arg);
                let pool = &self.f.dfg.value_lists;
                let cold = blocks.map(|b| self.f.layout.is_cold(b.block(pool)));
                let (t, e) = (self.target(blocks[0]), self.target(blocks[1]));
                let weights = match cold {
                    [true, false] => ", !prof !{!\"branch_weights\", i32 1, i32 2000}",
                    [false, true] => ", !prof !{!\"branch_weights\", i32 2000, i32 1}",
                    _ => "",
                };
                self.line(format!("br i1 {c}, label %{t}, label %{e}{weights}"));
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
                self.line(format!("ret {} {o}", llty(t)));
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
        let attrs = if fault_function(&name) {
            " cold noreturn"
        } else {
            ""
        };
        let decl = format!(
            "declare {} @\"{name}\"({}){attrs}",
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
                format!("call {0} @llvm.fptosi.sat.{0}.f64(double {a})", llty(rt))
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
        display: &str,
        fn_loc: (u32, u32),
        f: &Function,
        syms: &dyn Symbols,
        public: bool,
    ) {
        let blocks: Vec<Block> = f.layout.blocks().collect();
        let entry = blocks[0];
        // Debug info: a subprogram per function and one location node per (file, line, scope).
        let (sp_file, sp_line) = fn_loc;
        let sp = self.di.meta.len();
        let file_node = self.di.file_node(sp_file);
        self.di.meta.push(format!(
            "distinct !DISubprogram(name: \"{}\", linkageName: \"{}\", scope: !{file_node}, file: !{file_node}, line: {sp_line}, type: !4, scopeLine: {sp_line}, spFlags: DISPFlagDefinition, unit: !0)",
            display.replace(['"', '\\'], "'"),
            name.replace(['"', '\\'], "'")
        ));
        let none_loc = self.di.push(format!("!DILocation(line: 0, scope: !{sp})"));
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
            dbg: Some(none_loc),
            sites: self.sites,
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
        // Translate each block's instructions; phis are added once every incoming edge is known.
        let mut bodies: Vec<(Block, String)> = Vec::with_capacity(blocks.len());
        for b in &blocks {
            tr.out.clear();
            tr.cur = tr.label(*b);
            for inst in f.layout.block_insts(*b) {
                tr.dbg = Some(
                    self.di
                        .location(syms, f.srcloc(inst).bits(), sp, sp_file)
                        .unwrap_or(none_loc),
                );
                tr.inst(inst);
            }
            bodies.push((*b, std::mem::take(&mut tr.out)));
        }
        self.sites = tr.sites;
        // Trampolines carry arguments into phis.
        let tramps = std::mem::take(&mut tr.tramps);
        for (l, blk, args) in &tramps {
            tr.incoming.entry(*blk).or_default().push(Edge {
                from: l.clone(),
                args: args.clone(),
            });
        }
        let mut text = String::new();
        for (b, code) in &bodies {
            let _ = writeln!(text, "{}:", tr.label(*b));
            if *b != entry {
                let edges = tr.incoming.get(b).map(Vec::as_slice).unwrap_or(&[]);
                for (i, p) in f.dfg.block_params(*b).iter().enumerate() {
                    let t = llty(f.dfg.value_type(*p));
                    let ins: Vec<String> = edges
                        .iter()
                        .map(|e| format!("[ {}, %{} ]", e.args[i], e.from))
                        .collect();
                    let _ = writeln!(text, "  %p{}_{i} = phi {t} {}", b.as_u32(), ins.join(", "));
                }
            }
            text.push_str(code);
        }
        for (l, blk, _) in &tramps {
            let _ = writeln!(text, "{l}:\n  br label %{}", tr.label(*blk));
        }
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
        let header = format!(
            "{} @\"{name}\"({}) #0 !dbg !{sp} {{\n",
            ret_ty(&f.signature.returns),
            params.join(", ")
        );
        let mut body = String::new();
        body.push_str(first);
        body.push('\n');
        body.push_str(&allocas);
        body.push_str(rest);
        body.push_str("}\n\n");
        self.defined.push(name.to_string());
        self.defs.push(Def {
            name: name.to_string(),
            public,
            header,
            body,
        });
    }

    /// Glue functions at the top of a chain of glue calls three or more levels deep. They stay
    /// out of line: inlining a chain nests one loop per element-type level, which makes the
    /// optimizer quadratic in the nesting depth of a literal. Shallow glue still inlines.
    fn deep_glue(&self) -> HashSet<String> {
        const GLUE: &str = "@\"ms.glue.";
        let callees: HashMap<&str, Vec<&str>> = self
            .defs
            .iter()
            .filter(|d| d.name.starts_with("ms.glue."))
            .map(|d| {
                let calls = d
                    .body
                    .match_indices(GLUE)
                    .filter_map(|(at, _)| {
                        let rest = &d.body[at + 2..];
                        rest.split('"').next()
                    })
                    .filter(|c| *c != d.name)
                    .collect();
                (d.name.as_str(), calls)
            })
            .collect();
        fn depth<'a>(
            name: &'a str,
            callees: &HashMap<&'a str, Vec<&'a str>>,
            memo: &mut HashMap<&'a str, usize>,
        ) -> usize {
            if let Some(d) = memo.get(name) {
                return *d;
            }
            // A cycle (recursive types) counts as shallow while it is being resolved.
            memo.insert(name, 0);
            let d = callees.get(name).map_or(0, |cs| {
                cs.iter()
                    .filter(|c| callees.contains_key(**c))
                    .map(|c| 1 + depth(c, callees, memo))
                    .max()
                    .unwrap_or(0)
            });
            memo.insert(name, d);
            d
        }
        let mut memo = HashMap::new();
        callees
            .keys()
            .filter(|n| depth(n, &callees, &mut memo) >= 3)
            .map(|n| n.to_string())
            .collect()
    }

    /// The finished module text. When `anchored`, functions are `internal` unless they are public
    /// or named in `pinned` (symbols the Cranelift object refers to), which lets LLVM drop and
    /// specialize them; otherwise every function keeps a symbol.
    pub fn finish(&self, triple: &str, pinned: &HashSet<String>, anchored: bool) -> String {
        let mut s = String::new();
        let _ = writeln!(s, "target triple = \"{triple}\"");
        if anchored {
            let _ = writeln!(
                s,
                "define void @\"{TEXT_ANCHOR}\"() #0 {{\n  ret void\n}}\n"
            );
        }
        let deep = self.deep_glue();
        for d in &self.defs {
            let header = if deep.contains(&d.name) {
                d.header.replacen(" #0 ", " #1 ", 1)
            } else {
                d.header.clone()
            };
            let vis = if d.public {
                ""
            } else if !anchored || pinned.contains(&d.name) {
                "hidden "
            } else {
                "internal "
            };
            let _ = write!(s, "define {vis}{header}{}", d.body);
        }
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
             declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)\n\
             declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1)\n\
             declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)\n\
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
        s.push_str("attributes #1 = { \"frame-pointer\"=\"all\" nounwind noinline }\n");
        // Debug metadata: line tables only (no variables, types or inline frames).
        let esc = |t: &str| t.replace('\\', "\\5C").replace('"', "\\22");
        let first_file = self.di.files.iter().position(Option::is_some).unwrap_or(0);
        s.push_str("!llvm.dbg.cu = !{!0}\n!llvm.module.flags = !{!1, !2}\n");
        let _ = writeln!(
            s,
            "!0 = distinct !DICompileUnit(language: DW_LANG_C99, file: !{}, producer: \"Manuscript\", isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly)",
            FIRST_FILE + first_file
        );
        s.push_str("!1 = !{i32 2, !\"Debug Info Version\", i32 3}\n");
        s.push_str("!2 = !{i32 7, !\"Dwarf Version\", i32 4}\n");
        s.push_str("!3 = !{}\n!4 = !DISubroutineType(types: !3)\n");
        for (i, f) in self.di.files.iter().enumerate() {
            let name = f.as_deref().unwrap_or("<unknown>");
            let _ = writeln!(
                s,
                "!{} = !DIFile(filename: \"{}\", directory: \"{}\")",
                FIRST_FILE + i,
                esc(name),
                esc(&self.di.cwd)
            );
        }
        for (i, n) in self
            .di
            .meta
            .iter()
            .enumerate()
            .skip(FIRST_FILE + self.di.files.len())
        {
            let _ = writeln!(s, "!{i} = {n}");
        }
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use cranelift_codegen::ir::{AbiParam, InstBuilder, Signature, TrapCode, UserFuncName};
    use cranelift_codegen::isa::CallConv;
    use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext};
    use std::process::Command;

    struct TestSymbols;

    impl Symbols for TestSymbols {
        fn symbol(&self, _: u32, _: u32) -> String {
            "msrt_fault_int_overflow".into()
        }
        fn loc(&self, _: u32) -> Option<(u32, u32, u32)> {
            None
        }
        fn scope(&self, _: u32) -> Option<(String, u32, u32, u32)> {
            None
        }
    }

    fn checked_add(cold_first: bool) -> Function {
        let mut sig = Signature::new(CallConv::SystemV);
        sig.params = vec![AbiParam::new(types::I64); 2];
        sig.returns.push(AbiParam::new(types::I64));
        let mut f = Function::with_name_signature(UserFuncName::user(0, 0), sig);
        let sigref = f.import_signature(Signature::new(CallConv::SystemV));
        let name = f.declare_imported_user_function(ir::UserExternalName::new(1, 0));
        let fault = f.import_function(ExtFuncData {
            name: ExternalName::User(name),
            signature: sigref,
            colocated: false,
            patchable: false,
        });
        let mut cx = FunctionBuilderContext::new();
        let mut b = FunctionBuilder::new(&mut f, &mut cx);
        let entry = b.create_block();
        let bad = b.create_block();
        let good = b.create_block();
        b.append_block_params_for_function_params(entry);
        b.switch_to_block(entry);
        let args = b.block_params(entry).to_vec();
        let (sum, overflow) = b.ins().sadd_overflow(args[0], args[1]);
        b.set_cold_block(bad);
        if cold_first {
            b.ins().brif(overflow, bad, &[], good, &[]);
        } else {
            let fits = b.ins().bxor_imm_s(overflow, 1);
            b.ins().brif(fits, good, &[], bad, &[]);
        }
        b.switch_to_block(bad);
        b.ins().call(fault, &[]);
        b.ins().trap(TrapCode::unwrap_user(1));
        b.switch_to_block(good);
        b.ins().return_(&[sum]);
        b.seal_all_blocks();
        b.finalize(cranelift_codegen::isa::TargetFrontendConfig {
            default_call_conv: CallConv::SystemV,
            pointer_width: target_lexicon::PointerWidth::U64,
            page_size_align_log2: 12,
        });
        f
    }

    fn module(cold_first: bool, triple: &str) -> String {
        let f = checked_add(cold_first);
        let mut m = LlvmModule::new(vec![Some("cold.ms".into())], ".".into());
        m.add_function("checked_add", "checked_add", (0, 1), &f, &TestSymbols, true);
        m.finish(triple, &HashSet::new(), false)
    }

    #[test]
    fn cold_edges_and_fault_declarations_keep_their_semantics() {
        for cold_first in [true, false] {
            let text = module(cold_first, "x86_64-unknown-linux-gnu");
            let weights = if cold_first {
                "i32 1, i32 2000"
            } else {
                "i32 2000, i32 1"
            };
            assert!(text.contains(weights), "{text}");
            assert!(
                text.contains("declare void @\"msrt_fault_int_overflow\"() cold noreturn"),
                "{text}"
            );
            assert!(
                text.contains("asm sideeffect"),
                "fault-site identity lost: {text}"
            );
        }
        assert!(fault_function("msrt_list_index_fault"));
        assert!(!fault_function("msrt_string_concat"));
        assert!(!fault_function("msrt_fault_user_function#1"));
    }

    #[test]
    fn checked_arithmetic_llvm_generates_objects_for_all_supported_targets() {
        let Some(tools) = crate::link::llvm_tools().unwrap() else {
            return;
        };
        let dir = std::env::temp_dir().join(format!("ms-llvm-targets-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let targets: [(&str, &[u8]); 6] = [
            ("x86_64-unknown-linux-gnu", b"\x7fELF"),
            ("aarch64-unknown-linux-gnu", b"\x7fELF"),
            ("x86_64-apple-darwin", b"\xcf\xfa\xed\xfe"),
            ("aarch64-apple-darwin", b"\xcf\xfa\xed\xfe"),
            ("x86_64-pc-windows-gnu", b"\x64\x86"),
            ("aarch64-pc-windows-gnu", b"\x64\xaa"),
        ];
        for (triple, magic) in targets {
            for cold_first in [true, false] {
                let stem = format!("{triple}-{cold_first}");
                let ll = dir.join(format!("{stem}.ll"));
                let bc = dir.join(format!("{stem}.bc"));
                let object = dir.join(format!("{stem}.o"));
                std::fs::write(&ll, module(cold_first, triple)).unwrap();
                for (tool, args) in [
                    (
                        "opt",
                        vec![
                            "-passes=default<O3>".into(),
                            "-verify-each".into(),
                            ll.as_os_str().to_owned(),
                            "-o".into(),
                            bc.as_os_str().to_owned(),
                        ],
                    ),
                    (
                        "llc",
                        vec![
                            "-O3".into(),
                            "-filetype=obj".into(),
                            bc.as_os_str().to_owned(),
                            "-o".into(),
                            object.as_os_str().to_owned(),
                        ],
                    ),
                ] {
                    let out = Command::new(tools.join(tool)).args(args).output().unwrap();
                    assert!(
                        out.status.success(),
                        "{triple} {tool}: {}",
                        String::from_utf8_lossy(&out.stderr)
                    );
                    assert!(!String::from_utf8_lossy(&out.stderr).contains("invalid debug info"));
                }
                assert!(
                    std::fs::read(&object).unwrap().starts_with(magic),
                    "{triple}"
                );
            }
        }
        std::fs::remove_dir_all(dir).unwrap();
    }
}
