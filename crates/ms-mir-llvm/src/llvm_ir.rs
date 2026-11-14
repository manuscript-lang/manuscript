//! The LLVM module a release build writes: the functions and glue `mir_llvm` and `glue_llvm` emit,
//! with their debug information, tables and the split into units for parallel compilation.

use std::borrow::Cow;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fmt::Write as _;

/// Resolves the source positions a function's locations refer to.
pub trait Symbols {
    /// Source `(file index, line)` behind a source-location value.
    fn loc(&self, bits: u32) -> Option<(u32, u32, u32)>;
    /// Inlined-callee scope `idx` (1-based): `(name, file, parent, call_line)`.
    fn scope(&self, idx: u32) -> Option<(String, u32, u32, u32)>;
}

/// Symbols of a function with no source: nothing resolves.
pub(crate) struct NoSymbols;

impl Symbols for NoSymbols {
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
/// and is cold, a function that only reads memory says so. None unwinds.
pub(crate) fn runtime_attrs(name: &str, reads_only: bool) -> &'static str {
    if fault_function(name) {
        " cold noreturn nounwind"
    } else if reads_only {
        READS_ONLY
    } else {
        " nounwind"
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
    /// Private constants (string literals) of directly emitted functions, by name: each unit
    /// whose text names one defines it.
    consts: BTreeMap<String, String>,
    /// The function symbols in each vtable, by its data symbol, and the vtables in definition
    /// order. The first unit defines the vtables; each other unit that names one gets an
    /// `available_externally` copy so LLVM can read its slots.
    vtables: HashMap<String, Vec<String>>,
    vtable_order: Vec<String>,
    /// Definitions of the other data objects (descriptors, globals, shared blocks), by symbol.
    /// The first unit defines them.
    data_defs: BTreeMap<String, String>,
    /// The heap functions are declared as an allocation family (`BuildOptions::heap_facts`).
    pub heap_facts: bool,
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

/// Bytes of body below which a function another unit defines is also written into a unit that
/// calls it, as an `available_externally` copy for the inliner.
const SMALL_COPY_BYTES: usize = 8000;

/// How many levels of callees of such copies are copied too.
const SMALL_COPY_DEPTH: usize = 3;

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

/// Body lines above which a function with no loop is compiled without the optimizer. Folding
/// the branches of a long run of statements leaves one basic block of thousands of
/// instructions, and instruction selection on one block is superlinear: 300 statements that
/// call a generic function (12k lines, one block after optimization) took 2.3 s in `llc`,
/// 400 took 6.5 s and 800 took 56 s, against 60 ms for the same `main` as `optnone`. Code with
/// no loop runs once per call; the largest function of the benchmark suites is 9.3k lines and
/// has loops. A workaround for LLVM's instruction selection, tracked in #3928 with its
/// removal condition.
const LOOPFREE_HUGE_FUNCTION_LINES: usize = 8_000;

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
    let lines = body.bytes().filter(|&b| b == b'\n').count();
    lines > HUGE_FUNCTION_LINES || (lines > LOOPFREE_HUGE_FUNCTION_LINES && !has_back_edge(body))
}

/// Whether some branch goes to a block that starts at or before it, which is a loop.
fn has_back_edge(body: &str) -> bool {
    let mut started: HashSet<&str> = HashSet::new();
    for line in body.lines() {
        if let Some(label) = line.strip_suffix(':').filter(|l| !l.starts_with(' ')) {
            started.insert(label);
            continue;
        }
        let line = line.trim_start();
        if !(line.starts_with("br ") || line.starts_with("switch ")) {
            continue;
        }
        let targets = line.split("label %").skip(1);
        let reaches_started = |t: &str| {
            let end = t.find([',', ' ', ']']).unwrap_or(t.len());
            started.contains(&t[..end])
        };
        if targets.into_iter().any(reaches_started) {
            return true;
        }
    }
    false
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
/// `!range` node of the case index of an enum with `n` cases, `[0, n)`, for `n` in 1 to
/// `MAX_TAG_RANGE`.
pub(crate) fn range_tag_node(n: usize) -> usize {
    assert!(
        (1..=MAX_TAG_RANGE).contains(&n),
        "no range node for {n} cases"
    );
    TBAA_BASE + 7 + n
}
/// The largest enum whose case index has a range node.
pub(crate) const MAX_TAG_RANGE: usize = 16;
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
            consts: BTreeMap::new(),
            vtables: HashMap::new(),
            vtable_order: Vec::new(),
            data_defs: BTreeMap::new(),
            heap_facts: true,
        };
        // Placeholder slots for the fixed ids and one `DIFile` per file.
        m.di.meta.resize(FIRST_FILE + nfiles, String::new());
        m
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

impl LlvmModule {
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
        for (name, def) in out.consts {
            self.consts.entry(name).or_insert(def);
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

    /// Glue functions at the top of a chain of glue calls three or more levels deep. They stay
    /// out of line: inlining a chain nests one loop per element-type level, which makes the
    /// optimizer quadratic in the nesting depth of a literal. Count a cycle's closing edge,
    /// then stop traversing it; direct self calls remain excluded. Shallow glue still inlines.
    fn deep_glue(&self) -> HashSet<String> {
        let glue_call = format!("@\"{}", crate::GLUE_PREFIX);
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
    #[cfg(test)]
    pub fn finish(&self, triple: &str, pinned: &HashSet<String>, anchored: bool) -> String {
        self.finish_units(triple, pinned, anchored, 1)
            .swap_remove(0)
            .ir
    }

    /// Defines the vtable `name` with these function symbols, slot by slot.
    pub fn define_vtable(&mut self, name: String, slots: Vec<String>) {
        self.vtable_order.push(name.clone());
        self.vtables.insert(name, slots);
    }

    /// Defines a data object; `def` is its whole `@"name" = ...` line.
    pub fn define_data(&mut self, name: String, def: String) {
        self.data_defs.insert(name, def);
    }

    /// Records that the module names the data symbol `name`, so a unit that names it declares it.
    pub fn reference_data(&mut self, name: &str) {
        self.data.insert(name.to_string(), ());
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

    /// `defs` in depth-first order along the calls in their text, starting from the exported
    /// functions and the entry, so a function is cut into a unit beside its callees and the
    /// inliner keeps what it would have inlined in one unit.
    fn by_call_order(defs: Vec<&Def>) -> Vec<&Def> {
        let index: HashMap<&str, usize> = defs
            .iter()
            .enumerate()
            .map(|(i, d)| (d.name.as_str(), i))
            .collect();
        let calls: Vec<Vec<usize>> = defs
            .iter()
            .map(|d| {
                let mut seen = HashSet::new();
                let mut out = Vec::new();
                let mut rest = d.body.as_str();
                while let Some(at) = rest.find("@\"") {
                    rest = &rest[at + 2..];
                    let Some(end) = rest.find('"') else { break };
                    if let Some(&c) = index.get(&rest[..end])
                        && seen.insert(c)
                    {
                        out.push(c);
                    }
                    rest = &rest[end..];
                }
                out
            })
            .collect();
        let mut visited = vec![false; defs.len()];
        let mut order = Vec::with_capacity(defs.len());
        let roots = (0..defs.len())
            .filter(|&i| defs[i].public)
            .chain(0..defs.len());
        for root in roots {
            let mut stack = vec![root];
            while let Some(i) = stack.pop() {
                if std::mem::replace(&mut visited[i], true) {
                    continue;
                }
                order.push(defs[i]);
                stack.extend(calls[i].iter().rev().copied());
            }
        }
        order
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
        let plain = if units > 1 {
            Self::by_call_order(plain)
        } else {
            plain
        };
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
        tail.push_str(crate::llvm_lifetimes::DECLARES);
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
        for n in 1..=MAX_TAG_RANGE {
            let _ = writeln!(tail, "!{} = !{{i64 0, i64 {n}}}", range_tag_node(n));
        }
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
        for (gi, (members, unoptimized)) in groups.iter().enumerate() {
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
            let local: HashSet<&str> = members.iter().map(|d| d.name.as_str()).collect();
            let copied = if units > 1 && !unoptimized {
                self.write_small_copies(&mut s, &local, &deep)
            } else {
                HashSet::new()
            };
            // The first unit defines the data, then the vtables.
            if gi == 0 {
                for def in self.data_defs.values() {
                    s.push_str(def);
                    s.push('\n');
                }
            }
            // References can precede definitions, and with several units point into another:
            // declare what this unit calls and does not define, found in one scan of its text.
            let mut used = referenced(&s);
            // A vtable this unit names is written with its slots; the functions they name are
            // then referenced too, so the scan below declares the ones another unit defines.
            let mut tables = String::new();
            for name in &self.vtable_order {
                let slots = &self.vtables[name];
                let list: Vec<String> = slots.iter().map(|f| format!("ptr @\"{f}\"")).collect();
                let (linkage, wanted) = if gi == 0 {
                    ("hidden", true)
                } else {
                    ("available_externally", used.contains(name))
                };
                if wanted {
                    let _ = writeln!(
                        tables,
                        "@\"{name}\" = {linkage} constant [{} x ptr] [{}], align 8",
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
                    .filter(|d| !local.contains(d.name.as_str()) && !copied.contains(&d.name))
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
                    let plain = (!self.heap_facts)
                        .then(|| crate::mir_llvm::rt::plain_heap_decl(name))
                        .flatten();
                    s.push_str(plain.unwrap_or(decl));
                    s.push('\n');
                }
            }
            for name in self.data.keys() {
                if !defined.contains(name.as_str())
                    && !self.vtables.contains_key(name)
                    && !(gi == 0 && self.data_defs.contains_key(name))
                    && (units == 1 || used.contains(name))
                {
                    let _ = writeln!(s, "@\"{name}\" = external global i8");
                }
            }
            for (name, def) in &self.consts {
                if used.contains(name) {
                    s.push_str(def);
                    s.push('\n');
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

    /// Writes `available_externally` copies of the small functions other units define that this
    /// unit's text calls, directly or through another copy, so LLVM inlines them as it would in
    /// one unit; the copies are dropped after inlining and the real definition stays in its own
    /// unit. Returns the names written.
    fn write_small_copies(
        &self,
        s: &mut String,
        local: &HashSet<&str>,
        deep: &HashSet<String>,
    ) -> HashSet<String> {
        let mut copied: HashSet<String> = HashSet::new();
        let mut wanted = referenced(s);
        for _ in 0..SMALL_COPY_DEPTH {
            let mut added = String::new();
            for d in &self.defs {
                if d.body.len() > SMALL_COPY_BYTES
                    || local.contains(d.name.as_str())
                    || copied.contains(&d.name)
                    || !wanted.contains(&d.name)
                    || deep.contains(&d.name)
                {
                    continue;
                }
                let vis = if d.public { "" } else { "hidden " };
                let _ = write!(
                    added,
                    "define available_externally {vis}{}{}",
                    d.header, d.body
                );
                copied.insert(d.name.clone());
            }
            if added.is_empty() {
                break;
            }
            wanted.extend(referenced(&added));
            s.push_str(&added);
        }
        copied
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

    /// A function with no parameters whose body is one instruction.
    fn unit_function(instruction: &str) -> crate::mir_llvm::Emitted {
        crate::mir_llvm::Emitted {
            ret: "void".into(),
            params: String::new(),
            attrs: String::new(),
            body: format!("entry:\n  {instruction}\n}}\n\n"),
            decls: Vec::new(),
            data: Vec::new(),
            consts: Vec::new(),
        }
    }

    fn glue_module(edges: &[Vec<usize>]) -> LlvmModule {
        let mut module = LlvmModule::new(vec![Some("glue.ms".into())], ".".into());
        for (node, calls) in edges.iter().enumerate() {
            let name = format!("{}{node}.drop", crate::GLUE_PREFIX);
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
    fn a_long_body_without_a_loop_skips_optimization_but_one_with_a_loop_does_not() {
        let straight = format!(
            "b0:\n{}  br label %b1\nb1:\n  ret void\n}}\n",
            "  call void @\"x\"()\n".repeat(LOOPFREE_HUGE_FUNCTION_LINES)
        );
        assert!(is_huge(&straight));
        let looping = format!(
            "b0:\n  br label %b1\nb1:\n{}  br i1 %c, label %b1, label %b2\nb2:\n  ret void\n}}\n",
            "  call void @\"x\"()\n".repeat(LOOPFREE_HUGE_FUNCTION_LINES)
        );
        assert!(!is_huge(&looping));
        let switching = format!(
            "b0:\n  br label %b1\nb1:\n{}  switch i64 %k, label %b2 [ i64 0, label %b1 ]\nb2:\n  ret void\n}}\n",
            "  call void @\"x\"()\n".repeat(LOOPFREE_HUGE_FUNCTION_LINES)
        );
        assert!(!is_huge(&switching));
        let short = "b0:\n  br label %b1\nb1:\n  ret void\n}\n";
        assert!(!is_huge(short));
    }

    #[test]
    fn only_a_huge_body_skips_optimization() {
        // A loop keeps a body below the larger bound optimized.
        let looped = |extra: usize| {
            format!(
                "b0:\n  br label %b0\n{}",
                "  ret void\n".repeat(HUGE_FUNCTION_LINES - 2 + extra)
            )
        };
        assert!(!is_huge(&looped(0)));
        assert!(is_huge(&looped(1)));
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

    /// A function whose body calls `callees`.
    fn caller(name: &str, callees: &[&str], padding: usize) -> Def {
        let mut def = plain_def(name, padding);
        let calls: String = callees
            .iter()
            .map(|c| format!("  call void @\"{c}\"()\n"))
            .collect();
        def.body = def.body.replacen("b0:\n", &format!("b0:\n{calls}"), 1);
        def
    }

    #[test]
    fn units_follow_calls_and_copy_small_callees_for_the_inliner() {
        let mut module = LlvmModule::new(vec![Some("a.ms".into())], ".".into());
        // Emission order interleaves two call chains; the cut must keep each chain together.
        module.defs.push(caller("a1", &["a2"], 100));
        module.defs.push(caller("b1", &["b2"], 100));
        module.defs.push(caller("a2", &["tiny"], 100));
        module.defs.push(caller("b2", &[], 100));
        module.defs.push(caller("tiny", &[], 2));
        module.defs[0].public = true;
        let units = module.finish_units("x86_64-unknown-linux-gnu", &HashSet::new(), false, 2);
        assert_eq!(units.len(), 2);
        let defines =
            |u: &Unit, name: &str| u.ir.contains(&format!("hidden void @\"{name}\"() #0 {{"));
        let calls_chain = &units[0];
        assert!(defines(calls_chain, "a2"), "a callee follows its caller");
        assert!(!defines(calls_chain, "b2") || !defines(&units[1], "a2"));
        // The small function is defined once and copied where another unit calls it.
        let copies = units
            .iter()
            .filter(|u| {
                u.ir.contains("define available_externally hidden void @\"tiny\"")
            })
            .count();
        let owners = units.iter().filter(|u| defines(u, "tiny")).count();
        assert_eq!(owners, 1);
        assert!(copies <= 1);
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
        let bits = HashMap::new();
        m.add_direct(
            "plain",
            "display\n}\ndefine name",
            (0, 1),
            true,
            DirectLocs {
                syms: &NoSymbols,
                bits: &bits,
            },
            |_| unit_function("ret void"),
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
}
