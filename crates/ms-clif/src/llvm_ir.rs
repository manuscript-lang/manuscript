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
    /// Functions with loops over list elements get per-CPU copies (x86-64 only).
    per_cpu: bool,
    /// Fault call sites numbered so far (unique across the module).
    sites: u32,
    /// Function definitions in emission order.
    defs: Vec<Def>,
    /// `declare` lines of external functions, by symbol.
    decls: BTreeMap<String, String>,
    /// External data symbols referenced.
    data: BTreeMap<String, ()>,
    /// Internal functions' parameters that are exclusive pointers, by symbol. They are passed as
    /// `ptr noalias`, so LLVM knows nothing else the function reaches overlaps them.
    exclusive: HashMap<String, Vec<usize>>,
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
    /// The x86-64-v3 copy of a function with a loop over list elements: its header and body.
    avx2: Option<(String, String)>,
}

/// Body lines above which a function is compiled without LLVM's optimizer (`optnone`): SROA, the
/// SLP vectorizer and the code generator grow faster than linearly with one function's size, so
/// a generated function of thousands of statements took minutes. Hand-written functions are far
/// below this; a function above it is run-once straight-line code in practice.
const HUGE_FUNCTION_LINES: usize = 100_000;

/// Whether a function body is long enough to skip optimization.
fn is_huge(body: &str) -> bool {
    body.bytes().filter(|&b| b == b'\n').count() > HUGE_FUNCTION_LINES
}

/// Symbol suffix of a function's x86-64-v3 (AVX2, FMA) copy.
pub(crate) const AVX2_SUFFIX: &str = ".avx2";
/// Symbol suffix of a dispatched function's baseline copy.
pub(crate) const BASE_SUFFIX: &str = ".base";
/// `msrt_cpu_level` at or above this runs the x86-64-v3 copies.
const AVX2_LEVEL: u32 = 3;

/// The dispatcher `define` header and body for a function whose definition `header` names
/// `name`: it calls the AVX2 copy when the CPU supports it, else the baseline copy.
fn dispatcher(name: &str, header: &str) -> (String, String) {
    // `RET @"name"(PARAMS) #N !dbg !K {`: the dispatcher keeps the signature, drops the debug
    // subprogram (each belongs to one function), and passes its parameters through.
    let (ret, rest) = header
        .split_once(" @\"")
        .expect("header names the function");
    let params = rest
        .split_once('(')
        .and_then(|(_, p)| p.rsplit_once(')'))
        .map_or("", |(p, _)| p);
    let args = params
        .split(", ")
        .filter(|p| !p.is_empty())
        .map(|p| p.replace(" noalias", ""))
        .collect::<Vec<_>>()
        .join(", ");
    let bare = ret.trim_start_matches("zeroext ");
    let head_ret = ret;
    let call = |target: &str, r: &str| {
        if ret == "void" {
            format!("  tail call void @\"{name}{target}\"({args})\n  ret void\n")
        } else {
            format!("  %{r} = tail call {ret} @\"{name}{target}\"({args})\n  ret {bare} %{r}\n")
        }
    };
    let head = format!("{head_ret} @\"{name}\"({params}) #0 {{\n");
    let body = format!(
        "entry:\n  %l = call i64 @msrt_cpu_level()\n  %v3 = icmp sge i64 %l, {AVX2_LEVEL}\n  br i1 %v3, label %fast, label %base\nfast:\n{}base:\n{}}}\n\n",
        call(AVX2_SUFFIX, "fast.r"),
        call(BASE_SUFFIX, "base.r")
    );
    (head, body)
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
    /// Subprogram per (inlined-callee scope, function subprogram): a function translated twice
    /// (its AVX2 copy) needs its own chain.
    scope_sp: HashMap<(u32, usize), usize>,
    /// `inlinedAt` location per (inlined-callee scope, function subprogram).
    scope_at: HashMap<(u32, usize), usize>,
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
        if let Some(&n) = self.scope_sp.get(&(idx, fn_sp)) {
            return n;
        }
        let (name, file, ..) = syms.scope(idx).unwrap_or_default();
        let fnode = self.file_node(file);
        let n = self.push(format!(
            "distinct !DISubprogram(name: \"{}\", scope: !{fnode}, file: !{fnode}, line: 1, type: !4, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !0)",
            name.replace(['"', '\\'], "'")
        ));
        self.scope_sp.insert((idx, fn_sp), n);
        n
    }

    /// `inlinedAt` location for scope `idx` (the call site in its parent).
    fn scope_at(&mut self, syms: &dyn Symbols, idx: u32, fn_sp: usize) -> usize {
        if let Some(&n) = self.scope_at.get(&(idx, fn_sp)) {
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
        self.scope_at.insert((idx, fn_sp), n);
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
            per_cpu: true,
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
            exclusive: HashMap::new(),
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
        types::F32 => "float",
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
            | "msrt_fault_int_range"
            | "msrt_fault_div_zero"
            | "msrt_fault_rem_zero"
            | "msrt_fault_div_overflow"
            | "msrt_index_fault"
            | "msrt_list_index_fault"
            | "msrt_cancelled"
    )
}

/// What LLVM may assume about a runtime entry point that only inspects memory: it returns,
/// does not unwind, and writes nothing except, for `argmem`, the outputs its pointer arguments
/// name. Calls to these no longer clobber the caller's memory, so loads of list lengths, record
/// fields and map headers survive them. Only lookups with no descriptor callbacks (which could
/// run user code) and no fault belong here.
fn pure_runtime_attrs(name: &str) -> Option<&'static str> {
    match name {
        "msrt_map_slot_count"
        | "msrt_map_length"
        | "msrt_map_get_ptr_sw8"
        | "msrt_map_get_ptr_w8"
        | "msrt_map_contains_sw8"
        | "msrt_map_contains_w8"
        | "msrt_string_eq"
        | "msrt_string_hash"
        | "msrt_string_compare"
        | "msrt_string_is_empty"
        | "msrt_string_byte_length" => Some(" nounwind willreturn memory(read)"),
        _ => None,
    }
}

/// Returned scalar leaves above which a function is marked `noimplicitfloat`. The SLP vectorizer
/// skips such functions; it spends tens of milliseconds on the thousands of `insertvalue` and
/// `phi` lines that build a large flattened result (`FileSystem.stat`) and finds nothing to pack.
const WIDE_RETURN_LEAVES: usize = 16;

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

/// The intrinsic name suffix of a float type.
fn fsuf(t: Type) -> &'static str {
    if t == types::F32 { "f32" } else { "f64" }
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

/// The values of `f` used anywhere but as the condition of a `brif` or `select`.
fn wide_values(f: &Function) -> HashSet<Value> {
    let mut wide = HashSet::new();
    for block in f.layout.blocks() {
        for inst in f.layout.block_insts(block) {
            let data = &f.dfg.insts[inst];
            let cond = match data {
                InstructionData::Brif { arg, .. } => Some(*arg),
                InstructionData::Ternary {
                    opcode: Opcode::Select,
                    args,
                    ..
                } => Some(args[0]),
                _ => None,
            };
            let mut skipped = false;
            for v in f.dfg.inst_values(inst) {
                if !skipped && Some(v) == cond {
                    skipped = true;
                } else {
                    wide.insert(v);
                }
            }
        }
    }
    wide
}

struct Tr<'a> {
    f: &'a Function,
    syms: &'a dyn Symbols,
    out: String,
    /// Operand text of each Cranelift value.
    ops: HashMap<Value, String>,
    /// The `i1` behind a compare or overflow flag, which `ops` holds widened to `i8`. A branch on
    /// the widened form (`zext`, then `icmp ne 0`) made LLVM's InstCombine quadratic in the length
    /// of a compare-and-branch chain (8000 arms: 12s against 1.5s).
    flags: HashMap<Value, String>,
    /// Values with a use other than a branch or select condition: only these need the `i8` form.
    wide: HashSet<Value>,
    tmp: usize,
    /// Incoming edges per Cranelift block.
    incoming: HashMap<Block, Vec<Edge>>,
    /// Trampoline blocks to append after the instructions: (label, target, args).
    tramps: Vec<(String, Block, Vec<String>)>,
    cur: String,
    decls: &'a mut BTreeMap<String, String>,
    exclusive: &'a HashMap<String, Vec<usize>>,
    data: &'a mut BTreeMap<String, ()>,
    /// Debug location (`!dbg !N`) applied to emitted lines.
    dbg: Option<usize>,
    /// Fault call sites met so far.
    sites: u32,
    /// Addresses known to be a stack slot or symbol plus a constant offset. Memory accesses
    /// through them address the base directly instead of through `inttoptr`, so LLVM keeps
    /// their provenance: a slot whose address never reaches a call stays promotable to registers.
    bases: HashMap<Value, (String, i64)>,
    /// `base + scaled` sums where `scaled` is a product: element addresses. They are emitted as
    /// `inttoptr base` plus a `getelementptr`, so LLVM's loop analyses see one pointer and an
    /// affine offset instead of an opaque integer-to-pointer cast of the whole sum.
    indexed: HashMap<Value, (Value, Value)>,
    /// Layout position of each block, and of the block being translated.
    order: HashMap<Block, usize>,
    at: usize,
    /// Per block position: it addresses list elements, and it calls something other than a fault
    /// or a pure runtime helper (a loop that calls out cannot be vectorized).
    elements: Vec<bool>,
    calls: Vec<bool>,
    /// `(from, to)` layout positions of the branches that go back to an earlier or the same block.
    back_edges: Vec<(usize, usize)>,
    /// `(from, to)` layout positions of every branch in source-block order, and per block position: it ends the function
    /// (a return) or calls a fault.
    edges: Vec<(usize, usize)>,
    returns: Vec<bool>,
    faults: Vec<bool>,
}

impl<'a> Tr<'a> {
    /// Whether some loop addresses list elements, calls nothing and has a single way out: the
    /// loops LLVM may vectorize. A loop is the layout range from a branch target to the branch
    /// back to it. A search loop that returns or breaks early has a second way out and stays
    /// scalar, so a function holding only such loops keeps one copy and can be inlined.
    fn has_element_loop(&self) -> bool {
        self.back_edges.iter().any(|&(from, to)| {
            let range = to..=from;
            if !self.elements[to..=from].iter().any(|&e| e)
                || self.calls[to..=from].iter().any(|&c| c)
            {
                return false;
            }
            // Edges were appended as blocks were translated in layout order. Restrict the
            // scan to this loop instead of visiting every other loop's edges again.
            let first = self.edges.partition_point(|&(f, _)| f < to);
            let last = self.edges.partition_point(|&(f, _)| f <= from);
            let exits = self.edges[first..last]
                .iter()
                .filter(|&&(_, t)| !range.contains(&t) && !self.faults[t])
                .count()
                + self.returns[to..=from].iter().filter(|&&r| r).count();
            exits <= 1
        })
    }

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

    /// Records result `idx` of `inst` as the `i1` `flag` widened to `i8`.
    fn set_flag(&mut self, inst: Inst, idx: usize, flag: String) {
        let r = self.f.dfg.inst_results(inst)[idx];
        if self.wide.contains(&r) {
            let widened = self.def(format!("zext i1 {flag} to i8"));
            self.set(inst, idx, widened);
        }
        self.flags.insert(r, flag);
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
        if let Some(flag) = self.flags.get(&v) {
            return flag.clone();
        }
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
        if let Some((base, at)) = self.bases.get(&v).cloned() {
            let at = at.wrapping_add(i64::from(off));
            // A symbol's declared type or a parameter says nothing about its size, so only a
            // stack slot's offsets are known to stay in bounds.
            let inbounds = if base.starts_with("%ss") {
                " inbounds"
            } else {
                ""
            };
            return if at == 0 {
                base
            } else {
                self.def(format!("getelementptr{inbounds} i8, ptr {base}, i64 {at}"))
            };
        }
        let p = if let Some((base, scaled)) = self.indexed.get(&v).copied() {
            let (b, s) = (self.op(base), self.op(scaled));
            let bp = self.def(format!("inttoptr i64 {b} to ptr"));
            self.elements[self.at] = true;
            self.def(format!("getelementptr i8, ptr {bp}, i64 {s}"))
        } else {
            let o = self.op(v);
            self.def(format!("inttoptr i64 {o} to ptr"))
        };
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
        if let Some(&to) = self.order.get(&blk) {
            self.edges.push((self.at, to));
            if to <= self.at {
                self.back_edges.push((self.at, to));
            }
        }
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
            InstructionData::UnaryIeee32 { imm, .. } => {
                // LLVM spells a `float` constant as the double with the same value.
                let wide = f32::from_bits(imm.bits()) as f64;
                self.set(inst, 0, double_lit(wide.to_bits()));
            }
            InstructionData::UnaryIeee64 { imm, .. } => {
                self.set(inst, 0, double_lit(imm.bits()));
            }
            InstructionData::Binary { args, .. } => self.binary(inst, opc, args),
            InstructionData::IntCompare { args, cond, .. } => {
                let (a, b) = (self.op(args[0]), self.op(args[1]));
                let t = llty(self.ty(args[0]));
                let c = self.def(format!("icmp {} {t} {a}, {b}", icc(cond)));
                self.set_flag(inst, 0, c);
            }
            InstructionData::FloatCompare { args, cond, .. } => {
                let (a, b) = (self.op(args[0]), self.op(args[1]));
                let c = self.def(format!(
                    "fcmp {} {} {a}, {b}",
                    fcc(cond),
                    llty(self.ty(args[0]))
                ));
                self.set_flag(inst, 0, c);
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
                self.bases
                    .insert(dfg.first_result(inst), (base.clone(), i64::from(off)));
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
                self.bases
                    .insert(dfg.first_result(inst), (base.clone(), sym.1));
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
                if !fault_function(&name) && pure_runtime_attrs(&name).is_none() {
                    self.calls[self.at] = true;
                }
                if fault_function(&name) {
                    self.faults[self.at] = true;
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
                let exclusive = self.exclusive.get(&name).cloned().unwrap_or_default();
                self.call(inst, sigref, &format!("@\"{name}\""), &vals, &exclusive);
            }
            InstructionData::CallIndirect { args, sig_ref, .. } => {
                let vals: Vec<Value> = args.as_slice(&self.f.dfg.value_lists).to_vec();
                self.calls[self.at] = true;
                let callee = self.op(vals[0]);
                let p = self.def(format!("inttoptr i64 {callee} to ptr"));
                self.call(inst, sig_ref, &p, &vals[1..], &[]);
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
                self.returns[self.at] = true;
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
            pure_runtime_attrs(&name).unwrap_or("")
        };
        let decl = format!(
            "declare {} @\"{name}\"({}){attrs}",
            ret_ty(&sig.returns),
            sig_params(sig)
        );
        self.decls.entry(name.clone()).or_insert(decl);
        name
    }

    /// A call; the `exclusive` arguments are pointers the callee takes as `ptr noalias`.
    fn call(
        &mut self,
        inst: Inst,
        sigref: ir::SigRef,
        callee: &str,
        args: &[Value],
        exclusive: &[usize],
    ) {
        let sig = self.f.dfg.signatures[sigref].clone();
        let a: Vec<String> = args
            .iter()
            .enumerate()
            .map(|(i, v)| {
                let t = self.ty(*v);
                if exclusive.contains(&i) && t == types::I64 {
                    format!("ptr {}", self.ptr(*v, 0))
                } else {
                    format!("{}{} {}", llty(t), attr(t), self.op(*v))
                }
            })
            .collect();
        let rt = ret_ty(&sig.returns);
        // Any source call can fault, including ordinary native calls and callbacks.
        // Merging calls from distinct source sites loses the caller's fault frame.
        let rhs = format!("call {rt} {callee}({}) nomerge", a.join(", "));
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

    /// Whether `v` is the result of a multiplication or left shift.
    fn is_product(&self, v: Value) -> bool {
        let Some(def) = self.f.dfg.value_def(v).inst() else {
            return false;
        };
        matches!(self.f.dfg.insts[def].opcode(), Opcode::Imul | Opcode::Ishl)
    }

    fn binary(&mut self, inst: Inst, opc: Opcode, args: [Value; 2]) {
        let (a, b) = (self.op(args[0]), self.op(args[1]));
        // A known address plus or minus a constant stays a known address.
        let step = match opc {
            Opcode::Iadd => self
                .bases
                .get(&args[0])
                .zip(b.parse::<i64>().ok())
                .or_else(|| self.bases.get(&args[1]).zip(a.parse::<i64>().ok())),
            Opcode::Isub => self
                .bases
                .get(&args[0])
                .zip(b.parse::<i64>().ok().map(|c| -c)),
            _ => None,
        };
        if let Some(((base, at), c)) = step {
            let known = (base.clone(), at.wrapping_add(c));
            self.bases.insert(self.f.dfg.first_result(inst), known);
        }
        if opc == Opcode::Iadd && self.ty(args[0]) == types::I64 && self.is_product(args[1]) {
            let res = self.f.dfg.first_result(inst);
            self.indexed.insert(res, (args[0], args[1]));
        }
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
            Opcode::Fadd => simple("fadd"),
            Opcode::Fsub => simple("fsub"),
            Opcode::Fmul => simple("fmul"),
            Opcode::Fdiv => simple("fdiv"),
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
                self.set(inst, 0, v);
                self.set_flag(inst, 1, o);
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
                self.set(inst, 0, v);
                self.set_flag(inst, 1, o);
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
            Opcode::Fneg => format!("fneg {} {a}", llty(t)),
            Opcode::Fabs => format!("call {0} @llvm.fabs.{1}({0} {a})", llty(t), fsuf(t)),
            Opcode::Sqrt => format!("call {0} @llvm.sqrt.{1}({0} {a})", llty(t), fsuf(t)),
            Opcode::Floor => format!("call {0} @llvm.floor.{1}({0} {a})", llty(t), fsuf(t)),
            Opcode::Ceil => format!("call {0} @llvm.ceil.{1}({0} {a})", llty(t), fsuf(t)),
            Opcode::Trunc => format!("call {0} @llvm.trunc.{1}({0} {a})", llty(t), fsuf(t)),
            Opcode::Uextend => format!("zext {} {a} to {}", llty(t), llty(rt)),
            Opcode::Sextend => format!("sext {} {a} to {}", llty(t), llty(rt)),
            Opcode::Ireduce => format!("trunc {} {a} to {}", llty(t), llty(rt)),
            Opcode::Fdemote => format!("fptrunc double {a} to float"),
            Opcode::Fpromote => format!("fpext float {a} to double"),
            Opcode::FcvtFromSint => format!("sitofp {} {a} to {}", llty(t), llty(rt)),
            Opcode::FcvtToSintSat => {
                format!(
                    "call {0} @llvm.fptosi.sat.{0}.{2}({1} {a})",
                    llty(rt),
                    llty(t),
                    fsuf(t)
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
    /// Marks parameters `at` of the internal function `name` as exclusive pointers, before any
    /// function that calls it is added.
    pub fn set_exclusive(&mut self, name: &str, at: Vec<usize>) {
        self.exclusive.insert(name.to_string(), at);
    }

    /// Turns the per-CPU copies of vectorizable loops on or off (they exist for x86-64 only).
    pub fn set_per_cpu(&mut self, on: bool) {
        self.per_cpu = on;
    }

    /// Appends the definition of `f` named `name`. Returns whether the symbol became a
    /// dispatcher between per-CPU copies (`name.avx2`, `name.base`), which hold the code.
    pub fn add_function(
        &mut self,
        name: &str,
        display: &str,
        fn_loc: (u32, u32),
        f: &Function,
        syms: &dyn Symbols,
        public: bool,
    ) -> bool {
        // A function with a loop over list elements is also compiled for x86-64-v3 (AVX2, FMA),
        // where LLVM vectorizes twice as wide; on x86-64 its symbol becomes a dispatcher that
        // picks a copy by the running CPU (see `finish`).
        let (header, body, vector) = self.translate(name, name, display, fn_loc, f, syms);
        let avx2 = (vector && self.per_cpu).then(|| {
            let clone = format!("{name}{AVX2_SUFFIX}");
            let (h, b, _) = self.translate(&clone, name, display, fn_loc, f, syms);
            (h, b)
        });
        let copies = avx2.is_some();
        self.defs.push(Def {
            name: name.to_string(),
            public,
            header,
            body,
            avx2,
        });
        copies
    }

    /// The `define` header (after the linkage) and body of `f` under `name`, and whether it
    /// has a loop over list elements; `source` is the symbol the function was declared as,
    /// which keys its exclusive parameters.
    fn translate(
        &mut self,
        name: &str,
        source: &str,
        display: &str,
        fn_loc: (u32, u32),
        f: &Function,
        syms: &dyn Symbols,
    ) -> (String, String, bool) {
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
            flags: HashMap::new(),
            wide: wide_values(f),
            tmp: 0,
            incoming: HashMap::new(),
            tramps: Vec::new(),
            cur: String::new(),
            decls: &mut self.decls,
            exclusive: &self.exclusive,
            data: &mut self.data,
            dbg: Some(none_loc),
            sites: self.sites,
            bases: HashMap::new(),
            indexed: HashMap::new(),
            order: blocks.iter().enumerate().map(|(i, b)| (*b, i)).collect(),
            at: 0,
            elements: vec![false; blocks.len()],
            calls: vec![false; blocks.len()],
            back_edges: Vec::new(),
            edges: Vec::new(),
            returns: vec![false; blocks.len()],
            faults: vec![false; blocks.len()],
        };
        // Entry parameters are the function parameters; other block parameters are phis.
        let mut params = Vec::new();
        // Exclusive pointer parameters arrive as `ptr`; the body sees their integer value, and
        // addresses them through the parameter itself so the `noalias` fact reaches each access.
        let mut casts = String::new();
        let all = tr.exclusive;
        let exclusive = all.get(source).map(Vec::as_slice).unwrap_or(&[]);
        for (i, p) in f.dfg.block_params(entry).iter().enumerate() {
            let t = f.dfg.value_type(*p);
            tr.ops.insert(*p, format!("%a{i}"));
            if exclusive.contains(&i) && t == types::I64 {
                params.push(format!("ptr noalias %x{i}"));
                let _ = writeln!(casts, "  %a{i} = ptrtoint ptr %x{i} to i64");
                tr.bases.insert(*p, (format!("%x{i}"), 0));
            } else {
                params.push(format!("{}{} %a{i}", llty(t), attr(t)));
            }
        }
        for b in &blocks[1..] {
            for (i, p) in f.dfg.block_params(*b).iter().enumerate() {
                tr.ops.insert(*p, format!("%p{}_{i}", b.as_u32()));
            }
        }
        // Translate each block's instructions; phis are added once every incoming edge is known.
        let mut bodies: Vec<(Block, String)> = Vec::with_capacity(blocks.len());
        for (at, b) in blocks.iter().enumerate() {
            tr.at = at;
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
        allocas.push_str(&casts);
        // Allocas must sit in the entry block, right after its label.
        let (first, rest) = text.split_once('\n').expect("entry label");
        let header = format!(
            "{} @\"{name}\"({}) #{} !dbg !{sp} {{\n",
            ret_ty(&f.signature.returns),
            params.join(", "),
            if f.signature.returns.len() > WIDE_RETURN_LEAVES {
                2
            } else {
                0
            }
        );
        let mut body = String::new();
        body.push_str(first);
        body.push('\n');
        body.push_str(&allocas);
        body.push_str(rest);
        body.push_str("}\n\n");
        (header, body, tr.has_element_loop())
    }

    /// Glue functions at the top of a chain of glue calls three or more levels deep. They stay
    /// out of line: inlining a chain nests one loop per element-type level, which makes the
    /// optimizer quadratic in the nesting depth of a literal. Count a cycle's closing edge,
    /// then stop traversing it; direct self calls remain excluded. Shallow glue still inlines.
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
        let nonleaf: HashSet<&str> = callees
            .iter()
            .filter(|(_, cs)| cs.iter().any(|c| callees.contains_key(c)))
            .map(|(&name, _)| name)
            .collect();
        // With self edges excluded, a three-edge traversal r -> a -> b -> c only
        // requires b != r: c may close a cycle. For each a, retain two distinct b
        // choices that have an outgoing edge. Only r is forbidden, so two suffice.
        // This fixed-threshold query is linear and independent of traversal order;
        // memoizing recursive depths would retain results from another active path.
        let witnesses: HashMap<&str, [Option<&str>; 2]> = callees
            .iter()
            .map(|(&name, cs)| {
                let mut choices = cs.iter().copied().filter(|c| nonleaf.contains(c));
                let first = choices.next();
                let second = choices.find(|c| Some(*c) != first);
                (name, [first, second])
            })
            .collect();
        callees
            .iter()
            .filter(|(root, cs)| {
                cs.iter().any(|a| {
                    witnesses
                        .get(a)
                        .is_some_and(|bs| bs.iter().flatten().any(|b| b != *root))
                })
            })
            .map(|(&name, _)| name.to_string())
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
        let mut uses_level = false;
        for d in &self.defs {
            let vis = if d.public {
                ""
            } else if !anchored || pinned.contains(&d.name) {
                "hidden "
            } else {
                "internal "
            };
            if let Some((header, body)) = &d.avx2 {
                uses_level = true;
                // Where the tables address functions by symbol (COFF, Mach-O), the copies the
                // tables list need visible symbols too, as the dispatcher has.
                let copy_vis = if !anchored || pinned.contains(&d.name) {
                    "hidden "
                } else {
                    "internal "
                };
                let (dh, db) = dispatcher(&d.name, &d.header);
                let _ = write!(s, "define {vis}{dh}{db}");
                let base = d.header.replacen(
                    &format!("@\"{}\"(", d.name),
                    &format!("@\"{}{BASE_SUFFIX}\"(", d.name),
                    1,
                );
                // The copies stay out of line: inlined into the dispatcher, which has no debug
                // subprogram, their line tables are dropped and a fault loses its frames.
                let base = base.replacen(" #0 ", " #1 ", 1);
                let _ = write!(s, "define {copy_vis}{base}{}", d.body);
                let fast = header
                    .replacen(" #0 ", " #3 ", 1)
                    .replacen(" #2 ", " #3 ", 1);
                let _ = write!(s, "define {copy_vis}{fast}{body}");
                continue;
            }
            let header = if deep.contains(&d.name) {
                d.header.replacen(" #0 ", " #1 ", 1)
            } else if is_huge(&d.body) {
                d.header.replacen(" #0 ", " #4 ", 1)
            } else {
                d.header.clone()
            };
            let _ = write!(s, "define {vis}{header}{}", d.body);
        }
        // References can precede definitions. Index their borrowed names once instead of
        // scanning every definition for each call or function address in the module.
        let defined: HashSet<&str> = if self.decls.is_empty() && self.data.is_empty() {
            HashSet::new()
        } else {
            self.defs.iter().map(|d| d.name.as_str()).collect()
        };
        for (name, decl) in &self.decls {
            if !defined.contains(name.as_str()) {
                s.push_str(decl);
                s.push('\n');
            }
        }
        for name in self.data.keys() {
            if !defined.contains(name.as_str()) {
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
             declare double @llvm.floor.f64(double)\n\
             declare double @llvm.ceil.f64(double)\n\
             declare double @llvm.trunc.f64(double)\n\
             declare float @llvm.fabs.f32(float)\n\
             declare float @llvm.sqrt.f32(float)\n\
             declare float @llvm.floor.f32(float)\n\
             declare float @llvm.ceil.f32(float)\n\
             declare float @llvm.trunc.f32(float)\n\
             declare i64 @llvm.fptosi.sat.i64.f64(double)\n\
             declare i64 @llvm.fptosi.sat.i64.f32(float)\n",
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
        s.push_str("attributes #4 = { \"frame-pointer\"=\"all\" nounwind noinline optnone }\n");
        s.push_str("attributes #2 = { \"frame-pointer\"=\"all\" nounwind noimplicitfloat }\n");
        s.push_str("attributes #3 = { \"frame-pointer\"=\"all\" nounwind noinline \"target-features\"=\"+avx,+avx2,+fma,+f16c,+bmi,+bmi2\" }\n");
        if uses_level {
            s.push_str("declare i64 @msrt_cpu_level() nounwind willreturn memory(none)\n");
        }
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

    fn glue_module(edges: &[Vec<usize>]) -> LlvmModule {
        let mut module = LlvmModule::new(vec![Some("glue.ms".into())], ".".into());
        for (node, calls) in edges.iter().enumerate() {
            let name = format!("ms.glue.{node}.drop");
            let mut body = "block0:\n".to_string();
            for callee in calls {
                writeln!(body, "  call void @\"ms.glue.{callee}.drop\"()").unwrap();
            }
            body.push_str("  ret void\n}\n\n");
            module.defs.push(Def {
                header: format!("void @\"{name}\"() #0 {{\n"),
                name,
                public: false,
                body,
                avx2: None,
            });
        }
        module
    }

    fn assert_deep_glue(edges: &[&[usize]], expected: &[usize]) {
        let edges: Vec<_> = edges.iter().map(|cs| cs.to_vec()).collect();
        let expected: HashSet<_> = expected
            .iter()
            .map(|n| format!("ms.glue.{n}.drop"))
            .collect();
        assert_eq!(glue_module(&edges).deep_glue(), expected);
    }

    #[test]
    fn only_a_huge_body_skips_optimization() {
        assert!(!is_huge(&"  ret void\n".repeat(HUGE_FUNCTION_LINES)));
        assert!(is_huge(&"  ret void\n".repeat(HUGE_FUNCTION_LINES + 1)));
    }

    #[test]
    fn deep_glue_preserves_acyclic_depth_and_ignores_missing_targets() {
        // Every possible starting depth from zero through four occurs in this chain.
        assert_deep_glue(&[&[1], &[2], &[3], &[4], &[]], &[0, 1]);
        assert_deep_glue(&[&[1, 2], &[3], &[3], &[4], &[]], &[0]);
        assert_deep_glue(&[&[1], &[2], &[99], &[]], &[]);
        assert_deep_glue(&[&[1, 99], &[2], &[3], &[]], &[0]);
    }

    #[test]
    fn deep_glue_counts_cycle_closure_once_and_keeps_distinct_witnesses() {
        assert_deep_glue(&[&[0]], &[]);
        assert_deep_glue(&[&[1], &[0]], &[]);
        assert_deep_glue(&[&[1], &[2], &[0]], &[0, 1, 2]);
        assert_deep_glue(&[&[1], &[2], &[1]], &[0]);
        assert_deep_glue(&[&[1], &[2], &[1, 3], &[4], &[]], &[0, 1]);
        // Two copies of the forbidden root must not hide the other eligible witness.
        assert_deep_glue(&[&[1], &[0, 0, 2], &[3], &[]], &[0]);
        assert_deep_glue(&[&[0, 1], &[2], &[3], &[]], &[0]);
    }

    #[test]
    fn deep_glue_matches_bounded_traversal_on_every_four_node_graph() {
        fn reaches_three(
            node: usize,
            edges: &[Vec<usize>],
            active: &mut Vec<usize>,
            remaining: usize,
        ) -> bool {
            // Reaching the limit counts even when this last edge closed a cycle.
            if remaining == 0 {
                return true;
            }
            if active.contains(&node) {
                return false;
            }
            active.push(node);
            let reached = edges[node]
                .iter()
                .any(|&next| reaches_three(next, edges, active, remaining - 1));
            active.pop();
            reached
        }
        let possible: Vec<_> = (0..4)
            .flat_map(|a| (0..4).filter(move |&b| a != b).map(move |b| (a, b)))
            .collect();
        for mask in 0..(1 << possible.len()) {
            let mut edges = vec![Vec::new(); 4];
            for (bit, &(a, b)) in possible.iter().enumerate() {
                if mask & (1 << bit) != 0 {
                    edges[a].push(b);
                }
            }
            let expected: HashSet<_> = (0..4)
                .filter(|&root| reaches_three(root, &edges, &mut Vec::new(), 3))
                .map(|n| format!("ms.glue.{n}.drop"))
                .collect();
            assert_eq!(glue_module(&edges).deep_glue(), expected, "graph {mask}");
        }
    }

    #[test]
    fn deep_glue_selection_and_emission_do_not_depend_on_traversal_order() {
        let edges = vec![vec![1], vec![0, 0, 2], vec![3], vec![], vec![5], vec![4]];
        let expected = glue_module(&edges).deep_glue();
        for shift in 0..edges.len() {
            for reverse in [false, true] {
                let mut permuted = edges.clone();
                for cs in &mut permuted {
                    if !cs.is_empty() {
                        let length = cs.len();
                        cs.rotate_left(shift % length);
                    }
                    if reverse {
                        cs.reverse();
                    }
                }
                let mut module = glue_module(&permuted);
                module.defs.rotate_left(shift);
                if reverse {
                    module.defs.reverse();
                }
                assert_eq!(module.deep_glue(), expected);
            }
        }
        let module = glue_module(&edges);
        let text = module.finish("x86_64-unknown-linux-gnu", &HashSet::new(), false);
        for _ in 0..32 {
            assert_eq!(
                glue_module(&edges).finish("x86_64-unknown-linux-gnu", &HashSet::new(), false),
                text
            );
        }
        assert!(text.contains("@\"ms.glue.0.drop\"() #1"));
        assert!(text.contains("@\"ms.glue.1.drop\"() #0"));
    }

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
        // Exercise recursive and deep glue attributes through the same target verifier.
        m.defs
            .extend(glue_module(&[vec![1], vec![0, 2], vec![3], vec![4], vec![]]).defs);
        m.finish(triple, &HashSet::new(), false)
    }

    fn returning(leaves: usize) -> Function {
        let mut sig = Signature::new(CallConv::SystemV);
        sig.returns = vec![AbiParam::new(types::I64); leaves];
        let mut f = Function::with_name_signature(UserFuncName::user(0, 0), sig);
        let mut cx = FunctionBuilderContext::new();
        let mut b = FunctionBuilder::new(&mut f, &mut cx);
        let entry = b.create_block();
        b.switch_to_block(entry);
        let zero = b.ins().iconst(types::I64, 0);
        b.ins().return_(&vec![zero; leaves]);
        b.seal_all_blocks();
        b.finalize(cranelift_codegen::isa::TargetFrontendConfig {
            default_call_conv: CallConv::SystemV,
            pointer_width: target_lexicon::PointerWidth::U64,
            page_size_align_log2: 12,
        });
        f
    }

    #[test]
    fn definitions_filter_call_and_address_declarations_without_losing_externals() {
        // Calls and function addresses enter separate declaration maps, including forward
        // references. Similar external names must survive, and emission stays sorted.
        let mut m = LlvmModule::new(vec![Some("symbols.ms".into())], ".".into());
        let f = returning(1);
        for i in 0..256 {
            let name = format!("function_{i:06}");
            m.decls
                .insert(name.clone(), format!("declare i64 @\"{name}\"()"));
            m.data.insert(name.clone(), ());
            m.add_function(&name, &name, (0, 1), &f, &TestSymbols, i == 0);
        }
        for name in ["function_000256", "function_000000_external"] {
            m.decls
                .insert(name.into(), format!("declare i64 @\"{name}\"()"));
        }
        m.data.insert("function_000000_address".into(), ());
        let pinned = HashSet::from(["function_000001".into()]);
        for anchored in [false, true] {
            let text = m.finish("x86_64-unknown-linux-gnu", &pinned, anchored);
            let declarations: Vec<_> = text
                .lines()
                .filter(|l| l.starts_with("declare i64 @\""))
                .collect();
            assert_eq!(
                declarations,
                [
                    "declare i64 @\"function_000000_external\"()",
                    "declare i64 @\"function_000256\"()",
                ]
            );
            let data: Vec<_> = text.lines().filter(|l| l.starts_with("@\"")).collect();
            assert_eq!(data, ["@\"function_000000_address\" = external global i8"]);
            assert!(text.contains("define i64 @\"function_000000\""));
            assert!(text.contains("define hidden i64 @\"function_000001\""));
            let visibility = if anchored { "internal" } else { "hidden" };
            assert!(text.contains(&format!("define {visibility} i64 @\"function_000002\"")));
            assert_eq!(
                text,
                m.finish("x86_64-unknown-linux-gnu", &pinned, anchored)
            );
        }
        // A previously external reference can acquire a definition before the next finish.
        let name = "function_000256";
        m.add_function(name, name, (0, 1), &f, &TestSymbols, false);
        let text = m.finish("x86_64-unknown-linux-gnu", &pinned, false);
        assert!(!text.contains("declare i64 @\"function_000256\"()"));
        assert!(text.contains("define hidden i64 @\"function_000256\""));
    }

    /// `fn(base, i) -> f32 { load(base + i * 4) }`.
    fn element_load() -> Function {
        let mut sig = Signature::new(CallConv::SystemV);
        sig.params = vec![AbiParam::new(types::I64); 2];
        sig.returns.push(AbiParam::new(types::F32));
        let mut f = Function::with_name_signature(UserFuncName::user(0, 0), sig);
        let mut cx = FunctionBuilderContext::new();
        let mut b = FunctionBuilder::new(&mut f, &mut cx);
        let entry = b.create_block();
        b.append_block_params_for_function_params(entry);
        b.switch_to_block(entry);
        let args = b.block_params(entry).to_vec();
        let off = b.ins().imul_imm_s(args[1], 4);
        let addr = b.ins().iadd(args[0], off);
        let v = b
            .ins()
            .load(types::F32, ir::MemFlagsData::trusted(), addr, 0);
        b.ins().return_(&[v]);
        b.seal_all_blocks();
        b.finalize(cranelift_codegen::isa::TargetFrontendConfig {
            default_call_conv: CallConv::SystemV,
            pointer_width: target_lexicon::PointerWidth::U64,
            page_size_align_log2: 12,
        });
        f
    }

    /// `fn(a, b) -> i8 { if a == b { return 1 } else { return keep ? (a == b) : 0 } }`, the
    /// compare feeding a `brif` and, when `keep`, also returned as data.
    fn compare_branch(keep: bool) -> Function {
        let mut sig = Signature::new(CallConv::SystemV);
        sig.params = vec![AbiParam::new(types::I64); 2];
        sig.returns.push(AbiParam::new(types::I8));
        let mut f = Function::with_name_signature(UserFuncName::user(0, 0), sig);
        let mut cx = FunctionBuilderContext::new();
        let mut b = FunctionBuilder::new(&mut f, &mut cx);
        let (entry, yes, no) = (b.create_block(), b.create_block(), b.create_block());
        b.append_block_params_for_function_params(entry);
        b.switch_to_block(entry);
        let args = b.block_params(entry).to_vec();
        let same = b.ins().icmp(IntCC::Equal, args[0], args[1]);
        b.ins().brif(same, yes, &[], no, &[]);
        b.switch_to_block(yes);
        let one = b.ins().iconst(types::I8, 1);
        b.ins().return_(&[one]);
        b.switch_to_block(no);
        let out = if keep {
            same
        } else {
            b.ins().iconst(types::I8, 0)
        };
        b.ins().return_(&[out]);
        b.seal_all_blocks();
        b.finalize(cranelift_codegen::isa::TargetFrontendConfig {
            default_call_conv: CallConv::SystemV,
            pointer_width: target_lexicon::PointerWidth::U64,
            page_size_align_log2: 12,
        });
        f
    }

    fn compare_branch_text(keep: bool) -> String {
        let mut m = LlvmModule::new(vec![Some("cmp.ms".into())], ".".into());
        let f = compare_branch(keep);
        m.add_function("cmp", "cmp", (0, 1), &f, &TestSymbols, true);
        m.finish("x86_64-unknown-linux-gnu", &HashSet::new(), false)
    }

    #[test]
    fn a_branch_condition_stays_an_i1_and_widens_only_for_data_uses() {
        // Widening to `i8` and testing against zero again made InstCombine quadratic on a long
        // compare-and-branch chain, and an unused `zext` kept SimplifyCFG from forming a switch.
        let branch_only = compare_branch_text(false);
        assert!(!branch_only.contains("zext i1"), "{branch_only}");
        assert!(!branch_only.contains("icmp ne i8"), "{branch_only}");
        assert!(branch_only.contains("br i1 %t"), "{branch_only}");
        let also_data = compare_branch_text(true);
        assert!(also_data.contains("zext i1"), "{also_data}");
        assert!(also_data.contains("br i1 %t"), "{also_data}");
    }

    #[test]
    fn an_element_address_is_a_base_pointer_plus_an_offset() {
        let mut m = LlvmModule::new(vec![Some("elem.ms".into())], ".".into());
        let f = element_load();
        m.add_function("elem", "elem", (0, 1), &f, &TestSymbols, true);
        let text = m.finish("x86_64-unknown-linux-gnu", &HashSet::new(), false);
        // LLVM's loop analyses need the base and the scaled index apart; an `inttoptr` of the sum
        // hides the array and stops auto-vectorization of list loops.
        assert!(text.contains("= inttoptr i64 %a0 to ptr"), "{text}");
        assert!(text.contains("getelementptr i8, ptr %t"), "{text}");
        assert!(!text.contains("inttoptr i64 %t"), "{text}");
    }

    fn scalar_loop_for_cpu_classification(b: &mut FunctionBuilder<'_>, n: Value, zero: Value) {
        let header = b.create_block();
        let body = b.create_block();
        let done = b.create_block();
        b.append_block_param(header, types::I64);
        b.ins().jump(header, &[zero.into()]);
        b.switch_to_block(header);
        let i = b.block_params(header)[0];
        let more = b.ins().icmp(IntCC::SignedLessThan, i, n);
        b.ins().brif(more, body, &[], done, &[]);
        b.switch_to_block(body);
        let inc = b.ins().iadd_imm_s(i, 1);
        b.ins().jump(header, &[inc.into()]);
        b.switch_to_block(done);
    }

    fn loop_for_cpu_classification(
        elements: bool,
        calls: bool,
        early_return: bool,
        neighbors: bool,
    ) -> Function {
        let mut sig = Signature::new(CallConv::SystemV);
        sig.params = vec![AbiParam::new(types::I64); 2];
        sig.returns.push(AbiParam::new(types::I64));
        let mut f = Function::with_name_signature(UserFuncName::user(0, 0), sig);
        let sigref = f.import_signature(Signature::new(CallConv::SystemV));
        let name = f.declare_imported_user_function(ir::UserExternalName::new(0, 0));
        let callee = f.import_function(ExtFuncData {
            name: ExternalName::User(name),
            signature: sigref,
            colocated: false,
            patchable: false,
        });
        let mut cx = FunctionBuilderContext::new();
        let mut b = FunctionBuilder::new(&mut f, &mut cx);
        let entry = b.create_block();
        let header = b.create_block();
        let body = b.create_block();
        let done = b.create_block();
        b.append_block_params_for_function_params(entry);
        b.append_block_param(header, types::I64);
        b.switch_to_block(entry);
        let base = b.block_params(entry)[0];
        let n = b.block_params(entry)[1];
        let zero = b.ins().iconst(types::I64, 0);
        if neighbors {
            scalar_loop_for_cpu_classification(&mut b, n, zero);
        }
        b.ins().jump(header, &[zero.into()]);
        b.switch_to_block(header);
        let i = b.block_params(header)[0];
        let more = b.ins().icmp(IntCC::SignedLessThan, i, n);
        b.ins().brif(more, body, &[], done, &[]);
        b.switch_to_block(body);
        if elements {
            let scaled = b.ins().imul_imm_s(i, 8);
            let address = b.ins().iadd(base, scaled);
            b.ins()
                .load(types::F64, ir::MemFlagsData::trusted(), address, 0);
        }
        if calls {
            b.ins().call(callee, &[]);
        }
        if early_return {
            let stop = b.create_block();
            let next = b.create_block();
            let found = b.ins().icmp_imm_s(IntCC::Equal, i, 1);
            b.ins().brif(found, stop, &[], next, &[]);
            b.switch_to_block(stop);
            b.ins().return_(&[i]);
            b.switch_to_block(next);
        }
        let inc = b.ins().iadd_imm_s(i, 1);
        b.ins().jump(header, &[inc.into()]);
        b.switch_to_block(done);
        if neighbors {
            scalar_loop_for_cpu_classification(&mut b, n, zero);
        }
        b.ins().return_(&[n]);
        b.seal_all_blocks();
        b.finalize(cranelift_codegen::isa::TargetFrontendConfig {
            default_call_conv: CallConv::SystemV,
            pointer_width: target_lexicon::PointerWidth::U64,
            page_size_align_log2: 12,
        });
        f
    }

    #[test]
    fn cpu_copies_require_elements_no_calls_and_one_exit() {
        struct OpaqueCall;
        impl Symbols for OpaqueCall {
            fn symbol(&self, _: u32, _: u32) -> String {
                "opaque_call".into()
            }
            fn loc(&self, _: u32) -> Option<(u32, u32, u32)> {
                None
            }
            fn scope(&self, _: u32) -> Option<(String, u32, u32, u32)> {
                None
            }
        }
        for (elements, calls, early_return, copies) in [
            (false, false, false, false),
            (true, false, false, true),
            (true, true, false, false),
            (true, false, true, false),
        ] {
            for neighbors in [false, true] {
                let mut m = LlvmModule::new(vec![Some("loops.ms".into())], ".".into());
                let f = loop_for_cpu_classification(elements, calls, early_return, neighbors);
                assert_eq!(
                    m.add_function("loops", "loops", (0, 1), &f, &OpaqueCall, true),
                    copies,
                    "elements={elements}, calls={calls}, early_return={early_return}, neighbors={neighbors}"
                );
            }
        }
    }

    #[test]
    fn a_dispatcher_passes_its_parameters_to_the_copy_for_the_cpu() {
        let (head, body) = dispatcher(
            "k",
            "zeroext i8 @\"k\"(i64 %a0, ptr noalias %x1, i8 zeroext %a2) #0 !dbg !5 {\n",
        );
        assert_eq!(
            head,
            "zeroext i8 @\"k\"(i64 %a0, ptr noalias %x1, i8 zeroext %a2) #0 {\n"
        );
        assert!(body.contains("call i64 @msrt_cpu_level()"), "{body}");
        let args = "(i64 %a0, ptr %x1, i8 zeroext %a2)";
        assert!(
            body.contains(&format!("tail call zeroext i8 @\"k.avx2\"{args}")),
            "{body}"
        );
        assert!(
            body.contains(&format!("tail call zeroext i8 @\"k.base\"{args}")),
            "{body}"
        );
        let (_, void) = dispatcher("u", "void @\"u\"() #0 !dbg !6 {\n");
        assert!(
            void.contains("tail call void @\"u.avx2\"()\n  ret void"),
            "{void}"
        );
    }

    #[test]
    fn a_wide_result_skips_the_slp_vectorizer() {
        let text_for = |leaves| {
            let mut m = LlvmModule::new(vec![Some("wide.ms".into())], ".".into());
            let f = returning(leaves);
            m.add_function("wide", "wide", (0, 1), &f, &TestSymbols, true);
            m.finish("x86_64-unknown-linux-gnu", &HashSet::new(), false)
        };
        assert!(text_for(WIDE_RETURN_LEAVES + 1).contains("@\"wide\"() #2"));
        assert!(text_for(WIDE_RETURN_LEAVES).contains("@\"wide\"() #0"));
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
            // The bundled tools only carry the backend of the machine they run on.
            if !triple.starts_with(std::env::consts::ARCH) {
                continue;
            }
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
