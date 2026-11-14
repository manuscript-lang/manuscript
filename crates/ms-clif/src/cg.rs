//! Module-level code generation state: function declarations, runtime imports,
//! static data, and the glue functions (drop, copy) generated on demand.

use crate::layout::{Layouts, Leaf};
use crate::lower::Lower;
use crate::{Error, Options};
use cranelift_codegen::Context;
use cranelift_codegen::ir::{self, AbiParam, Signature, UserFuncName, types};
use ms_mir::types::Native;

/// A parameter or return of type `ty`. Bytes are zero-extended to a full register: the
/// runtime is compiled by rustc, which assumes `u8` and `bool` arguments arrive extended.
fn abi_param(ty: ir::Type) -> AbiParam {
    let p = AbiParam::new(ty);
    if ty == types::I8 { p.uext() } else { p }
}
use cranelift_codegen::settings::{self, Configurable};
use cranelift_frontend::FunctionBuilderContext;
use cranelift_module::{
    DataDescription, DataId, FuncId, Linkage, Module as _, default_libcall_names,
};
use cranelift_object::{ObjectBuilder, ObjectModule};
use ms_mir::ir::{ExtId, Func, Module};
use ms_mir::types::{Ty, TyKind};
use std::collections::HashMap;

/// Offset of `code` in a closure object.
/// The name prefix of generated glue functions, followed by a serial and the kind.
pub(crate) const GLUE_PREFIX: &str = "ms.glue.";

pub const CLOSURE_CODE: i32 = ms_rt_abi::CLOSURE_CODE_OFFSET as i32;
/// Offset of the first capture in a closure object.
pub const CLOSURE_CAPTURES: u32 = ms_rt_abi::CLOSURE_CAPTURES_OFFSET as u32;

/// Kinds of generated helper functions.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Glue {
    /// Drops a value (takes the value's leaves).
    Drop,
    /// Clones a value (takes and returns the value's leaves).
    Clone,
    /// Closure object destructor `fn(obj)`; the `Ty` is unused (`Ty::UNIT`) and the key carries the function id.
    ClosureDrop(u32),
    /// Like `ClosureDrop` for an object in a stack frame: drops the captures, frees nothing.
    ClosureDropFramed(u32),
    /// `fn(obj)` that releases a closure object after capture `k` while a fault unwinds out of the
    /// close of that capture (whose value that close owns): it drops the later captures without
    /// closing them and frees the object.
    ClosureDropFrom(u32, u32),
    /// Closure object clone entry `fn(obj) -> obj`, cloning the captures; keyed like `ClosureDrop`.
    ClosureClone(u32),
    /// Heap block destructor of an interface payload `fn(block)`.
    BlockDrop,
    /// Clone of an interface payload block `fn(block) -> block`.
    BlockClone,
    /// `fn(arg: *mut u8)` thunk used by cleanup.push; key carries the closer function.
    CleanupThunk(u32),
    /// `fn(block)` that calls the function in the key with the parameters stored at `block` and
    /// stores its results after them: the body `msrt_task_grow` runs on a new stack segment.
    GrowShim(u32),
    /// `fn(slot)` that drops the value stored in memory at `slot` (descriptor `drop`).
    SlotDrop,
    /// `fn(src, dst)` that copies the value at `src` into uninitialised `dst` (descriptor `copy`).
    SlotCopy,
}

/// Runtime functions the generated code may call: `(name, params, returns)` with
/// `i` = i64, `b` = i8.
const RT: &[(&str, &str, &str)] = &[
    ("msrt_alloc", "i", "i"),
    ("msrt_free", "i", ""),
    ("msrt_realloc", "ii", "i"),
    ("msrt_obj_clone", "i", "i"),
    ("msrt_obj_drop", "i", ""),
    ("msrt_str_free", "i", ""),
    ("msrt_str_copy", "iii", ""),
    ("msrt_fault", "ii", ""),
    ("msrt_fault_int_overflow", "", ""),
    ("msrt_fault_int_range", "", ""),
    ("msrt_fault_div_zero", "", ""),
    ("msrt_fault_rem_zero", "", ""),
    ("msrt_fault_div_overflow", "ii", ""),
    ("msrt_index_fault", "ii", ""),
    ("msrt_fault_unwrap_none", "", ""),
    ("msrt_fault_depth", "", ""),
    ("msrt_task_grow", "ii", ""),
    ("msrt_cancelled", "", ""),
    ("msrt_isolate_hdr", "", "i"),
    ("msrt_cleanup_push", "ii", "i"),
    ("msrt_cleanup_run", "i", ""),
    ("msrt_cleanup_discard", "i", ""),
    ("msrt_unwind_drops", "", "b"),
    ("msrt_drop_enter", "", "i"),
    ("msrt_drop_defer", "ii", ""),
    ("msrt_drop_leave", "", ""),
    ("msrt_start", "iiii", "i"),
    ("msrt_string_length", "i", "i"),
    ("msrt_slot_drop", "ii", ""),
    ("msrt_slot_copy", "iii", ""),
];

/// Runtime data symbols: `(name, is_writable)`.
const RT_DATA: &[(&str, bool)] = &[
    ("msrt_ascii_chars", false),
    ("msrt_desc_int", false),
    ("msrt_desc_float32", false),
    ("msrt_desc_float", false),
    ("msrt_desc_bool", false),
    ("msrt_desc_string", false),
    ("msrt_desc_bytes", false),
];

fn clif_type(c: char) -> ir::Type {
    match c {
        'b' => types::I8,
        _ => types::I64,
    }
}

/// Cranelift type of a leaf in a register.
pub fn leaf_type(l: Leaf) -> ir::Type {
    match l {
        Leaf::I64 | Leaf::N8 | Leaf::N16 | Leaf::N32 | Leaf::U8 | Leaf::U16 | Leaf::U32 => {
            types::I64
        }
        Leaf::F64 => types::F64,
        Leaf::F32 => types::F32,
        Leaf::I8 => types::I8,
    }
}

/// Cranelift type of a leaf in memory.
pub fn mem_type(l: Leaf) -> ir::Type {
    match l {
        Leaf::N8 | Leaf::U8 => types::I8,
        Leaf::N16 | Leaf::U16 => types::I16,
        Leaf::N32 | Leaf::U32 => types::I32,
        Leaf::F32 => types::F32,
        _ => leaf_type(l),
    }
}

/// A linker-safe spelling of a source name: `@` starts a symbol version, and other punctuation
/// is not portable across object formats.
fn sym_safe(name: &str) -> String {
    name.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '$') {
                c
            } else {
                '_'
            }
        })
        .collect()
}

pub struct Gen<'m> {
    pub m: &'m Module,
    pub lay: Layouts<'m>,
    pub module: ObjectModule,
    pub opts: Options,
    pub funcs: Vec<FuncId>,
    pub rt: HashMap<&'static str, FuncId>,
    pub rt_data: HashMap<&'static str, DataId>,
    pub ext: HashMap<ExtId, FuncId>,
    pub strs: HashMap<u32, DataId>,
    pub list_consts: HashMap<usize, DataId>,
    pub blobs: HashMap<usize, DataId>,
    pub glue: HashMap<(Glue, Ty), FuncId>,
    /// The ids of the glue functions, indexed by id.
    pub glue_ids: std::collections::HashSet<FuncId>,
    pub queue: Vec<(Glue, Ty)>,
    pub vtables: Vec<DataId>,
    pub globals: Vec<DataId>,
    /// Interned `(file, line)` pairs referenced by Cranelift source locations (id = index).
    pub locs: Vec<(u32, u32, u32)>,
    loc_ids: HashMap<(u32, u32, u32), u32>,
    /// Inlined-callee scopes of every compiled function; [`ms_mir::ir::Loc::scope`] is
    /// shifted by `scope_base` to index it (1-based, 0 = none).
    pub scopes: Vec<ms_mir::ir::Scope>,
    pub scope_base: u32,
    /// Per compiled source function: the data for fault traces and profiles.
    pub dbg: Vec<FuncDbg>,
    /// Static type descriptors by type.
    pub desc_ids: HashMap<Ty, DataId>,
    /// Shared read-only blocks for payloadless cases of boxed alternatives, by `(alternative, case)`.
    unit_blocks: HashMap<(ms_mir::types::AltId, usize), DataId>,
    /// The `ms.tables` blob, once emitted.
    pub tables: Option<DataId>,
}

impl Gen<'_> {
    /// Linkage of module-private data.
    pub fn private(&self) -> Linkage {
        Linkage::Local
    }

    /// Declares `f` in a data object built by this compile.
    pub fn func_in_data(&mut self, f: FuncId, d: &mut DataDescription) -> ir::FuncRef {
        self.module.declare_func_in_data(f, d)
    }

    /// Linkage of a function defined in this compile.
    pub fn func_linkage(&self, exported: bool) -> Linkage {
        if exported {
            Linkage::Export
        } else {
            Linkage::Local
        }
    }
}

/// Debug facts about one compiled function.
pub struct FuncDbg {
    pub id: FuncId,
    pub name: String,
    pub file: u32,
    pub line: u32,
    pub size: u32,
    /// `(code offset, file, line, scope)` ranges, sorted by offset.
    pub ranges: Vec<(u32, u32, u32, u32)>,
    /// Exact known source spans `(start, end, file, line)`; gaps stay unmapped in DWARF.
    pub dwarf_ranges: Vec<(u32, u32, u32, u32)>,
}

impl<'m> Gen<'m> {
    /// Makes the inlined-callee scopes of `f` module-wide, so that locations can name them, and
    /// sets `scope_base` for [`Gen::loc_bits`].
    pub fn add_scopes(&mut self, f: &Func) {
        self.scope_base = self.scopes.len() as u32;
        for sc in &f.scopes {
            let mut sc = sc.clone();
            if sc.parent != 0 {
                sc.parent += self.scope_base;
            }
            self.scopes.push(sc);
        }
    }

    /// Cranelift source location bits for a MIR location (`!0` when unknown).
    pub fn loc_bits(&mut self, loc: ms_mir::ir::Loc) -> u32 {
        if loc.is_none() || loc.line == 0 {
            return !0;
        }
        let scope = if loc.scope == 0 {
            0
        } else {
            self.scope_base + loc.scope
        };
        let key = (loc.file, loc.line, scope);
        if let Some(i) = self.loc_ids.get(&key) {
            return *i;
        }
        let i = self.locs.len() as u32;
        self.locs.push(key);
        self.loc_ids.insert(key, i);
        i
    }

    pub fn sig(&self, params: &[Leaf], rets: &[Leaf]) -> Signature {
        let mut sig = self.module.make_signature();
        sig.params
            .extend(params.iter().map(|l| abi_param(leaf_type(*l))));
        sig.returns
            .extend(rets.iter().map(|l| abi_param(leaf_type(*l))));
        sig
    }

    /// Flattened parameter leaves of a function.
    pub fn param_leaves(&self, f: &Func) -> Vec<Leaf> {
        f.params
            .iter()
            .flat_map(|p| self.lay.leaves(p.ty))
            .collect()
    }

    /// Signature of a MIR function.
    pub fn func_sig(&self, f: &Func) -> Signature {
        self.sig(&self.param_leaves(f), &self.lay.leaves(f.ret))
    }

    /// The runtime import `name`.
    pub fn rt(&mut self, name: &'static str) -> FuncId {
        if let Some(id) = self.rt.get(name) {
            return *id;
        }
        let (_, p, r) = RT
            .iter()
            .find(|e| e.0 == name)
            .unwrap_or_else(|| panic!("unknown runtime function {name}"));
        let mut sig = self.module.make_signature();
        sig.params
            .extend(p.chars().map(|c| abi_param(clif_type(c))));
        sig.returns
            .extend(r.chars().map(|c| abi_param(clif_type(c))));
        let id = self
            .module
            .declare_function(name, Linkage::Import, &sig)
            .expect("declare runtime function");
        self.rt.insert(name, id);
        id
    }

    /// The runtime data symbol `name`.
    pub fn rt_data(&mut self, name: &'static str) -> DataId {
        if let Some(id) = self.rt_data.get(name) {
            return *id;
        }
        let writable = RT_DATA
            .iter()
            .find(|e| e.0 == name)
            .unwrap_or_else(|| panic!("unknown runtime data {name}"))
            .1;
        let id = self
            .module
            .declare_data(name, Linkage::Import, writable, false)
            .expect("declare runtime data");
        self.rt_data.insert(name, id);
        id
    }

    /// The glue function of `kind` for `ty`, queued for generation.
    pub fn glue(&mut self, kind: Glue, ty: Ty) -> FuncId {
        if let Some(id) = self.glue.get(&(kind, ty)) {
            return *id;
        }
        let leaves = self.lay.leaves(ty);
        let sig = match kind {
            Glue::Drop => self.sig(&leaves, &[]),
            Glue::Clone => self.sig(&leaves, &leaves),
            Glue::BlockClone | Glue::ClosureClone(_) => self.sig(&[Leaf::I64], &[Leaf::I64]),
            Glue::ClosureDrop(_)
            | Glue::ClosureDropFramed(_)
            | Glue::ClosureDropFrom(..)
            | Glue::BlockDrop
            | Glue::CleanupThunk(_)
            | Glue::GrowShim(_)
            | Glue::SlotDrop => self.sig(&[Leaf::I64], &[]),
            Glue::SlotCopy => self.sig(&[Leaf::I64, Leaf::I64], &[]),
        };
        let name = format!(
            "{GLUE_PREFIX}{}.{}",
            self.glue.len(),
            match kind {
                Glue::Drop => "drop",
                Glue::Clone => "clone",
                Glue::ClosureDrop(_) => "closure_drop",
                Glue::ClosureDropFramed(_) => "closure_drop_framed",
                Glue::ClosureDropFrom(..) => "closure_drop_from",
                Glue::ClosureClone(_) => "closure_clone",
                Glue::BlockDrop => "block_drop",
                Glue::BlockClone => "block_clone",
                Glue::CleanupThunk(_) => "cleanup_thunk",
                Glue::GrowShim(_) => "grow_shim",
                Glue::SlotDrop => "slot_drop",
                Glue::SlotCopy => "slot_copy",
            }
        );
        let id = self
            .module
            .declare_function(&name, self.func_linkage(false), &sig)
            .expect("declare glue");
        self.glue.insert((kind, ty), id);
        self.glue_ids.insert(id);
        self.queue.push((kind, ty));
        id
    }

    /// The static `TypeDesc` for slots of type `ty` (`crates/ms-rt/ABI.md`, section 5).
    pub fn typedesc(&mut self, ty: Ty) -> DataId {
        use ms_rt_abi::{
            DESC_DROP_OFFSET, KIND_CUSTOM, KIND_LIST, KIND_MAP, KIND_POD, KIND_SET, KIND_SHARED,
        };
        if let Some(id) = self.desc_ids.get(&ty) {
            return *id;
        }
        let m = self.m;
        // A scoped key names the same layout with the glue of one module's local implementations.
        let (key, scope) = (ty, ty.scope());
        let ty = ty.unscoped();
        let builtin = match m.types.kind(ty) {
            // `Int8`..`Int32` and `UInt8`..`UInt64` are plain bits of their width and take the `POD` path below.
            TyKind::Int => Some("msrt_desc_int"),
            TyKind::Float => Some("msrt_desc_float"),
            TyKind::Float32 => Some("msrt_desc_float32"),
            TyKind::Bool => Some("msrt_desc_bool"),
            TyKind::Str => Some("msrt_desc_string"),
            TyKind::Bytes => Some("msrt_desc_bytes"),
            _ => None,
        };
        if let Some(name) = builtin {
            let id = self.rt_data(name);
            self.desc_ids.insert(key, id);
            return id;
        }
        let name = format!("ms.desc.{}", self.desc_ids.len());
        let id = self
            .module
            .declare_data(&name, self.private(), false, false)
            .expect("declare descriptor");
        self.desc_ids.insert(key, id);
        let mem = self.lay.mem(ty);
        let mut inner: [Option<Ty>; 2] = [None, None];
        let mut with_glue = false;
        let kind = match m.types.kind(ty) {
            TyKind::List(e) => {
                inner[0] = Some(*e);
                KIND_LIST
            }
            TyKind::Obj(Native::Map, args) => {
                inner = [args.first().copied(), args.get(1).copied()];
                KIND_MAP
            }
            TyKind::Obj(Native::Set, args) => {
                inner[0] = args.first().copied();
                KIND_SET
            }
            TyKind::Obj(..) | TyKind::Fn(..) => KIND_SHARED,
            TyKind::Opt(i) if self.lay.opt_is_nullable(*i) => KIND_SHARED,
            _ if !m.needs_drop(ty) => KIND_POD,
            _ => {
                with_glue = true;
                KIND_CUSTOM
            }
        };
        let mut bytes = vec![0u8; ms_rt_abi::DESC_SIZE];
        bytes[0..4].copy_from_slice(&mem.size.to_le_bytes());
        bytes[4..8].copy_from_slice(&mem.align.to_le_bytes());
        bytes[8..12].copy_from_slice(&kind.to_le_bytes());
        let mut d = DataDescription::new();
        d.define(bytes.into_boxed_slice());
        d.set_align(8);
        for (k, t) in inner.into_iter().enumerate() {
            if let Some(t) = t {
                let did = self.typedesc(t.scoped(scope));
                let gv = self.module.declare_data_in_data(did, &mut d);
                d.write_data_addr(16 + 8 * k as u32, gv, 0);
            }
        }
        if with_glue {
            let drop = self.glue(Glue::SlotDrop, ty);
            let copy = self.glue(Glue::SlotCopy, ty);
            for (off, f) in [
                (DESC_DROP_OFFSET as u32, drop),
                (DESC_DROP_OFFSET as u32 + 8, copy),
            ] {
                let fr = self.func_in_data(f, &mut d);
                d.write_function_addr(off, fr);
            }
        }
        // The scope's own glue, else the unscoped one.
        let glue = m
            .desc_glue
            .iter()
            .find(|(t, _, _)| *t == key)
            .or_else(|| m.desc_glue.iter().find(|(t, _, _)| *t == ty));
        if let Some(&(_, eq, hash)) = glue {
            for (off, f) in [
                (ms_rt_abi::DESC_EQ_OFFSET as u32, eq),
                (ms_rt_abi::DESC_HASH_OFFSET as u32, hash),
            ] {
                let fr = self.func_in_data(self.funcs[f.index()], &mut d);
                d.write_function_addr(off, fr);
            }
        }
        self.module.define_data(id, &d).expect("define descriptor");
        id
    }

    /// The shared block of payloadless case `case` of a boxed alternative: `size` zero bytes with
    /// the tag stored first. Such values never allocate, and dropping them frees nothing.
    pub fn unit_block(&mut self, alt: ms_mir::types::AltId, case: usize, size: usize) -> DataId {
        if let Some(id) = self.unit_blocks.get(&(alt, case)) {
            return *id;
        }
        let id = self
            .module
            .declare_data(
                &format!("ms.unit.{}", self.unit_blocks.len()),
                self.private(),
                false,
                false,
            )
            .expect("declare unit block");
        let mut bytes = vec![0u8; size.max(8)];
        bytes[0..8].copy_from_slice(&(case as u64).to_le_bytes());
        let mut d = DataDescription::new();
        d.define(bytes.into_boxed_slice());
        d.set_align(8);
        self.module.define_data(id, &d).expect("define unit block");
        self.unit_blocks.insert((alt, case), id);
        id
    }

    /// A static `String` block for literal `i`: the bytes then a NUL.
    /// The static data of constant list `i` (`list.const`), laid out as its elements are in memory.
    pub fn list_const(&mut self, i: usize, elem: Ty) -> DataId {
        if let Some(id) = self.list_consts.get(&i) {
            return *id;
        }
        let leaf = self.lay.leaves(elem)[0];
        let bytes = leaf.const_bytes(&self.m.list_consts[i]);
        let id = self
            .module
            .declare_data(&format!("ms.list.{i}"), self.private(), false, false)
            .expect("declare constant list");
        let mut d = DataDescription::new();
        d.define(bytes.into_boxed_slice());
        d.set_align(16);
        self.module
            .define_data(id, &d)
            .expect("define constant list");
        self.list_consts.insert(i, id);
        id
    }

    /// The read-only data of constant bytes `i`.
    pub fn blob(&mut self, i: usize) -> DataId {
        if let Some(id) = self.blobs.get(&i) {
            return *id;
        }
        let id = self
            .module
            .declare_data(&format!("ms.blob.{i}"), self.private(), false, false)
            .expect("declare constant bytes");
        let mut d = DataDescription::new();
        d.define(self.m.blobs[i].clone().into_boxed_slice());
        d.set_align(16);
        self.module
            .define_data(id, &d)
            .expect("define constant bytes");
        self.blobs.insert(i, id);
        id
    }

    pub fn str_lit(&mut self, i: u32) -> DataId {
        if let Some(id) = self.strs.get(&i) {
            return *id;
        }
        let s = &self.m.strings[i as usize];
        let mut bytes = s.as_bytes().to_vec();
        bytes.push(0);
        let id = self
            .module
            .declare_data(&format!("ms.str.{i}"), self.private(), true, false)
            .expect("declare string");
        let mut d = DataDescription::new();
        d.define(bytes.into_boxed_slice());
        d.set_align(16);
        self.module.define_data(id, &d).expect("define string");
        self.strs.insert(i, id);
        id
    }
}

pub fn compile(m: &Module, opts: &Options) -> Result<Vec<u8>, Error> {
    let isa_builder = cranelift_native::builder().map_err(|e| e.to_string())?;
    compile_with_isa(m, opts, isa_builder)
}

/// MIR instructions in one function above which a Debug module is allocated with the single-pass
/// register allocator.
const SINGLE_PASS_INSTS: usize = ms_mir::opt::LONG_FUNCTION_INSTS;

fn single_pass(m: &Module, opts: &Options) -> bool {
    opts.opt_level == "none"
        && m.funcs
            .iter()
            .any(|f| ms_mir::opt::instruction_count(f) > SINGLE_PASS_INSTS)
}

fn compile_with_isa(
    m: &Module,
    opts: &Options,
    isa_builder: cranelift_codegen::isa::Builder,
) -> Result<Vec<u8>, Error> {
    let arm64_coff = windows_arm64(isa_builder.triple());
    let mut flags = settings::builder();
    flags
        .set("opt_level", opts.opt_level)
        .map_err(|e| e.to_string())?;
    flags
        .set(
            "enable_verifier",
            if opts.build.clif_verify {
                "true"
            } else {
                "false"
            },
        )
        .map_err(|e| e.to_string())?;
    if single_pass(m, opts) {
        // The backtracking allocator is quadratic in a function's size and Debug builds keep owned
        // values live to scope end, so a very long function takes seconds; the single-pass
        // allocator is near linear but emits slower code, so only such modules use it.
        flags
            .set("regalloc_algorithm", "single_pass")
            .map_err(|e| e.to_string())?;
    }
    // Cranelift's ARM64 COFF writer supports absolute addresses, but not GOT or
    // ADRP data relocations. The PE linker types these absolute addresses in
    // the image's base-relocation table so the loader can still relocate it.
    flags
        .set("is_pic", if arm64_coff { "false" } else { "true" })
        .map_err(|e| e.to_string())?;
    flags
        .set("preserve_frame_pointers", "true")
        .map_err(|e| e.to_string())?;
    flags
        .set("enable_multi_ret_implicit_sret", "true")
        .map_err(|e| e.to_string())?;
    flags
        .set("unwind_info", "false")
        .map_err(|e| e.to_string())?;
    // Windows commits stack one guard page at a time, so a frame larger than a page that is not
    // probed in order faults with no diagnostic. Inline probing needs no `__rust_probestack`
    // symbol, which this runtime does not provide.
    flags
        .set("enable_probestack", "true")
        .map_err(|e| e.to_string())?;
    flags
        .set("probestack_strategy", "inline")
        .map_err(|e| e.to_string())?;
    let isa = isa_builder
        .finish(settings::Flags::new(flags))
        .map_err(|e| e.to_string())?;
    let worker_isa = isa.clone();
    let builder = ObjectBuilder::new(isa, m.name.as_str(), default_libcall_names())
        .map_err(|e| e.to_string())?;
    let module = ObjectModule::new(builder);
    let mut g = Gen {
        m,
        lay: Layouts::new(m),
        module,
        opts: opts.clone(),
        funcs: Vec::new(),
        rt: HashMap::new(),
        rt_data: HashMap::new(),
        ext: HashMap::new(),
        strs: HashMap::new(),
        list_consts: HashMap::new(),
        blobs: HashMap::new(),
        glue: HashMap::new(),
        glue_ids: Default::default(),
        queue: Vec::new(),
        vtables: Vec::new(),
        globals: Vec::new(),
        locs: Vec::new(),
        loc_ids: HashMap::new(),
        scopes: Vec::new(),
        scope_base: 0,
        dbg: Vec::new(),
        tables: None,
        desc_ids: HashMap::new(),
        unit_blocks: HashMap::new(),
    };
    let mut ctx = Context::new();
    let mut fctx = FunctionBuilderContext::new();
    {
        {
            for (i, f) in m.funcs.iter().enumerate() {
                let sig = g.func_sig(f);
                let exported = f.linkage == ms_mir::ir::Linkage::Export
                    || m.entry.is_some_and(|e| e.index() == i);
                let is_entry = m.entry.is_some_and(|e| e.index() == i);
                let name = if is_entry {
                    "ms_entry".to_string()
                } else if exported {
                    f.name.clone()
                } else {
                    format!("{}#{i}", sym_safe(&f.name))
                };
                let id = g
                    .module
                    .declare_function(&name, g.func_linkage(exported), &sig)
                    .map_err(|e| e.to_string())?;
                g.funcs.push(id);
            }
            for (i, gl) in m.globals.iter().enumerate() {
                let mem = g.lay.mem(gl.ty);
                let id = g
                    .module
                    .declare_data(
                        &format!("ms.global.{i}.{}", sym_safe(&gl.name)),
                        g.private(),
                        true,
                        false,
                    )
                    .map_err(|e| e.to_string())?;
                let mut d = DataDescription::new();
                d.define_zeroinit(mem.size.max(8) as usize);
                d.set_align(8);
                g.module.define_data(id, &d).map_err(|e| e.to_string())?;
                g.globals.push(id);
            }
            // Vtables are defined after functions are declared: slot 0 is the payload block destructor,
            // the methods follow, then the payload block copier.
            for (i, vt) in m.vtables.iter().enumerate() {
                let id = g
                    .module
                    .declare_data(
                        &format!("ms.vtable.{i}.{}", sym_safe(&vt.name)),
                        g.private(),
                        false,
                        false,
                    )
                    .map_err(|e| e.to_string())?;
                g.vtables.push(id);
                let drop = g.glue(Glue::BlockDrop, vt.data_ty);
                let copy = g.glue(Glue::BlockClone, vt.data_ty);
                let mut d = DataDescription::new();
                d.define(vec![0u8; 8 * (2 + vt.methods.len())].into_boxed_slice());
                d.set_align(8);
                let r = g.func_in_data(drop, &mut d);
                d.write_function_addr(0, r);
                // The payload copier follows the methods.
                let r = g.func_in_data(copy, &mut d);
                d.write_function_addr(8 * (1 + vt.methods.len()) as u32, r);
                for (k, mf) in vt.methods.iter().enumerate() {
                    let r = g.func_in_data(g.funcs[mf.index()], &mut d);
                    d.write_function_addr(8 * (1 + k as u32), r);
                }
                g.module.define_data(id, &d).map_err(|e| e.to_string())?;
            }
            // Lowering and defining stay on this thread, in function order; Cranelift compiles in between
            // on the other cores, so no stage waits for a whole batch of the others.
            std::thread::scope(|scope| -> Result<(), Error> {
                let mut pipe = Pipeline::start(scope, &worker_isa);
                let mut temps;
                for (i, f) in m.funcs.iter().enumerate() {
                    ctx.clear();
                    ctx.func.signature = g.func_sig(f);
                    ctx.func.name = UserFuncName::user(0, g.funcs[i].as_u32());
                    {
                        let mut l = Lower::new(&mut g, &mut ctx.func, &mut fctx);
                        l.lower_func(i, f);
                        if let Some(u) = l.unsupported.clone() {
                            return Err(Error(format!("{}: unsupported: {u}", f.name)));
                        }
                        temps = l.finish();
                    }
                    crate::slotshare::share(&mut ctx.func, &temps);
                    let fid = g.funcs[i];
                    prepare(&g, &mut ctx);
                    pipe.submit(&mut g, std::mem::replace(&mut ctx, Context::new()), fid, i)?;
                }
                pipe.finish(&mut g)
            })?;
            while let Some((kind, ty)) = g.queue.pop() {
                let temps;
                let id = g.glue[&(kind, ty)];
                ctx.clear();
                let leaves = g.lay.leaves(ty);
                ctx.func.signature = match kind {
                    Glue::Drop => g.sig(&leaves, &[]),
                    Glue::Clone => g.sig(&leaves, &leaves),
                    Glue::BlockClone | Glue::ClosureClone(_) => g.sig(&[Leaf::I64], &[Leaf::I64]),
                    Glue::SlotCopy => g.sig(&[Leaf::I64, Leaf::I64], &[]),
                    _ => g.sig(&[Leaf::I64], &[]),
                };
                ctx.func.name = UserFuncName::user(0, id.as_u32());
                {
                    let mut l = Lower::new(&mut g, &mut ctx.func, &mut fctx);
                    l.lower_glue(kind, ty);
                    temps = l.finish();
                }
                crate::slotshare::share(&mut ctx.func, &temps);
                define(&mut g, &mut ctx, id, "glue")?;
            }
        }
    }
    let tables = if g.m.entry.is_some() {
        Some(emit_tables(&mut g)?)
    } else {
        None
    };
    emit_main(&mut g, &mut ctx, &mut fctx)?;
    let endian = g.module.isa().endianness();
    let mut product = g.module.finish();
    if let Some(t) = tables {
        relocate_tables(&mut product, &g.dbg, &t);
    }
    crate::dwarf::emit(&mut product, m, &g.dbg, endian)?;
    product.emit().map_err(|e| Error(e.to_string()))
}

fn windows_arm64(triple: &target_lexicon::Triple) -> bool {
    triple.operating_system == target_lexicon::OperatingSystem::Windows
        && matches!(
            triple.architecture,
            target_lexicon::Architecture::Aarch64(_)
        )
}

/// The emitted `ms.tables` blob, kept to relocate it after `finish`.
struct Tables {
    id: DataId,
    built: ms_mir::fault_tables::Built,
}

/// Builds the symbol and line tables handed to `msrt_start` (`crates/ms-rt/ABI.md`).
/// Absolute addresses are zero here and filled by relocations in [`relocate_tables`].
fn emit_tables(g: &mut Gen) -> Result<Tables, Error> {
    let funcs: Vec<_> = g
        .dbg
        .iter()
        .map(|d| ms_mir::fault_tables::FuncTable {
            name: &d.name,
            file: d.file,
            line: d.line,
            size: d.size,
            ranges: &d.ranges,
        })
        .collect();
    let mut built = ms_mir::fault_tables::build(&g.m.files, &funcs, &g.scopes);
    let id = g
        .module
        .declare_data("ms.tables", Linkage::Local, true, false)
        .map_err(|e| e.to_string())?;
    let mut desc = DataDescription::new();
    desc.define(std::mem::take(&mut built.blob).into_boxed_slice());
    desc.set_align(8);
    g.module.define_data(id, &desc).map_err(|e| e.to_string())?;
    g.tables = Some(id);
    Ok(Tables { id, built })
}

/// Adds the absolute relocations that point the tables at code and at themselves.
fn relocate_tables(product: &mut cranelift_object::ObjectProduct, dbg: &[FuncDbg], t: &Tables) {
    use cranelift_object::object::{
        RelocationEncoding, RelocationFlags, RelocationKind,
        write::{Relocation, SymbolSection},
    };
    let own = product.data_symbol(t.id);
    let own_sym = product.object.symbol(own);
    let SymbolSection::Section(section) = own_sym.section else {
        return;
    };
    // Relocation offsets are section-relative; the blob sits at `base` inside its section.
    let base = own_sym.value as usize;
    let flags = RelocationFlags::Generic {
        kind: RelocationKind::Absolute,
        encoding: RelocationEncoding::Generic,
        size: 64,
    };
    let syms: Vec<_> = t
        .built
        .pcs
        .iter()
        .map(|p| product.function_symbol(dbg[p.1].id))
        .collect();
    let obj = &mut product.object;
    let mut add = |offset: usize, symbol, addend: i64| {
        let r = Relocation {
            offset: (base + offset) as u64,
            symbol,
            addend,
            flags,
        };
        obj.add_relocation(section, r).expect("relocation");
    };
    for &(at, target) in &t.built.pointers {
        add(at, own, target as i64);
    }
    for (&(at, _, off), sym) in t.built.pcs.iter().zip(syms) {
        add(at, sym, i64::from(off));
    }
}

fn define(g: &mut Gen, ctx: &mut Context, id: FuncId, name: &str) -> Result<(), Error> {
    define_with(g, ctx, id, name, None)
}

/// Defines the function; `source` is the MIR function it came from (for the symbol and line tables).
fn define_with(
    g: &mut Gen,
    ctx: &mut Context,
    id: FuncId,
    name: &str,
    source: Option<&Func>,
) -> Result<(), Error> {
    prepare(g, ctx);
    g.module
        .define_function(id, ctx)
        .map_err(|e| Error(format!("{name}: {e:?}")))?;
    finish(g, ctx, id, name, source)
}

/// Lowered functions in flight at once; bounds the contexts held.
const IN_FLIGHT: usize = 512;

/// A function compiled by a worker: its position in the order, its MIR index and symbol, and the
/// context (or the error) that Cranelift returned.
type Done = (usize, FuncId, usize, Result<Context, String>);

/// Cranelift compilation on worker threads. Functions are submitted as they are lowered and defined
/// in submission order as their results arrive, so the object is the same as a serial build's.
struct Pipeline {
    jobs: Option<std::sync::mpsc::Sender<(usize, FuncId, usize, Context)>>,
    done: std::sync::mpsc::Receiver<Done>,
    /// Results that arrived ahead of an earlier function's.
    early: HashMap<usize, Done>,
    submitted: usize,
    defined: usize,
}

impl Pipeline {
    fn start<'s>(
        scope: &'s std::thread::Scope<'s, '_>,
        isa: &'s cranelift_codegen::isa::OwnedTargetIsa,
    ) -> Pipeline {
        use std::sync::{Mutex, mpsc};
        let (jobs, queue) = mpsc::channel::<(usize, FuncId, usize, Context)>();
        let (sender, done) = mpsc::channel::<Done>();
        let queue = std::sync::Arc::new(Mutex::new(queue));
        let threads = std::thread::available_parallelism().map_or(1, usize::from);
        for _ in 0..threads {
            let (queue, sender) = (queue.clone(), sender.clone());
            scope.spawn(move || {
                let mut plane = cranelift_codegen::control::ControlPlane::default();
                loop {
                    let job = queue.lock().unwrap().recv();
                    let Ok((seq, id, i, mut ctx)) = job else {
                        return;
                    };
                    let result = match ctx.compile(&**isa, &mut plane) {
                        Ok(_) => Ok(ctx),
                        Err(e) => Err(format!("{e:?}")),
                    };
                    if sender.send((seq, id, i, result)).is_err() {
                        return;
                    }
                }
            });
        }
        Pipeline {
            jobs: Some(jobs),
            done,
            early: HashMap::new(),
            submitted: 0,
            defined: 0,
        }
    }

    fn submit(&mut self, g: &mut Gen, ctx: Context, id: FuncId, i: usize) -> Result<(), Error> {
        let seq = self.submitted;
        self.submitted += 1;
        self.jobs
            .as_ref()
            .expect("pipeline open")
            .send((seq, id, i, ctx))
            .map_err(|_| Error("Cranelift worker stopped".into()))?;
        self.drain(g, self.submitted - self.defined > IN_FLIGHT)
    }

    /// Defines every function whose turn has come; with `block`, waits until the backlog is
    /// back under the bound.
    fn drain(&mut self, g: &mut Gen, mut block: bool) -> Result<(), Error> {
        loop {
            while let Ok(d) = self.done.try_recv() {
                self.early.insert(d.0, d);
            }
            while let Some(d) = self.early.remove(&self.defined) {
                self.define(g, d)?;
                self.defined += 1;
                block = block && self.submitted - self.defined > IN_FLIGHT / 2;
            }
            if !block {
                return Ok(());
            }
            let d = self
                .done
                .recv()
                .map_err(|_| Error("Cranelift worker stopped".into()))?;
            self.early.insert(d.0, d);
        }
    }

    fn finish(mut self, g: &mut Gen) -> Result<(), Error> {
        self.jobs = None;
        while self.defined < self.submitted {
            self.drain(g, true)?;
        }
        Ok(())
    }

    fn define(&mut self, g: &mut Gen, (_, id, i, result): Done) -> Result<(), Error> {
        let f = &g.m.funcs[i];
        let mut ctx = result.map_err(|e| Error(format!("{}: {e}", f.name)))?;
        let cc = ctx.compiled_code().expect("function compiled");
        let relocs: Vec<_> = cc
            .buffer
            .relocs()
            .iter()
            .map(|r| cranelift_module::ModuleReloc::from_mach_reloc(r, &ctx.func, id))
            .collect();
        let alignment = cc.buffer.alignment as u64;
        g.module
            .define_function_bytes(id, alignment, cc.buffer.data(), &relocs)
            .map_err(|e| Error(format!("{}: {e:?}", f.name)))?;
        finish(g, &mut ctx, id, &f.name, Some(f))
    }
}

/// Runs the passes that precede Cranelift's own compilation.
fn prepare(g: &Gen, ctx: &mut Context) {
    if windows_arm64(g.module.isa().triple()) {
        // Non-PIC near symbols also select unsupported ADRP relocations.
        // Far symbol addresses use the COFF writer's supported Abs8 form.
        for value in ctx.func.global_values.values_mut() {
            if let ir::GlobalValueData::Symbol { colocated, .. } = value {
                *colocated = false;
            }
        }
        let addresses: Vec<_> = ctx
            .func
            .layout
            .blocks()
            .flat_map(|block| ctx.func.layout.block_insts(block))
            .filter_map(|inst| match ctx.func.dfg.insts[inst] {
                ir::InstructionData::FuncAddr { func_ref, .. } => Some(func_ref),
                _ => None,
            })
            .collect();
        for func_ref in addresses {
            ctx.func.dfg.ext_funcs[func_ref].colocated = false;
        }
    }
    if g.opts.dump_clif || g.opts.build.dump_clif {
        eprintln!("; {}\n{}", ctx.func.name, ctx.func.display());
    }
    if g.opts.opt_level != "none" {
        crate::spill::spill_loop_cold(&mut ctx.func);
    }
}

/// Types the line and fault tables of a function that Cranelift has compiled and defined.
fn finish(
    g: &mut Gen,
    ctx: &mut Context,
    id: FuncId,
    name: &str,
    source: Option<&Func>,
) -> Result<(), Error> {
    {
        let cc = ctx.compiled_code().expect("function compiled");
        let mut ranges: Vec<(u32, u32, u32, u32)> = Vec::new();
        let mut dwarf_ranges = Vec::new();
        for r in cc.buffer.get_srclocs_sorted() {
            let bits = r.loc.bits();
            let Some((file, line, scope)) = g.locs.get(bits as usize).copied() else {
                continue;
            };
            if source.is_some() && r.start < r.end {
                dwarf_ranges.push((r.start, r.end, file, line));
            }
            if ranges
                .last()
                .is_none_or(|l| (l.1, l.2, l.3) != (file, line, scope))
            {
                ranges.push((r.start, file, line, scope));
            }
        }
        // Frames of inlined callees return to the physical function's file, so a function
        // without a position of its own borrows the first file its lines name.
        // Glue has no source of its own, but a cleanup thunk can hold an inlined callee, whose
        // frame a fault trace must still name.
        let (file, line) = match source {
            Some(f) if !f.loc.is_none() => (f.loc.file, f.loc.line),
            _ => {
                let own = ranges.iter().find(|r| r.3 == 0 && r.1 != u32::MAX);
                let first = own
                    .map(|r| r.1)
                    .or_else(|| ranges.iter().map(|r| r.1).find(|f| *f != u32::MAX));
                (first.unwrap_or(u32::MAX), 0)
            }
        };
        if source.is_none() && ranges.is_empty() {
            g.module.clear_context(ctx);
            return Ok(());
        }
        g.dbg.push(FuncDbg {
            id,
            name: source.map_or_else(|| name.to_string(), |f| f.name.clone()),
            file,
            line,
            size: cc.code_buffer().len() as u32,
            ranges,
            dwarf_ranges,
        });
    }
    g.module.clear_context(ctx);
    Ok(())
}

/// Emits the C `main(argc, argv)` that hands the entry function to the runtime.
fn emit_main(
    g: &mut Gen,
    ctx: &mut Context,
    fctx: &mut FunctionBuilderContext,
) -> Result<(), Error> {
    let Some(entry) = g.m.entry else {
        return Ok(());
    };
    let entry_id = g.funcs[entry.index()];
    let mut sig = g.module.make_signature();
    sig.params.push(AbiParam::new(types::I32));
    sig.params.push(AbiParam::new(types::I64));
    sig.returns.push(AbiParam::new(types::I32));
    let id = g
        .module
        .declare_function("main", Linkage::Export, &sig)
        .map_err(|e| e.to_string())?;
    ctx.clear();
    ctx.func.signature = sig;
    ctx.func.name = UserFuncName::user(0, id.as_u32());
    let temps;
    {
        let mut l = Lower::new(g, &mut ctx.func, fctx);
        l.lower_main(entry_id);
        temps = l.finish();
    }
    crate::slotshare::share(&mut ctx.func, &temps);
    define(g, ctx, id, "main")
}

#[cfg(test)]
mod target_tests {
    use super::*;

    #[test]
    fn compile_honors_the_requested_optimization_level() {
        let m = ms_mir::parse::parse_module(
            "module \"levels\"\nfn @identity(%x: int) -> int export {\nb0:\n  ret %x\n}\n",
        )
        .unwrap();
        for opt_level in ["none", "speed", "speed_and_size"] {
            compile(
                &m,
                &Options {
                    opt_level,
                    ..Options::default()
                },
            )
            .unwrap();
        }
        assert!(
            compile(
                &m,
                &Options {
                    opt_level: "invalid",
                    ..Options::default()
                },
            )
            .is_err(),
            "an unknown Cranelift optimization level must be rejected"
        );
    }

    #[test]
    fn long_debug_functions_use_the_single_pass_allocator() {
        let body = |n: usize| {
            let mut text = String::from("module \"m\"\nfn @main() -> int export {\nb0:\n");
            for i in 0..n {
                text.push_str(&format!("  %{i}: int = iconst {i}\n"));
            }
            text.push_str(&format!("  ret %{}\n}}\n", n - 1));
            ms_mir::parse::parse_module(&text).unwrap()
        };
        let debug = Options {
            opt_level: "none",
            ..Options::default()
        };
        assert!(!single_pass(&body(100), &debug));
        assert!(single_pass(&body(SINGLE_PASS_INSTS + 1), &debug));
        assert!(!single_pass(
            &body(SINGLE_PASS_INSTS + 1),
            &Options::default()
        ));
    }

    #[test]
    fn mir_fixtures_emit_for_all_six_supported_platforms() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../ms-mir/tests");
        let mut files = Vec::new();
        for dir in ["fixtures", "fixtures-opt"] {
            files.extend(
                std::fs::read_dir(root.join(dir))
                    .unwrap()
                    .map(|entry| entry.unwrap().path())
                    .filter(|p| p.extension().is_some_and(|e| e == "mir")),
            );
        }
        files.sort();
        assert!(files.len() >= 18);
        let targets: [(&str, &[u8]); 6] = [
            ("x86_64-unknown-linux-gnu", b"\x7fELF"),
            ("aarch64-unknown-linux-gnu", b"\x7fELF"),
            ("x86_64-apple-darwin", b"\xcf\xfa\xed\xfe"),
            ("aarch64-apple-darwin", b"\xcf\xfa\xed\xfe"),
            ("x86_64-pc-windows-gnu", b"\x64\x86"),
            ("aarch64-pc-windows-gnullvm", b"\x64\xaa"),
        ];
        for path in files {
            let source = std::fs::read_to_string(&path).unwrap();
            for level in [ms_mir::opt::Level::None, ms_mir::opt::Level::Speed] {
                let mut m = ms_mir::parse::parse_module(&source).unwrap();
                ms_mir::verify::verify_module(&m).unwrap();
                ms_mir::opt::optimize(&mut m, level, true);
                let opts = Options {
                    opt_level: if level == ms_mir::opt::Level::None {
                        "none"
                    } else {
                        "speed"
                    },
                    ..Options::default()
                };
                for (target, magic) in targets {
                    let triple: target_lexicon::Triple = target.parse().unwrap();
                    let isa = cranelift_codegen::isa::lookup(triple).unwrap();
                    let object = compile_with_isa(&m, &opts, isa)
                        .unwrap_or_else(|e| panic!("{} {target} {level:?}: {e}", path.display()));
                    assert!(object.starts_with(magic), "{} {target}", path.display());
                }
            }
        }
    }
}
