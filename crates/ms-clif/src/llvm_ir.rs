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
use std::borrow::Cow;
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
    /// Whether the runtime function `symbol` only reads memory: it returns, does not unwind and
    /// writes nothing, so calls to it do not clobber the caller's memory and loads of list
    /// lengths, record fields and map headers survive them. Declared `// ms: pure` on the
    /// function, which only lookups with no descriptor callbacks (that could run user code)
    /// and no fault may be.
    fn reads_only(&self, _symbol: &str) -> bool {
        false
    }
}

/// Symbols of a function with no source: nothing resolves.
pub(crate) struct NoSymbols;

impl Symbols for NoSymbols {
    fn symbol(&self, _: u32, _: u32) -> String {
        unreachable!("no source locations to resolve")
    }
    fn loc(&self, _: u32) -> Option<(u32, u32, u32)> {
        None
    }
    fn scope(&self, _: u32) -> Option<(String, u32, u32, u32)> {
        None
    }
}

/// Attributes of a call to a function that only reads memory.
/// Runtime allocators: each returns a block no other pointer reaches, so the translation declares
/// the result `noalias ptr` and keeps the pointer for the accesses that follow.
pub(crate) fn returns_fresh_block(symbol: &str) -> bool {
    matches!(symbol, "msrt_alloc" | "msrt_alloc_zeroed" | "msrt_realloc")
}

/// The function attributes of the declaration of runtime function `name`: a fault never returns
/// and is cold, a function that only reads memory says so.
pub(crate) fn runtime_attrs(name: &str, reads_only: bool) -> &'static str {
    if fault_function(name) {
        " cold noreturn"
    } else if reads_only {
        READS_ONLY
    } else {
        ""
    }
}

const READS_ONLY: &str = " nounwind willreturn nofree nosync memory(read)";

/// An LLVM module under construction.
pub struct LlvmModule {
    di: DebugInfo,
    /// Fault call sites numbered so far (unique across the module).
    sites: u32,
    /// Function definitions in emission order.
    defs: Vec<Def>,
    /// Named struct types of the directly emitted functions; every unit defines them all.
    types: crate::llvm_build::Types,
    /// `declare` lines of external functions, by symbol.
    decls: BTreeMap<String, String>,
    /// External data symbols referenced.
    data: BTreeMap<String, ()>,
    /// The function symbols in each vtable, by its data symbol. The Cranelift object defines the
    /// vtable; each unit gets an `available_externally` copy so LLVM can read its slots.
    vtables: HashMap<String, Vec<String>>,
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
    /// A glue function (drop, copy) generated on demand.
    glue: bool,
    /// `define ` is followed by the linkage, then this: return type, name, parameters, attributes.
    header: String,
    /// The entry label, the stack slots, then the rest of the body.
    body: String,
}

/// Body lines above which a function is compiled without LLVM's optimizer (`optnone`): SROA, the
/// SLP vectorizer and the code generator grow faster than linearly with one function's size, so
/// a generated function of thousands of statements took minutes, and one of 2000 loops (60k lines)
/// still took about 17 s before the `optsize` tier. Hand-written functions are far below this; a
/// function above it is run-once straight-line code in practice.
const HUGE_FUNCTION_LINES: usize = 60_000;

/// Body lines above which a function is optimized for size (`optsize`). The default pipeline's
/// loop unrolling, induction-variable simplification and GVN are superlinear in one function's
/// size: 1500 simple loops in `main` (about 42k lines) took 9 to 11 s, and 3000 took 41 s. Under
/// `optsize` the unroller and inliner stop growing the body and those inputs take about half the
/// time; the induction-variable pass stays superlinear, which `HUGE_FUNCTION_LINES` bounds.
/// Hand-written functions are far below this.
const LARGE_FUNCTION_LINES: usize = 25_000;
const _: () = assert!(LARGE_FUNCTION_LINES < HUGE_FUNCTION_LINES);

/// One LLVM module of the program.
pub struct Unit {
    /// The module's IR text.
    pub ir: String,
    /// Every function in it is `optnone`. Code generation then runs at `-O0`: the optimizing
    /// register allocator is superlinear in one function's size, and `optnone` does not make
    /// `llc -O2` skip it (8000 statements in `main` took 7.9 s, 16000 took 28 s, against 1.6 s and
    /// 3.3 s at `-O0`).
    pub unoptimized: bool,
}

/// Whether a function body is long enough to skip optimization.
fn is_huge(body: &str) -> bool {
    body.bytes().filter(|&b| b == b'\n').count() > HUGE_FUNCTION_LINES
}

/// Whether a function body is long enough to be optimized for size.
fn is_large(body: &str) -> bool {
    body.bytes().filter(|&b| b == b'\n').count() > LARGE_FUNCTION_LINES
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

/// What a function emitted straight from MIR gets from the module.
pub(crate) struct DirectEnv<'a> {
    /// The `DILocation` node of the function itself (line 0).
    pub loc: usize,
    /// Fault call sites numbered so far in the module.
    pub sites: &'a mut u32,
    /// The struct types of the module, shared by every function.
    pub types: &'a crate::llvm_build::Types,
    di: &'a mut DebugInfo,
    sp: usize,
    sp_file: u32,
    locs: DirectLocs<'a>,
}

/// How a direct function's source locations resolve: the symbol tables and the source-location
/// bits of each MIR location in the function (see `Gen::loc_bits`).
#[derive(Clone, Copy)]
pub(crate) struct DirectLocs<'a> {
    pub syms: &'a dyn Symbols,
    pub bits: &'a HashMap<ms_mir::ir::Loc, u32>,
}

impl DirectEnv<'_> {
    /// The `DILocation` node for MIR location `loc`: its source line, and the chain of inlined
    /// callees it sits in, like a translated instruction's. The function itself when unknown.
    pub fn at(&mut self, loc: ms_mir::ir::Loc) -> usize {
        self.locs
            .bits
            .get(&loc)
            .and_then(|b| self.di.location(self.locs.syms, *b, self.sp, self.sp_file))
            .unwrap_or(self.loc)
    }
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
            metadata_string(&name)
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

/// First metadata id of the TBAA nodes, above any debug-info id a program can reach.
const TBAA_BASE: usize = 1 << 30;

/// Metadata node of the access tag for a list element that is one scalar word.
pub(crate) const TBAA_SCALAR_ELEM_NODE: usize = TBAA_BASE + 3;
/// Metadata node of the access tag for a list element that is a list or string header.
pub(crate) const TBAA_HEADER_ELEM_NODE: usize = TBAA_BASE + 4;
/// `!range` node of a `Bool` byte: `[0, 2)`.
pub(crate) const RANGE_BOOL_NODE: usize = TBAA_BASE + 5;
/// `!range` node of a length: `[0, 2^63)`.
pub(crate) const RANGE_LEN_NODE: usize = TBAA_BASE + 6;
/// `!align` node of an 8-byte aligned pointer (a vtable slot).
pub(crate) const ALIGN8_NODE: usize = TBAA_BASE + 7;
/// The empty node `!noundef` and `!nonnull` point at.
pub(crate) const EMPTY_NODE: usize = 3;

/// The symbol names `text` mentions as `@"name"`.
fn referenced(text: &str) -> HashSet<String> {
    let mut names = HashSet::new();
    let mut rest = text;
    while let Some(at) = rest.find("@\"") {
        rest = &rest[at + 2..];
        let Some(end) = rest.find('"') else { break };
        names.insert(rest[..end].to_string());
        rest = &rest[end..];
    }
    names
}

/// LLVM quoted byte strings use hexadecimal escapes. Keep each metadata node on one
/// physical line, including names and paths that contain line breaks or line markers.
fn metadata_string(text: &str) -> Cow<'_, str> {
    if !text
        .bytes()
        .any(|b| b.is_ascii_control() || matches!(b, b'"' | b'\\'))
    {
        return Cow::Borrowed(text);
    }
    let mut escaped = String::with_capacity(text.len());
    for c in text.chars() {
        if c.is_ascii_control() || matches!(c, '"' | '\\') {
            let _ = write!(escaped, "\\{:02X}", c as u32);
        } else {
            escaped.push(c);
        }
    }
    Cow::Owned(escaped)
}

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
            types: crate::llvm_build::Types::default(),
            decls: BTreeMap::new(),
            data: BTreeMap::new(),
            vtables: HashMap::new(),
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

/// The extension attribute of a signature parameter or return, as Cranelift records it: runtime
/// bytes are zero-extended (`abi_param`), a user shim's narrow arguments carry their own, and
/// a user shim's narrow results carry none, because the C callee need not extend them.
fn param_attr(p: &ir::AbiParam) -> &'static str {
    match p.extension {
        ir::ArgumentExtension::Sext => " signext",
        ir::ArgumentExtension::Uext => " zeroext",
        ir::ArgumentExtension::None => "",
    }
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

/// Returned scalar leaves above which a function is marked `noimplicitfloat`. The SLP vectorizer
/// skips such functions; it spends tens of milliseconds on the thousands of `insertvalue` and
/// `phi` lines that build a large flattened result (`FileSystem.stat`) and finds nothing to pack.
const WIDE_RETURN_LEAVES: usize = 16;

fn ret_ty(rets: &[ir::AbiParam]) -> String {
    match rets {
        [] => "void".into(),
        [r] => format!(
            "{}{}",
            param_attr(r).trim_start(),
            if param_attr(r).is_empty() {
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
        .map(|p| format!("{}{}", llty(p.value_type), param_attr(p)))
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

/// Whether the access is a list element access the lowering marked in bounds
/// (`crate::lower::REGION_IN_BOUNDS`).
fn in_bounds_element(f: &Function, flags: ir::MemFlags) -> bool {
    f.dfg.mem_flags[flags]
        .alias_region()
        .is_some_and(|r| f.dfg.alias_regions[r].user_id & crate::lower::REGION_IN_BOUNDS != 0)
}

/// The scaled indexes behind element accesses tagged `crate::lower::REGION_IN_BOUNDS`.
fn elem_products(f: &Function) -> (HashSet<Value>, HashSet<Value>) {
    let mut products = HashSet::new();
    let mut addrs = HashSet::new();
    for block in f.layout.blocks() {
        for inst in f.layout.block_insts(block) {
            let (InstructionData::Load { arg, flags, .. }
            | InstructionData::Store {
                args: [_, arg],
                flags,
                ..
            }) = f.dfg.insts[inst]
            else {
                continue;
            };
            if !in_bounds_element(f, flags) {
                continue;
            }
            let Some(sum) = f.dfg.value_def(arg).inst() else {
                continue;
            };
            if let InstructionData::Binary {
                opcode: Opcode::Iadd,
                args,
            } = f.dfg.insts[sum]
            {
                let product = |v: Value| {
                    f.dfg.value_def(v).inst().is_some_and(|d| {
                        matches!(f.dfg.insts[d].opcode(), Opcode::Imul | Opcode::Ishl)
                    })
                };
                // The base is a pointer, never a product, so one product operand is the index.
                if let [a, b] = args
                    && product(a) != product(b)
                {
                    products.insert(if product(a) { a } else { b });
                    addrs.insert(arg);
                }
            }
        }
    }
    (products, addrs)
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
    /// Scaled indexes (`index * size`) of list element accesses (`crate::lower::REGION_IN_BOUNDS`):
    /// the index is below the list's length, so the product cannot wrap.
    elem_products: HashSet<Value>,
    /// Addresses (`base + scaled index`) of list element accesses: their offsets stay in bounds.
    elem_addrs: HashSet<Value>,
    /// Block parameters carried as `ptr` phis: every value flowing into them is a pointer (or
    /// null), so LLVM keeps the provenance of the block it came from.
    ptr_params: HashSet<Value>,
    /// Entry parameters addressed as memory (see `find_addr_params`).
    addr_params: HashSet<Value>,
}

impl<'a> Tr<'a> {
    /// Whether `v` is a pointer by construction: a fresh block, a stack slot or symbol address, a
    /// parameter the body addresses memory through, or such a pointer plus an offset.
    fn is_pointer(&self, v: Value, depth: u32) -> bool {
        if self.addr_params.contains(&v) {
            return true;
        }
        let Some(inst) = self.f.dfg.value_def(v).inst() else {
            return false;
        };
        match self.f.dfg.insts[inst] {
            InstructionData::StackAddr { .. } | InstructionData::UnaryGlobalValue { .. } => true,
            InstructionData::Call { func_ref, .. } => match &self.ext_func(func_ref).name {
                ExternalName::User(_) => {
                    returns_fresh_block(&self.name_of(&self.ext_func(func_ref).name))
                }
                _ => false,
            },
            InstructionData::Binary {
                opcode: Opcode::Iadd,
                args: [a, b],
            } if depth < 32 => self.is_pointer(a, depth + 1) != self.is_pointer(b, depth + 1),
            _ => false,
        }
    }

    /// Whether `v` is the constant zero, which a pointer phi takes as `null`.
    fn is_null(&self, v: Value) -> bool {
        self.f.dfg.value_def(v).inst().is_some_and(|i| {
            matches!(self.f.dfg.insts[i], InstructionData::UnaryImm { imm, .. } if imm.bits() == 0)
        })
    }

    /// Entry parameters the body addresses memory through (a load or store address, or the base
    /// of an element address): each is converted to a `ptr` once, at entry.
    fn find_addr_params(&self, exclusive: &[usize]) -> HashSet<Value> {
        let entry = self.f.layout.entry_block().expect("entry block");
        let params: HashSet<Value> = self
            .f
            .dfg
            .block_params(entry)
            .iter()
            .enumerate()
            .filter(|(i, p)| self.ty(**p) == types::I64 && !exclusive.contains(i))
            .map(|(_, p)| *p)
            .collect();
        let mut found = HashSet::new();
        for block in self.f.layout.blocks() {
            for inst in self.f.layout.block_insts(block) {
                let addr = match self.f.dfg.insts[inst] {
                    InstructionData::Load { arg, .. } => arg,
                    InstructionData::Store { args: [_, arg], .. } => arg,
                    _ => continue,
                };
                if params.contains(&addr) {
                    found.insert(addr);
                } else if let Some(sum) = self.f.dfg.value_def(addr).inst()
                    && let InstructionData::Binary {
                        opcode: Opcode::Iadd,
                        args: [a, b],
                    } = self.f.dfg.insts[sum]
                {
                    for v in [a, b] {
                        if params.contains(&v) {
                            found.insert(v);
                        }
                    }
                }
            }
        }
        found
    }

    /// The block parameters that can be `ptr` phis: those whose every incoming value is a
    /// pointer, another such parameter or zero, and at least one comes from a known pointer.
    fn find_ptr_params(&self) -> HashSet<Value> {
        let dfg = &self.f.dfg;
        let pool = &dfg.value_lists;
        let mut incoming: HashMap<Value, Vec<Value>> = HashMap::new();
        let mut flow = |bc: ir::BlockCall| {
            let params = dfg.block_params(bc.block(pool));
            for (p, a) in params.iter().zip(bc.args(pool)) {
                if let Some(a) = a.as_value() {
                    incoming.entry(*p).or_default().push(a);
                }
            }
        };
        for block in self.f.layout.blocks() {
            for inst in self.f.layout.block_insts(block) {
                match dfg.insts[inst] {
                    InstructionData::Jump { destination, .. } => flow(destination),
                    InstructionData::Brif { blocks, .. } => blocks.into_iter().for_each(&mut flow),
                    InstructionData::BranchTable { table, .. } => {
                        let jt = &dfg.jump_tables[table];
                        flow(jt.default_block());
                        jt.as_slice().iter().for_each(|bc| flow(*bc));
                    }
                    _ => {}
                }
            }
        }
        let mut cand: HashSet<Value> = incoming
            .keys()
            .copied()
            .filter(|p| self.ty(*p) == types::I64)
            .collect();
        let like = |v: Value, cand: &HashSet<Value>| {
            cand.contains(&v) || self.is_null(v) || self.is_pointer(v, 0)
        };
        loop {
            let drop: Vec<Value> = cand
                .iter()
                .copied()
                .filter(|p| !incoming[p].iter().all(|a| like(*a, &cand)))
                .collect();
            if drop.is_empty() {
                break;
            }
            for p in drop {
                cand.remove(&p);
            }
        }
        // A counter that starts at zero and adds to itself is not a pointer: keep only the
        // parameters some known pointer reaches.
        let mut anchored: HashSet<Value> = HashSet::new();
        loop {
            let grown: Vec<Value> = cand
                .iter()
                .copied()
                .filter(|p| !anchored.contains(p))
                .filter(|p| {
                    incoming[p]
                        .iter()
                        .any(|a| anchored.contains(a) || self.is_pointer(*a, 0))
                })
                .collect();
            if grown.is_empty() {
                break;
            }
            anchored.extend(grown);
        }
        anchored
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

    /// `, !tbaa !N` for an access in an alias region: LLVM then knows a scalar element store
    /// leaves the list and string header words alone, so it hoists their loads out of loops.
    fn tbaa(&self, flags: cranelift_codegen::ir::MemFlags) -> String {
        let Some(region) = self.f.dfg.mem_flags[flags].alias_region() else {
            return String::new();
        };
        match self.f.dfg.alias_regions[region].user_id & !crate::lower::REGION_IN_BOUNDS {
            crate::lower::REGION_SCALAR_ELEM => format!(", !tbaa !{TBAA_SCALAR_ELEM_NODE}"),
            crate::lower::REGION_HEADER_ELEM => format!(", !tbaa !{TBAA_HEADER_ELEM_NODE}"),
            _ => String::new(),
        }
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

    /// Whether the memory flags `mf` mark a list element access in bounds.
    fn is_elem(&self, mf: ir::MemFlags) -> bool {
        in_bounds_element(self.f, mf)
    }

    fn ptr(&mut self, v: Value, off: i32) -> String {
        self.ptr_at(v, off, false)
    }

    /// The pointer for address `v` plus `off`; `elem` marks an in-bounds list element address.
    fn ptr_at(&mut self, v: Value, off: i32, elem: bool) -> String {
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
            let flags = if elem { "inbounds nuw " } else { "" };
            self.def(format!("getelementptr {flags}i8, ptr {bp}, i64 {s}"))
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
        let params = self.f.dfg.block_params(blk);
        let args: Vec<String> = bc
            .args(pool)
            .enumerate()
            .map(|(i, a)| {
                let v = a.as_value().expect("value block arg");
                if params.get(i).is_some_and(|p| self.ptr_params.contains(p)) {
                    if self.is_null(v) {
                        "null".to_string()
                    } else {
                        self.ptr(v, 0)
                    }
                } else {
                    self.op(v)
                }
            })
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
                let elem = self.is_elem(flags);
                let p = self.ptr_at(arg, offset.into(), elem);
                let al = if self.f.dfg.mem_flags[flags].aligned() {
                    t.bytes().max(1)
                } else {
                    1
                };
                let tag = self.tbaa(flags);
                let r = self.def(format!("load {}, ptr {p}, align {al}{tag}", llty(t)));
                self.set(inst, 0, r);
            }
            InstructionData::Store {
                args,
                flags,
                offset,
                ..
            } => {
                let t = self.ty(args[0]);
                let elem = self.is_elem(flags);
                let p = self.ptr_at(args[1], offset.into(), elem);
                let v = self.op(args[0]);
                let al = if self.f.dfg.mem_flags[flags].aligned() {
                    t.bytes().max(1)
                } else {
                    1
                };
                let tag = self.tbaa(flags);
                self.line(format!("store {} {v}, ptr {p}, align {al}{tag}", llty(t)));
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
                let exclusive = self.exclusive.get(&name).cloned().unwrap_or_default();
                if returns_fresh_block(&name) {
                    // A fresh block: `noalias` tells LLVM nothing else reaches it, and keeping the
                    // pointer lets later accesses address it without an `inttoptr`. `msrt_realloc`
                    // also takes the block it replaces, which is dead after the call.
                    let args: Vec<String> = vals
                        .iter()
                        .map(|v| format!("i64 {}", self.op(*v)))
                        .collect();
                    let p = self.def(format!(
                        "call noalias align 16 ptr @\"{name}\"({}) nomerge",
                        args.join(", ")
                    ));
                    let result = self.f.dfg.first_result(inst);
                    self.bases.insert(result, (p.clone(), 0));
                    let i = self.def(format!("ptrtoint ptr {p} to i64"));
                    self.set(inst, 0, i);
                } else {
                    self.call(inst, sigref, &format!("@\"{name}\""), &vals, &exclusive);
                }
            }
            InstructionData::CallIndirect { args, sig_ref, .. } => {
                let vals: Vec<Value> = args.as_slice(&self.f.dfg.value_lists).to_vec();
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
        let attrs = runtime_attrs(&name, self.syms.reads_only(&name));
        let ret = if returns_fresh_block(&name) {
            "noalias align 16 ptr".to_string()
        } else {
            ret_ty(&sig.returns)
        };
        let decl = format!("declare {ret} @\"{name}\"({}){attrs}", sig_params(sig));
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
                    let a = sig.params.get(i).map_or(attr(t), param_attr);
                    format!("{}{} {}", llty(t), a, self.op(*v))
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
                .zip(b.parse::<i64>().ok().map(i64::wrapping_neg)),
            _ => None,
        };
        let has_step = step.is_some();
        if let Some(((base, at), c)) = step {
            let known = (base.clone(), at.wrapping_add(c));
            self.bases.insert(self.f.dfg.first_result(inst), known);
        }
        if opc == Opcode::Iadd && self.ty(args[0]) == types::I64 && !has_step {
            // A pointer plus an offset stays a pointer, so LLVM keeps the block it points into.
            let (b0, b1) = (
                self.bases.contains_key(&args[0]),
                self.bases.contains_key(&args[1]),
            );
            if b0 != b1 {
                let (base, index) = if b0 {
                    (args[0], args[1])
                } else {
                    (args[1], args[0])
                };
                let res = self.f.dfg.first_result(inst);
                let at = self.ptr(base, 0);
                let idx = self.op(index);
                let flags = if self.elem_addrs.contains(&res) {
                    "inbounds nuw "
                } else {
                    ""
                };
                let sum = self.def(format!("getelementptr {flags}i8, ptr {at}, i64 {idx}"));
                self.bases.insert(res, (sum, 0));
            }
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
            Opcode::Imul if self.elem_products.contains(&self.f.dfg.first_result(inst)) => {
                simple("mul nuw nsw")
            }
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
            Opcode::Rotl | Opcode::Rotr => {
                // LLVM funnel shifts of a value with itself reduce the count modulo the width.
                let name = if opc == Opcode::Rotl { "fshl" } else { "fshr" };
                format!("call {lt} @llvm.{name}.{lt}({lt} {a}, {lt} {a}, {lt} {b})")
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
            Opcode::Clz => format!("call {0} @llvm.ctlz.{0}({0} {a}, i1 false)", llty(t)),
            Opcode::Ctz => format!("call {0} @llvm.cttz.{0}({0} {a}, i1 false)", llty(t)),
            Opcode::Popcnt => format!("call {0} @llvm.ctpop.{0}({0} {a})", llty(t)),
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

    /// Appends the definition of `f` named `name`.
    pub fn add_function(
        &mut self,
        name: &str,
        display: &str,
        fn_loc: (u32, u32),
        f: &Function,
        syms: &dyn Symbols,
        public: bool,
    ) {
        let (header, body) = self.translate(name, name, display, fn_loc, f, syms);
        self.defs.push(Def {
            name: name.to_string(),
            public,
            glue: false,
            header,
            body,
        });
    }

    /// Adds a function emitted straight from MIR (see `mir_llvm`). `emit` receives the id of the
    /// function's `DILocation` node, which every call it writes must carry, and returns the
    /// finished text. The function gets its own subprogram like a translated one.
    pub(crate) fn add_direct(
        &mut self,
        name: &str,
        display: &str,
        fn_loc: (u32, u32),
        public: bool,
        locs: DirectLocs,
        emit: impl FnOnce(&mut DirectEnv) -> crate::mir_llvm::Emitted,
    ) {
        let (sp_file, sp_line) = fn_loc;
        let sp = self.di.meta.len();
        let file_node = self.di.file_node(sp_file);
        self.di.meta.push(format!(
            "distinct !DISubprogram(name: \"{}\", linkageName: \"{}\", scope: !{file_node}, file: !{file_node}, line: {sp_line}, type: !4, scopeLine: {sp_line}, spFlags: DISPFlagDefinition, unit: !0)",
            metadata_string(display),
            metadata_string(name)
        ));
        let loc = self.di.push(format!("!DILocation(line: 0, scope: !{sp})"));
        let mut env = DirectEnv {
            loc,
            sites: &mut self.sites,
            types: &self.types,
            di: &mut self.di,
            sp,
            sp_file,
            locs,
        };
        let out = emit(&mut env);
        for (callee, decl) in out.decls {
            self.decls.entry(callee).or_insert(decl);
        }
        for sym in out.data {
            self.data.insert(sym, ());
        }
        self.defs.push(Def {
            name: name.to_string(),
            public,
            glue: false,
            header: format!(
                "{} @\"{name}\"({}) #0{} !dbg !{sp} {{\n",
                out.ret, out.params, out.attrs
            ),
            body: out.body,
        });
    }

    /// Marks the function just added as glue.
    pub fn mark_glue(&mut self) {
        if let Some(d) = self.defs.last_mut() {
            d.glue = true;
        }
    }

    /// The `define` header (after the linkage) and body of `f` under `name`; `source` is the
    /// symbol the function was declared as, which keys its exclusive parameters.
    fn translate(
        &mut self,
        name: &str,
        source: &str,
        display: &str,
        fn_loc: (u32, u32),
        f: &Function,
        syms: &dyn Symbols,
    ) -> (String, String) {
        let blocks: Vec<Block> = f.layout.blocks().collect();
        let entry = blocks[0];
        // Debug info: a subprogram per function and one location node per (file, line, scope).
        let (sp_file, sp_line) = fn_loc;
        let sp = self.di.meta.len();
        let file_node = self.di.file_node(sp_file);
        self.di.meta.push(format!(
            "distinct !DISubprogram(name: \"{}\", linkageName: \"{}\", scope: !{file_node}, file: !{file_node}, line: {sp_line}, type: !4, scopeLine: {sp_line}, spFlags: DISPFlagDefinition, unit: !0)",
            metadata_string(display),
            metadata_string(name)
        ));
        let none_loc = self.di.push(format!("!DILocation(line: 0, scope: !{sp})"));
        let (elem_products, elem_addrs) = elem_products(f);
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
            elem_products,
            elem_addrs,
            ptr_params: HashSet::new(),
            addr_params: HashSet::new(),
        };
        // Entry parameters are the function parameters; other block parameters are phis.
        let mut params = Vec::new();
        // Exclusive pointer parameters arrive as `ptr`; the body sees their integer value, and
        // addresses them through the parameter itself so the `noalias` fact reaches each access.
        let mut casts = String::new();
        let all = tr.exclusive;
        let exclusive = all.get(source).map(Vec::as_slice).unwrap_or(&[]);
        tr.addr_params = tr.find_addr_params(exclusive);
        tr.ptr_params = tr.find_ptr_params();
        for (i, p) in f.dfg.block_params(entry).iter().enumerate() {
            let t = f.dfg.value_type(*p);
            tr.ops.insert(*p, format!("%a{i}"));
            if exclusive.contains(&i) && t == types::I64 {
                params.push(format!("ptr noalias %x{i}"));
                let _ = writeln!(casts, "  %a{i} = ptrtoint ptr %x{i} to i64");
                tr.bases.insert(*p, (format!("%x{i}"), 0));
            } else {
                params.push(format!("{}{} %a{i}", llty(t), attr(t)));
                if tr.addr_params.contains(p) {
                    // One conversion for every access, so LLVM sees a single base pointer.
                    let _ = writeln!(casts, "  %x{i} = inttoptr i64 %a{i} to ptr");
                    tr.bases.insert(*p, (format!("%x{i}"), 0));
                }
            }
        }
        for b in &blocks[1..] {
            for (i, p) in f.dfg.block_params(*b).iter().enumerate() {
                let name = format!("%p{}_{i}", b.as_u32());
                if tr.ptr_params.contains(p) {
                    tr.ops.insert(*p, format!("{name}.i"));
                    tr.bases.insert(*p, (name, 0));
                } else {
                    tr.ops.insert(*p, name);
                }
            }
        }
        // Translate each block's instructions; phis are added once every incoming edge is known.
        let mut bodies: Vec<(Block, String)> = Vec::with_capacity(blocks.len());
        for b in blocks.iter() {
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
                let mut casts_after = String::new();
                for (i, p) in f.dfg.block_params(*b).iter().enumerate() {
                    let is_ptr = tr.ptr_params.contains(p);
                    let t = if is_ptr {
                        "ptr"
                    } else {
                        llty(f.dfg.value_type(*p))
                    };
                    let ins: Vec<String> = edges
                        .iter()
                        .map(|e| format!("[ {}, %{} ]", e.args[i], e.from))
                        .collect();
                    let _ = writeln!(text, "  %p{}_{i} = phi {t} {}", b.as_u32(), ins.join(", "));
                    if is_ptr {
                        let _ = writeln!(
                            casts_after,
                            "  %p{0}_{i}.i = ptrtoint ptr %p{0}_{i} to i64",
                            b.as_u32()
                        );
                    }
                }
                text.push_str(&casts_after);
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
        (header, body)
    }

    /// Glue functions at the top of a chain of glue calls three or more levels deep. They stay
    /// out of line: inlining a chain nests one loop per element-type level, which makes the
    /// optimizer quadratic in the nesting depth of a literal. Count a cycle's closing edge,
    /// then stop traversing it; direct self calls remain excluded. Shallow glue still inlines.
    fn deep_glue(&self) -> HashSet<String> {
        let glue_call = format!("@\"{}", crate::cg::GLUE_PREFIX);
        let callees: HashMap<&str, Vec<&str>> = self
            .defs
            .iter()
            .filter(|d| d.glue)
            .map(|d| {
                let calls = d
                    .body
                    .match_indices(glue_call.as_str())
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
        self.finish_units(triple, pinned, anchored, 1)
            .swap_remove(0)
            .ir
    }

    /// Records the function symbols in the vtable `name`, slot by slot.
    pub fn set_vtable(&mut self, name: String, slots: Vec<String>) {
        self.vtables.insert(name, slots);
    }

    /// Whether `d` is written `optnone` (see [`HUGE_FUNCTION_LINES`]).
    fn is_unoptimized(&self, d: &Def, deep: &HashSet<String>) -> bool {
        !deep.contains(&d.name) && is_huge(&d.body)
    }

    /// Whether some function is compiled without optimization, which gets a unit of its own.
    pub fn has_unoptimized(&self) -> bool {
        let deep = self.deep_glue();
        self.defs.iter().any(|d| self.is_unoptimized(d, &deep))
    }

    /// What `d` adds to its unit's size when the functions are cut into units.
    fn weight(d: &Def) -> usize {
        d.body.len()
    }

    /// Total bytes of function text, which decides how many units a module is worth.
    pub fn code_bytes(&self) -> usize {
        self.defs.iter().map(|d| d.body.len()).sum()
    }

    /// The module as `units` texts of about equal size, each a complete module: the functions
    /// are cut into consecutive runs, and a function another unit defines is only declared. With
    /// more than one unit every function keeps a symbol (`anchored` is ignored), because the
    /// units are compiled to separate objects and link together.
    pub fn finish_units(
        &self,
        triple: &str,
        pinned: &HashSet<String>,
        anchored: bool,
        units: usize,
    ) -> Vec<Unit> {
        let deep = self.deep_glue();
        // Functions compiled without optimization go to a unit of their own, which `llc` runs at
        // `-O0` (see `Unit::unoptimized`); the rest are cut into `units` of similar size.
        let (plain, bare): (Vec<&Def>, Vec<&Def>) = self
            .defs
            .iter()
            .partition(|d| !self.is_unoptimized(d, &deep));
        let units = units.clamp(1, plain.len().max(1));
        let mut groups: Vec<(Vec<&Def>, bool)> = Vec::new();
        let total: usize = plain.iter().map(|d| Self::weight(d)).sum();
        let mut seen = 0usize;
        for d in plain {
            if groups.is_empty() || (units > 1 && seen * units >= total * groups.len()) {
                groups.push((Vec::new(), false));
            }
            seen += Self::weight(d);
            groups.last_mut().expect("group").0.push(d);
        }
        if !bare.is_empty() {
            groups.push((bare, true));
        }
        if groups.is_empty() {
            groups.push((Vec::new(), false));
        }
        let units = groups.len();
        let anchored = anchored && units == 1;
        let mut tail = String::new();
        tail.push_str(
            "declare void @llvm.trap() cold noreturn nounwind\n\
             declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)\n\
             declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1)\n\
             declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)\n\
             declare ptr @llvm.frameaddress.p0(i32)\n\
             declare ptr @llvm.ptrmask.p0.i64(ptr, i64) nounwind speculatable willreturn memory(none)\n\
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
             declare i64 @llvm.fptosi.sat.i64.f32(float)\n\
             declare i64 @llvm.fshl.i64(i64, i64, i64)\n\
             declare i64 @llvm.fshr.i64(i64, i64, i64)\n\
             declare i64 @llvm.ctlz.i64(i64, i1)\n\
             declare i64 @llvm.cttz.i64(i64, i1)\n\
             declare i64 @llvm.ctpop.i64(i64)\n",
        );
        for op in ["sadd", "ssub", "smul", "uadd", "usub", "umul"] {
            for t in ["i64", "i32", "i8"] {
                let _ = writeln!(
                    tail,
                    "declare {{ {t}, i1 }} @llvm.{op}.with.overflow.{t}({t}, {t})"
                );
            }
        }
        tail.push_str("attributes #0 = { \"frame-pointer\"=\"all\" nounwind }\n");
        tail.push_str("attributes #1 = { \"frame-pointer\"=\"all\" nounwind noinline }\n");
        tail.push_str("attributes #4 = { \"frame-pointer\"=\"all\" nounwind noinline optnone }\n");
        tail.push_str("attributes #5 = { \"frame-pointer\"=\"all\" nounwind optsize }\n");
        tail.push_str("attributes #2 = { \"frame-pointer\"=\"all\" nounwind noimplicitfloat }\n");
        // Debug metadata: line tables only (no variables, types or inline frames).
        let first_file = self.di.files.iter().position(Option::is_some).unwrap_or(0);
        tail.push_str("!llvm.dbg.cu = !{!0}\n!llvm.module.flags = !{!1, !2}\n");
        let _ = writeln!(
            tail,
            "!0 = distinct !DICompileUnit(language: DW_LANG_C99, file: !{}, producer: \"Manuscript\", isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly)",
            FIRST_FILE + first_file
        );
        tail.push_str("!1 = !{i32 2, !\"Debug Info Version\", i32 3}\n");
        tail.push_str("!2 = !{i32 7, !\"Dwarf Version\", i32 4}\n");
        tail.push_str("!3 = !{}\n!4 = !DISubroutineType(types: !3)\n");
        let _ = write!(
            tail,
            "!{b} = !{{!\"ms.tbaa\"}}\n!{s} = !{{!\"ms.scalar-elem\", !{b}, i64 0}}\n!{h} = !{{!\"ms.header-elem\", !{b}, i64 0}}\n!{ts} = !{{!{s}, !{s}, i64 0}}\n!{th} = !{{!{h}, !{h}, i64 0}}\n",
            b = TBAA_BASE,
            s = TBAA_BASE + 1,
            h = TBAA_BASE + 2,
            ts = TBAA_SCALAR_ELEM_NODE,
            th = TBAA_HEADER_ELEM_NODE
        );
        let _ = write!(
            tail,
            "!{RANGE_BOOL_NODE} = !{{i8 0, i8 2}}\n!{RANGE_LEN_NODE} = !{{i64 0, i64 -9223372036854775808}}\n!{ALIGN8_NODE} = !{{i64 8}}\n"
        );
        for (i, f) in self.di.files.iter().enumerate() {
            let name = f.as_deref().unwrap_or("<unknown>");
            let _ = writeln!(
                tail,
                "!{} = !DIFile(filename: \"{}\", directory: \"{}\")",
                FIRST_FILE + i,
                metadata_string(name),
                metadata_string(&self.di.cwd)
            );
        }
        for (i, n) in self
            .di
            .meta
            .iter()
            .enumerate()
            .skip(FIRST_FILE + self.di.files.len())
        {
            let _ = writeln!(tail, "!{i} = {n}");
        }
        let mut out = Vec::with_capacity(units);
        for (members, unoptimized) in &groups {
            let mut s = String::new();
            let _ = writeln!(s, "target triple = \"{triple}\"");
            // Struct bodies come before any use: a `getelementptr` on a type not yet defined
            // is rejected as unsized.
            s.push_str(&self.types.definitions());
            if anchored {
                let _ = writeln!(
                    s,
                    "define void @\"{TEXT_ANCHOR}\"() #0 {{\n  ret void\n}}\n"
                );
            }
            for d in members {
                self.write_def(&mut s, d, &deep, anchored, pinned);
            }
            // References can precede definitions, and with several units point into another:
            // declare what this unit calls and does not define, found in one scan of its text.
            let local: HashSet<&str> = members.iter().map(|d| d.name.as_str()).collect();
            let mut used = referenced(&s);
            // A vtable this unit names is written with its slots; the functions they name are
            // then referenced too, so the scan below declares the ones another unit defines.
            let mut tables = String::new();
            for name in self.data.keys() {
                if let Some(slots) = self.vtables.get(name)
                    && (units == 1 || used.contains(name))
                {
                    let list: Vec<String> = slots.iter().map(|f| format!("ptr @\"{f}\"")).collect();
                    let _ = writeln!(
                        tables,
                        "@\"{name}\" = available_externally constant [{} x ptr] [{}], align 8",
                        slots.len(),
                        list.join(", ")
                    );
                }
            }
            s.push_str(&tables);
            used.extend(referenced(&tables));
            if units > 1 {
                for d in self
                    .defs
                    .iter()
                    .filter(|d| !local.contains(d.name.as_str()))
                {
                    if used.contains(&d.name)
                        && let Some(at) = d.header.find(" #")
                    {
                        let _ = writeln!(s, "declare {}", &d.header[..at]);
                    }
                }
            }
            let defined: HashSet<&str> = if units > 1 {
                self.defs.iter().map(|d| d.name.as_str()).collect()
            } else {
                local
            };
            for (name, decl) in &self.decls {
                if !defined.contains(name.as_str()) && (units == 1 || used.contains(name)) {
                    s.push_str(decl);
                    s.push('\n');
                }
            }
            for name in self.data.keys() {
                if !defined.contains(name.as_str())
                    && !self.vtables.contains_key(name)
                    && (units == 1 || used.contains(name))
                {
                    let _ = writeln!(s, "@\"{name}\" = external global i8");
                }
            }
            s.push_str(&tail);
            out.push(Unit {
                ir: s,
                unoptimized: *unoptimized,
            });
        }
        out
    }

    /// Writes `d` as a definition.
    fn write_def(
        &self,
        s: &mut String,
        d: &Def,
        deep: &HashSet<String>,
        anchored: bool,
        pinned: &HashSet<String>,
    ) {
        let vis = if d.public {
            ""
        } else if !anchored || pinned.contains(&d.name) {
            "hidden "
        } else {
            "internal "
        };
        let header = if deep.contains(&d.name) {
            d.header.replacen(" #0 ", " #1 ", 1)
        } else if is_huge(&d.body) {
            d.header.replacen(" #0 ", " #4 ", 1)
        } else if is_large(&d.body) {
            d.header.replacen(" #0 ", " #5 ", 1)
        } else {
            d.header.clone()
        };
        let _ = write!(s, "define {vis}{header}{}", d.body);
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
            let name = format!("{}{node}.drop", crate::cg::GLUE_PREFIX);
            let mut body = "block0:\n".to_string();
            for callee in calls {
                writeln!(body, "  call void @\"ms.glue.{callee}.drop\"()").unwrap();
            }
            body.push_str("  ret void\n}\n\n");
            module.defs.push(Def {
                header: format!("void @\"{name}\"() #0 {{\n"),
                name,
                public: false,
                glue: true,
                body,
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

    fn plain_def(name: &str, lines: usize) -> Def {
        Def {
            header: format!("void @\"{name}\"() #0 {{\n"),
            name: name.to_string(),
            public: false,
            glue: false,
            body: format!(
                "b0:\n{}  ret void\n}}\n\n",
                "  call void @\"x\"()\n".repeat(lines)
            ),
        }
    }

    #[test]
    fn huge_functions_form_one_unoptimized_unit_of_their_own() {
        let mut module = LlvmModule::new(vec![Some("a.ms".into())], ".".into());
        module.defs.push(plain_def("small_a", 10));
        module.defs.push(plain_def("huge", HUGE_FUNCTION_LINES + 1));
        module.defs.push(plain_def("small_b", 10));
        assert!(module.has_unoptimized());
        let units = module.finish_units("x86_64-unknown-linux-gnu", &HashSet::new(), true, 1);
        let flags: Vec<bool> = units.iter().map(|u| u.unoptimized).collect();
        assert_eq!(flags, [false, true]);
        let defines =
            |u: &Unit, name: &str| u.ir.contains(&format!("define hidden void @\"{name}\""));
        assert!(defines(&units[0], "small_a") && defines(&units[0], "small_b"));
        assert!(!units[0].ir.contains("define hidden void @\"huge\""));
        assert!(defines(&units[1], "huge"));
        // The huge function's neighbours are declared where they are only called.
        assert!(!units[1].ir.contains("optnone") || units[1].ir.contains("#4"));
    }

    #[test]
    fn a_module_without_huge_functions_stays_one_optimized_unit() {
        let mut module = LlvmModule::new(vec![Some("a.ms".into())], ".".into());
        module.defs.push(plain_def("small", 10));
        assert!(!module.has_unoptimized());
        let units = module.finish_units("x86_64-unknown-linux-gnu", &HashSet::new(), true, 1);
        assert_eq!(units.len(), 1);
        assert!(!units[0].unoptimized);
    }

    #[test]
    fn a_large_body_is_optimized_for_size() {
        assert!(!is_large(&"  ret void\n".repeat(LARGE_FUNCTION_LINES)));
        assert!(is_large(&"  ret void\n".repeat(LARGE_FUNCTION_LINES + 1)));
    }

    #[test]
    fn metadata_strings_preserve_unicode_and_escape_quoted_control_bytes() {
        assert_eq!(metadata_string("plain/雪.ms"), "plain/雪.ms");
        assert_eq!(
            metadata_string("quote\"slash\\tab\tline\nreturn\r\0\u{7f}雪"),
            "quote\\22slash\\5Ctab\\09line\\0Areturn\\0D\\00\\7F雪"
        );
    }

    #[test]
    fn metadata_line_markers_stay_inside_their_quoted_fields() {
        struct Inlined;
        impl Symbols for Inlined {
            fn symbol(&self, _: u32, _: u32) -> String {
                unreachable!()
            }
            fn loc(&self, _: u32) -> Option<(u32, u32, u32)> {
                None
            }
            fn scope(&self, _: u32) -> Option<(String, u32, u32, u32)> {
                Some(("inline\n}\ndefine scope".into(), 0, 0, 1))
            }
        }
        let mut m = LlvmModule::new(
            vec![Some("part\n}\ndefine file.ms".into())],
            "dir\r\n}\ndefine cwd".into(),
        );
        m.add_function(
            "plain",
            "display\n}\ndefine name",
            (0, 1),
            &returning(1),
            &TestSymbols,
            true,
        );
        m.di.scope_sp(&Inlined, 1, FIRST_FILE + 1);
        let text = m.finish("x86_64-unknown-linux-gnu", &HashSet::new(), false);
        assert_eq!(text.lines().filter(|l| l.starts_with("define ")).count(), 1);
        assert_eq!(text.lines().filter(|l| *l == "}").count(), 1);
        for quoted in [
            "part\\0A}\\0Adefine file.ms",
            "dir\\0D\\0A}\\0Adefine cwd",
            "display\\0A}\\0Adefine name",
            "inline\\0A}\\0Adefine scope",
        ] {
            assert!(text.contains(quoted), "missing {quoted}: {text}");
        }
    }

    #[test]
    fn quoted_metadata_survives_llvm_and_fault_table_reconstruction() {
        struct Inlined;
        const INLINE: &str = "inline\"\\雪\n}\ndefine scope";
        impl Symbols for Inlined {
            fn symbol(&self, _: u32, _: u32) -> String {
                unreachable!()
            }
            fn loc(&self, bits: u32) -> Option<(u32, u32, u32)> {
                (bits == 0).then_some((0, 7, 1))
            }
            fn scope(&self, idx: u32) -> Option<(String, u32, u32, u32)> {
                (idx == 1).then(|| (INLINE.into(), 0, 0, 3))
            }
        }
        let mut sig = Signature::new(CallConv::SystemV);
        sig.params.push(AbiParam::new(types::I64));
        sig.returns.push(AbiParam::new(types::I64));
        let mut f = Function::with_name_signature(UserFuncName::user(0, 0), sig);
        let mut context = FunctionBuilderContext::new();
        let mut b = FunctionBuilder::new(&mut f, &mut context);
        let entry = b.create_block();
        b.append_block_params_for_function_params(entry);
        b.switch_to_block(entry);
        b.set_srcloc(ir::SourceLoc::new(0));
        let arg = b.block_params(entry)[0];
        let next = b.ins().iadd_imm_s(arg, 1);
        b.ins().return_(&[next]);
        b.seal_all_blocks();
        b.finalize(cranelift_codegen::isa::TargetFrontendConfig {
            default_call_conv: CallConv::SystemV,
            pointer_width: target_lexicon::PointerWidth::U64,
            page_size_align_log2: 12,
        });
        let file = "/source/雪\nquote\".ms".to_string();
        let display = "display\"\\雪\n}\ndefine name";
        let mut m = LlvmModule::new(vec![Some(file.clone())], "dir\r\n}\ndefine cwd".into());
        m.add_function("metadata", display, (0, 1), &f, &Inlined, true);
        let triple = format!("{}-unknown-linux-gnu", std::env::consts::ARCH);
        let unit = Unit {
            ir: m.finish(&triple, &HashSet::new(), false),
            unoptimized: false,
        };
        let object = crate::llvm_obj::compile_all(
            std::slice::from_ref(&unit),
            "3",
            &crate::BuildOptions::default(),
        )
        .unwrap()
        .remove(0);
        let funcs = [crate::cg::LlvmFn {
            id: cranelift_module::FuncId::from_u32(0),
            symbol: "metadata".into(),
            name: display.into(),
            file: 0,
            line: 1,
        }];
        let tables = crate::llvm_tables::read(object.path(), &funcs, &[file], false).unwrap();
        assert!(
            tables
                .scopes
                .iter()
                .any(|s| s.name == INLINE && s.call_line == 3),
            "inlined name or call line lost: {:?}",
            tables.scopes
        );
        // Line-table-only DWARF may omit the abstract origin's declaration file. The
        // instruction row still has to recover the exact source path and line.
        assert!(tables.dbg[0].ranges.iter().any(|r| r.1 == 0 && r.2 == 7));
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
        element_load_flags(None)
    }

    /// `element_load`, its access tagged as an in-bounds list element of region `tagged`.
    fn element_load_flags(tagged: Option<u32>) -> Function {
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
        let mut flags = ir::MemFlagsData::trusted();
        if let Some(user_id) = tagged {
            let region = b.func.dfg.alias_regions.insert(ir::AliasRegionData {
                user_id,
                description: "list element".into(),
            });
            flags.set_alias_region(Some(region));
        }
        let v = b.ins().load(types::F32, flags, addr, 0);
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
        // The parameter is converted once at entry and each access offsets that pointer.
        assert!(text.contains("%x0 = inttoptr i64 %a0 to ptr"), "{text}");
        assert!(text.contains("getelementptr i8, ptr %x0, i64 %t"), "{text}");
        assert!(!text.contains("inttoptr i64 %t"), "{text}");
    }

    #[test]
    fn a_tagged_element_access_is_in_bounds_and_cannot_wrap() {
        use crate::lower::{REGION_HEADER_ELEM, REGION_IN_BOUNDS, REGION_SCALAR_ELEM};
        let mut m = LlvmModule::new(vec![Some("elem.ms".into())], ".".into());
        let f = element_load_flags(Some(REGION_SCALAR_ELEM | REGION_IN_BOUNDS));
        m.add_function("elem", "elem", (0, 1), &f, &TestSymbols, true);
        let text = m.finish("x86_64-unknown-linux-gnu", &HashSet::new(), false);
        assert!(text.contains("= mul nuw nsw i64 %a1, 4"), "{text}");
        assert!(
            text.contains(&format!(", !tbaa !{}", TBAA_BASE + 3)),
            "{text}"
        );
        let mut m = LlvmModule::new(vec![Some("elem.ms".into())], ".".into());
        let f = element_load_flags(Some(REGION_HEADER_ELEM | REGION_IN_BOUNDS));
        m.add_function("elem", "elem", (0, 1), &f, &TestSymbols, true);
        let text = m.finish("x86_64-unknown-linux-gnu", &HashSet::new(), false);
        assert!(
            text.contains(&format!(", !tbaa !{}", TBAA_BASE + 4)),
            "{text}"
        );
        assert!(
            text.contains("getelementptr inbounds nuw i8, ptr %x0, i64 %t"),
            "{text}"
        );
        // An untagged address keeps plain wrapping arithmetic.
        let mut m = LlvmModule::new(vec![Some("elem.ms".into())], ".".into());
        m.add_function("elem", "elem", (0, 1), &element_load(), &TestSymbols, true);
        let text = m.finish("x86_64-unknown-linux-gnu", &HashSet::new(), false);
        assert!(!text.contains("nuw") && !text.contains("!tbaa"), "{text}");
    }

    #[test]
    fn subtraction_tracks_minimum_integer_offsets_without_overflow() {
        for offset in [i64::MIN, i64::MIN + 1, -1, 0, 1, i64::MAX] {
            for exclusive in [false, true] {
                let mut sig = Signature::new(CallConv::SystemV);
                sig.params.push(AbiParam::new(types::I64));
                sig.returns.push(AbiParam::new(types::I64));
                let mut f = Function::with_name_signature(UserFuncName::user(0, 0), sig);
                let mut cx = FunctionBuilderContext::new();
                let mut b = FunctionBuilder::new(&mut f, &mut cx);
                let entry = b.create_block();
                b.append_block_params_for_function_params(entry);
                b.switch_to_block(entry);
                let base = b.block_params(entry)[0];
                let delta = b.ins().iconst(types::I64, offset);
                let first = b.ins().isub(base, delta);
                let back = b.ins().iadd(first, delta);
                let result = if exclusive {
                    b.ins()
                        .load(types::I64, ir::MemFlagsData::trusted(), back, 0)
                } else {
                    back
                };
                b.ins().return_(&[result]);
                b.seal_all_blocks();
                b.finalize(cranelift_codegen::isa::TargetFrontendConfig {
                    default_call_conv: CallConv::SystemV,
                    pointer_width: target_lexicon::PointerWidth::U64,
                    page_size_align_log2: 12,
                });
                let mut m = LlvmModule::new(vec![Some("offset.ms".into())], ".".into());
                if exclusive {
                    m.set_exclusive("offset", vec![0]);
                }
                m.add_function("offset", "offset", (0, 1), &f, &TestSymbols, true);
                let text = m.finish("x86_64-unknown-linux-gnu", &HashSet::new(), false);
                assert!(text.contains(&format!("sub i64 %a0, {offset}")), "{text}");
                if exclusive {
                    // Subtracting then adding the same offset returns to the original
                    // address, including MIN where negating the delta must wrap.
                    assert!(text.contains("load i64, ptr %x0"), "{text}");
                }
            }
        }
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
        let Some(tools) = crate::link::llvm_tools(&crate::BuildOptions::default()).unwrap() else {
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
