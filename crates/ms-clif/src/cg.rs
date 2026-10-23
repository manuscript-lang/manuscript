//! Module-level code generation state: function declarations, runtime imports,
//! static data, and the glue functions (drop, copy) generated on demand.

use crate::layout::{Layouts, Leaf};
use crate::lower::Lower;
use crate::{Error, Options};
use cranelift_codegen::Context;
use cranelift_codegen::ir::{self, AbiParam, Signature, UserFuncName, types};

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
use std::collections::{HashMap, HashSet};

/// `rc` of static objects (`ms_rt_abi::STATIC_RC`).
pub const STATIC_RC: u64 = 1 << 62;
/// `ms_rt_abi::STR_DATA_OFFSET`.
pub const STR_DATA_OFFSET: usize = 32;
/// Offset of `code` in a closure object.
pub const CLOSURE_CODE: i32 = 16;
/// Offset of the payload in a `Shared[T]` box.
pub const SHARED_VALUE: i64 = 16;
/// Offset of the first capture in a closure object.
pub const CLOSURE_CAPTURES: u32 = 24;

/// Kinds of generated helper functions.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Glue {
    /// Drops a value (takes the value's leaves).
    Drop,
    /// Deep-copies a value (takes and returns the value's leaves).
    Copy,
    /// Closure object destructor `fn(obj)`; the `Ty` is unused (`Ty::UNIT`) and the key carries the function id.
    ClosureDrop(u32),
    /// Heap block destructor of an interface payload `fn(block)`.
    BlockDrop,
    /// Deep copy of an interface payload block `fn(block) -> block`.
    BlockCopy,
    /// `fn(arg: *mut u8)` thunk used by cleanup.push; key carries the closer function.
    CleanupThunk(u32),
    /// Destructor of a `Shared[T]` box `fn(obj)`; the `Ty` is `T`. Drops the payload, frees the box.
    SharedDrop,
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
    ("msrt_drop_slow", "i", ""),
    ("msrt_fault", "ii", ""),
    ("msrt_fault_int_overflow", "", ""),
    ("msrt_fault_div_zero", "", ""),
    ("msrt_fault_rem_zero", "", ""),
    ("msrt_fault_div_overflow", "ii", ""),
    ("msrt_index_fault", "ii", ""),
    ("msrt_fault_unwrap_none", "", ""),
    ("msrt_fault_depth", "", ""),
    ("msrt_cancelled", "", ""),
    ("msrt_cleanup_push", "ii", "i"),
    ("msrt_cleanup_run", "i", ""),
    ("msrt_start", "iiii", "i"),
    ("msrt_string_length", "i", "i"),
    ("msrt_slot_drop", "ii", ""),
    ("msrt_slot_copy", "iii", ""),
];

/// Runtime data symbols: `(name, is_writable)`.
const RT_DATA: &[(&str, bool)] = &[
    ("msrt_cancel_flag", false),
    ("msrt_stack_limit", true),
    ("msrt_ascii_chars", false),
    ("msrt_desc_int", false),
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

/// Cranelift type of a leaf.
pub fn leaf_type(l: Leaf) -> ir::Type {
    match l {
        Leaf::I64 => types::I64,
        Leaf::F64 => types::F64,
        Leaf::I8 => types::I8,
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
    pub glue: HashMap<(Glue, Ty), FuncId>,
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
    /// Functions translated to LLVM IR instead of being compiled by Cranelift (release builds).
    pub llvm: Option<crate::llvm_ir::LlvmModule>,
    /// Source functions defined through [`Gen::llvm`], for the fault and profile tables.
    pub llvm_funcs: Vec<LlvmFn>,
    /// Functions the Cranelift object refers to by address.
    pub pinned: HashSet<FuncId>,
    /// Symbol the LLVM-built code's table addresses are relative to.
    pub anchor: Option<FuncId>,
}

/// A source function compiled by LLVM.
pub struct LlvmFn {
    pub id: FuncId,
    pub symbol: String,
    pub name: String,
    pub file: u32,
    pub line: u32,
}

impl Gen<'_> {
    /// Linkage of module-private data and functions: visible to the LLVM object when it is used.
    pub fn private(&self) -> Linkage {
        if self.llvm.is_some() {
            Linkage::Export
        } else {
            Linkage::Local
        }
    }

    /// Declares `f` in a data object built by this compile. The Cranelift object then names it, so
    /// an LLVM-built `f` must stay a visible symbol.
    pub fn func_in_data(&mut self, f: FuncId, d: &mut DataDescription) -> ir::FuncRef {
        self.pinned.insert(f);
        self.module.declare_func_in_data(f, d)
    }

    /// Linkage of a function defined in this compile: LLVM-built functions are imported here.
    pub fn func_linkage(&self, exported: bool) -> Linkage {
        if self.opts.llvm.is_some() {
            Linkage::Import
        } else if exported {
            Linkage::Export
        } else {
            Linkage::Local
        }
    }
}

struct ModuleSymbols<'a>(
    &'a ObjectModule,
    &'a [(u32, u32, u32)],
    &'a [ms_mir::ir::Scope],
);

impl ModuleSymbols<'_> {
    fn symbol_of(&self, id: FuncId) -> String {
        self.0
            .declarations()
            .get_function_decl(id)
            .linkage_name(id)
            .into_owned()
    }
}

impl crate::llvm_ir::Symbols for ModuleSymbols<'_> {
    fn loc(&self, bits: u32) -> Option<(u32, u32, u32)> {
        self.1.get(bits as usize).copied()
    }

    fn scope(&self, idx: u32) -> Option<(String, u32, u32, u32)> {
        let sc = self.2.get((idx as usize).checked_sub(1)?)?;
        Some((sc.name.clone(), sc.file, sc.parent, sc.call_line))
    }

    fn symbol(&self, namespace: u32, index: u32) -> String {
        let decls = self.0.declarations();
        if namespace == 0 {
            decls
                .get_function_decl(FuncId::from_u32(index))
                .linkage_name(FuncId::from_u32(index))
                .into_owned()
        } else {
            decls
                .get_data_decl(DataId::from_u32(index))
                .linkage_name(DataId::from_u32(index))
                .into_owned()
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
    /// Offset of the function from [`crate::llvm_ir::TEXT_ANCHOR`]; zero when Cranelift built it
    /// (its own symbol is the table's target).
    pub text: u64,
}

impl<'m> Gen<'m> {
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
            Glue::Copy => self.sig(&leaves, &leaves),
            Glue::BlockCopy => self.sig(&[Leaf::I64], &[Leaf::I64]),
            Glue::ClosureDrop(_)
            | Glue::BlockDrop
            | Glue::CleanupThunk(_)
            | Glue::SlotDrop
            | Glue::SharedDrop => self.sig(&[Leaf::I64], &[]),
            Glue::SlotCopy => self.sig(&[Leaf::I64, Leaf::I64], &[]),
        };
        let name = format!(
            "ms.glue.{}.{}",
            self.glue.len(),
            match kind {
                Glue::Drop => "drop",
                Glue::Copy => "copy",
                Glue::ClosureDrop(_) => "closure_drop",
                Glue::BlockDrop => "block_drop",
                Glue::BlockCopy => "block_copy",
                Glue::CleanupThunk(_) => "cleanup_thunk",
                Glue::SlotDrop => "slot_drop",
                Glue::SharedDrop => "shared_drop",
                Glue::SlotCopy => "slot_copy",
            }
        );
        let id = self
            .module
            .declare_function(&name, self.func_linkage(false), &sig)
            .expect("declare glue");
        self.glue.insert((kind, ty), id);
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
        let builtin = match m.types.kind(ty) {
            TyKind::Int => Some("msrt_desc_int"),
            TyKind::Float => Some("msrt_desc_float"),
            TyKind::Bool => Some("msrt_desc_bool"),
            TyKind::Str => Some("msrt_desc_string"),
            TyKind::Bytes => Some("msrt_desc_bytes"),
            _ => None,
        };
        if let Some(name) = builtin {
            let id = self.rt_data(name);
            self.desc_ids.insert(ty, id);
            return id;
        }
        let name = format!("ms.desc.{}", self.desc_ids.len());
        let id = self
            .module
            .declare_data(&name, self.private(), false, false)
            .expect("declare descriptor");
        self.desc_ids.insert(ty, id);
        let mem = self.lay.mem(ty);
        let mut inner: [Option<Ty>; 2] = [None, None];
        let mut with_glue = false;
        let kind = match m.types.kind(ty) {
            TyKind::List(e) => {
                inner[0] = Some(*e);
                KIND_LIST
            }
            TyKind::Obj(n, args) if n == "Map" => {
                inner = [args.first().copied(), args.get(1).copied()];
                KIND_MAP
            }
            TyKind::Obj(n, args) if n == "Set" => {
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
                let did = self.typedesc(t);
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
        if let Some(&(_, eq, hash)) = m.desc_glue.iter().find(|(t, _, _)| *t == ty) {
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

    /// A static `String` object for literal `i`.
    pub fn str_lit(&mut self, i: u32) -> DataId {
        if let Some(id) = self.strs.get(&i) {
            return *id;
        }
        let s = &self.m.strings[i as usize];
        let mut bytes = vec![0u8; STR_DATA_OFFSET];
        bytes[0..8].copy_from_slice(&STATIC_RC.to_le_bytes());
        bytes[16..24].copy_from_slice(&(s.len() as u64).to_le_bytes());
        bytes[24..32].copy_from_slice(&(s.chars().count() as u64).to_le_bytes());
        bytes.extend_from_slice(s.as_bytes());
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

pub fn compile(m: &Module, opts: &Options) -> Result<crate::Parts, Error> {
    let isa_builder = cranelift_native::builder().map_err(|e| e.to_string())?;
    compile_with_isa(m, opts, isa_builder)
}

fn compile_with_isa(
    m: &Module,
    opts: &Options,
    isa_builder: cranelift_codegen::isa::Builder,
) -> Result<crate::Parts, Error> {
    let arm64_coff = windows_arm64(isa_builder.triple());
    let mut flags = settings::builder();
    flags
        .set("opt_level", opts.opt_level)
        .map_err(|e| e.to_string())?;
    // Cranelift's ARM64 COFF writer supports absolute addresses, but not GOT or
    // ADRP data relocations. The PE linker records these absolute addresses in
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
    let isa = isa_builder
        .finish(settings::Flags::new(flags))
        .map_err(|e| e.to_string())?;
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
        glue: HashMap::new(),
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
        llvm_funcs: Vec::new(),
        pinned: HashSet::new(),
        anchor: None,
        llvm: opts.llvm.map(|_| {
            let files = m
                .files
                .iter()
                .map(|p| (!p.is_empty() && !p.contains('\0')).then(|| p.clone()))
                .collect();
            let cwd = std::env::current_dir()
                .map_or_else(|_| ".".into(), |d| d.to_string_lossy().into_owned());
            crate::llvm_ir::LlvmModule::new(files, cwd)
        }),
    };
    for (i, f) in m.funcs.iter().enumerate() {
        let sig = g.func_sig(f);
        let exported =
            f.linkage == ms_mir::ir::Linkage::Export || m.entry.is_some_and(|e| e.index() == i);
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
    if opts.llvm.is_some() && internalize(g.module.isa().triple()) {
        let sig = g.module.make_signature();
        let id = g
            .module
            .declare_function(crate::llvm_ir::TEXT_ANCHOR, Linkage::Import, &sig)
            .map_err(|e| e.to_string())?;
        g.anchor = Some(id);
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
        let copy = g.glue(Glue::BlockCopy, vt.data_ty);
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
    let mut ctx = Context::new();
    let mut fctx = FunctionBuilderContext::new();
    for (i, f) in m.funcs.iter().enumerate() {
        ctx.clear();
        ctx.func.signature = g.func_sig(f);
        ctx.func.name = UserFuncName::user(0, g.funcs[i].as_u32());
        {
            let mut l = Lower::new(&mut g, &mut ctx.func, &mut fctx);
            l.lower_func(f);
            if let Some(u) = l.unsupported.clone() {
                return Err(Error(format!("{}: unsupported: {u}", f.name)));
            }
            l.finish();
        }
        let fid = g.funcs[i];
        define_with(&mut g, &mut ctx, fid, &f.name, Some(f))?;
    }
    while let Some((kind, ty)) = g.queue.pop() {
        let id = g.glue[&(kind, ty)];
        ctx.clear();
        let leaves = g.lay.leaves(ty);
        ctx.func.signature = match kind {
            Glue::Drop => g.sig(&leaves, &[]),
            Glue::Copy => g.sig(&leaves, &leaves),
            Glue::BlockCopy => g.sig(&[Leaf::I64], &[Leaf::I64]),
            Glue::SlotCopy => g.sig(&[Leaf::I64, Leaf::I64], &[]),
            _ => g.sig(&[Leaf::I64], &[]),
        };
        ctx.func.name = UserFuncName::user(0, id.as_u32());
        {
            let mut l = Lower::new(&mut g, &mut ctx.func, &mut fctx);
            l.lower_glue(kind, ty);
            l.finish();
        }
        define(&mut g, &mut ctx, id, "glue")?;
    }
    let triple = llvm_triple(g.module.isa().triple());
    let mut llvm_object = None;
    if let Some(llvm) = g.llvm.take() {
        let syms = ModuleSymbols(&g.module, &g.locs, &g.scopes);
        let pinned = g.pinned.iter().map(|id| syms.symbol_of(*id)).collect();
        let anchored = g.anchor.is_some();
        let obj = crate::llvm_obj::compile(
            &llvm.finish(&triple, &pinned, anchored),
            opts.llvm.unwrap_or("3"),
        )?;
        let t = crate::llvm_tables::read(obj.path(), &g.llvm_funcs, &m.files, anchored)?;
        g.dbg = t.dbg;
        g.scopes = t.scopes;
        llvm_object = Some(obj);
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
        relocate_tables(&mut product, &g.dbg, g.anchor, &t);
    }
    if let Some(obj) = llvm_object {
        return Ok(crate::Parts {
            object: product.emit().map_err(|e| Error(e.to_string()))?,
            llvm: Some(obj.bytes()?),
        });
    }
    crate::dwarf::emit(&mut product, m, &g.dbg, endian)?;
    Ok(crate::Parts {
        object: product.emit().map_err(|e| Error(e.to_string()))?,
        llvm: None,
    })
}

/// The target triple of the LLVM IR. Windows executables link over the mingw-w64 CRT, so the code
/// must follow its conventions rather than MSVC's.
fn llvm_triple(triple: &target_lexicon::Triple) -> String {
    if triple.operating_system != target_lexicon::OperatingSystem::Windows {
        return triple.to_string();
    }
    format!("{}-w64-windows-gnu", triple.architecture)
}

/// Whether LLVM-built functions may be internal, with the tables addressing them from an anchor.
/// Mach-O links with `-dead_strip` and one atom per function, so offsets within the object's code
/// do not survive the link; COFF linkers reject the undefined symbol that the Cranelift object
/// declares for each function it never references. Both keep a visible symbol per function.
fn internalize(triple: &target_lexicon::Triple) -> bool {
    triple.binary_format == target_lexicon::BinaryFormat::Elf
}

fn windows_arm64(triple: &target_lexicon::Triple) -> bool {
    triple.operating_system == target_lexicon::OperatingSystem::Windows
        && matches!(
            triple.architecture,
            target_lexicon::Architecture::Aarch64(_)
        )
}

/// Layout facts of the emitted `ms.tables` blob needed to relocate it after `finish`.
struct Tables {
    id: DataId,
    funcs_at: usize,
    lines_at: usize,
    line_scopes_at: usize,
    scopes_at: usize,
    strings_at: usize,
    /// `(entry offset in blob, function index in dbg, code offset)`; the relocation target for each pc.
    pcs: Vec<(usize, usize, u32)>,
}

const TABLES_HEADER: usize = 80;
const SCOPE_ENTRY: usize = 16;
const FUNC_ENTRY: usize = 24;
const LINE_ENTRY: usize = 16;

/// Builds the symbol and line tables handed to `msrt_start` (`crates/ms-rt/ABI.md`).
/// Absolute addresses are zero here and filled by relocations in [`relocate_tables`].
fn emit_tables(g: &mut Gen) -> Result<Tables, Error> {
    let mut strings: Vec<u8> = Vec::new();
    let mut intern = |s: &str| -> u32 {
        let at = strings.len() as u32;
        strings.extend_from_slice(s.as_bytes());
        strings.push(0);
        at
    };
    let files: Vec<u32> = g.m.files.iter().map(|f| intern(f)).collect();
    let file_off = |f: u32| files.get(f as usize).copied().unwrap_or(u32::MAX);
    let mut order: Vec<usize> = (0..g.dbg.len()).collect();
    order.sort_by_key(|i| g.dbg[*i].id.as_u32());
    let names: Vec<u32> = g.dbg.iter().map(|d| intern(&d.name)).collect();
    let scope_names: Vec<u32> = g.scopes.iter().map(|sc| intern(&sc.name)).collect();
    let nlines: usize = g.dbg.iter().map(|d| d.ranges.len()).sum();
    let funcs_at = TABLES_HEADER;
    let lines_at = funcs_at + g.dbg.len() * FUNC_ENTRY;
    let line_scopes_at = lines_at + nlines * LINE_ENTRY;
    let scopes_at = (line_scopes_at + nlines * 4).next_multiple_of(8);
    let strings_at = scopes_at + g.scopes.len() * SCOPE_ENTRY;
    let mut blob = vec![0u8; strings_at + strings.len()];
    blob[0..4].copy_from_slice(&3u32.to_le_bytes()); // ms-rt ABI_VERSION
    blob[72..80].copy_from_slice(&(g.scopes.len() as u64).to_le_bytes());
    blob[16..24].copy_from_slice(&(g.dbg.len() as u64).to_le_bytes());
    blob[32..40].copy_from_slice(&(nlines as u64).to_le_bytes());
    blob[48..56].copy_from_slice(&(strings.len() as u64).to_le_bytes());
    for (n, sc) in g.scopes.iter().enumerate() {
        let at = scopes_at + n * SCOPE_ENTRY;
        blob[at..at + 4].copy_from_slice(&scope_names[n].to_le_bytes());
        blob[at + 4..at + 8].copy_from_slice(&file_off(sc.file).to_le_bytes());
        blob[at + 8..at + 12].copy_from_slice(&sc.parent.to_le_bytes());
        blob[at + 12..at + 16].copy_from_slice(&sc.call_line.to_le_bytes());
    }
    blob[strings_at..].copy_from_slice(&strings);
    let mut pcs = Vec::new();
    let mut at_line = lines_at;
    for (n, d) in g.dbg.iter().enumerate() {
        let at = funcs_at + n * FUNC_ENTRY;
        pcs.push((at, n, 0));
        blob[at + 8..at + 12].copy_from_slice(&d.size.to_le_bytes());
        blob[at + 12..at + 16].copy_from_slice(&names[n].to_le_bytes());
        blob[at + 16..at + 20].copy_from_slice(&file_off(d.file).to_le_bytes());
        blob[at + 20..at + 24].copy_from_slice(&d.line.to_le_bytes());
        for &(off, file, line, scope) in &d.ranges {
            // The runtime resolves a pc to the last entry at or before it.
            pcs.push((at_line, n, off));
            blob[at_line + 8..at_line + 12].copy_from_slice(&line.to_le_bytes());
            blob[at_line + 12..at_line + 16].copy_from_slice(&file_off(file).to_le_bytes());
            let ls = line_scopes_at + (at_line - lines_at) / LINE_ENTRY * 4;
            blob[ls..ls + 4].copy_from_slice(&scope.to_le_bytes());
            at_line += LINE_ENTRY;
        }
    }
    let id = g
        .module
        .declare_data("ms.tables", Linkage::Local, true, false)
        .map_err(|e| e.to_string())?;
    let mut desc = DataDescription::new();
    desc.define(blob.into_boxed_slice());
    desc.set_align(8);
    g.module.define_data(id, &desc).map_err(|e| e.to_string())?;
    g.tables = Some(id);
    Ok(Tables {
        id,
        funcs_at,
        lines_at,
        line_scopes_at,
        scopes_at,
        strings_at,
        pcs,
    })
}

/// Adds the absolute relocations that point the tables at code and at themselves.
fn relocate_tables(
    product: &mut cranelift_object::ObjectProduct,
    dbg: &[FuncDbg],
    anchor: Option<FuncId>,
    t: &Tables,
) {
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
    // LLVM-built functions have no visible symbol: they are addressed from the anchor.
    let syms: Vec<_> = t
        .pcs
        .iter()
        .map(|p| match anchor {
            Some(a) => (product.function_symbol(a), dbg[p.1].text as i64),
            None => (product.function_symbol(dbg[p.1].id), 0),
        })
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
    add(8, own, t.funcs_at as i64);
    add(24, own, t.lines_at as i64);
    add(40, own, t.strings_at as i64);
    add(56, own, t.line_scopes_at as i64);
    add(64, own, t.scopes_at as i64);
    for (&(at, _, off), (sym, base)) in t.pcs.iter().zip(syms) {
        add(at, sym, base + off as i64);
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
    if g.opts.dump_clif {
        eprintln!("; {name}\n{}", ctx.func.display());
    }
    if let Some(mut llvm) = g.llvm.take() {
        let sym = ModuleSymbols(&g.module, &g.locs, &g.scopes).symbol_of(id);
        let exported = g.module.declarations().get_function_decl(id).linkage == Linkage::Import
            && !sym.contains('#')
            && !sym.starts_with("ms.glue.");
        let (display, fn_loc) = match source {
            Some(f) if f.loc.file != u32::MAX => (f.name.as_str(), (f.loc.file, f.loc.line)),
            Some(f) => (f.name.as_str(), (0, f.loc.line)),
            None => (name, (0, 0)),
        };
        llvm.add_function(
            &sym,
            display,
            fn_loc,
            &ctx.func,
            &ModuleSymbols(&g.module, &g.locs, &g.scopes),
            exported,
        );
        if let Some(f) = source {
            g.llvm_funcs.push(LlvmFn {
                id,
                symbol: sym.clone(),
                name: f.name.clone(),
                file: f.loc.file,
                line: f.loc.line,
            });
        }
        g.llvm = Some(llvm);
        g.module.clear_context(ctx);
        return Ok(());
    }
    if g.opts.opt_level != "none" {
        crate::spill::spill_loop_cold(&mut ctx.func);
    }
    g.module
        .define_function(id, ctx)
        .map_err(|e| Error(format!("{name}: {e:?}")))?;
    if let Some(f) = source {
        let cc = ctx.compiled_code().expect("function compiled");
        let mut ranges: Vec<(u32, u32, u32, u32)> = Vec::new();
        let mut dwarf_ranges = Vec::new();
        for r in cc.buffer.get_srclocs_sorted() {
            let bits = r.loc.bits();
            let Some((file, line, scope)) = g.locs.get(bits as usize).copied() else {
                continue;
            };
            if r.start < r.end {
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
        let (file, line) = if f.loc.is_none() {
            let first = ranges.iter().map(|r| r.1).find(|f| *f != u32::MAX);
            (first.unwrap_or(u32::MAX), 0)
        } else {
            (f.loc.file, f.loc.line)
        };
        g.dbg.push(FuncDbg {
            id,
            name: f.name.clone(),
            file,
            line,
            size: cc.code_buffer().len() as u32,
            ranges,
            dwarf_ranges,
            text: 0,
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
    {
        let mut l = Lower::new(g, &mut ctx.func, fctx);
        l.lower_main(entry.index());
        l.finish();
    }
    let llvm = g.llvm.take();
    let r = define(g, ctx, id, "main");
    g.llvm = llvm;
    r
}

#[cfg(test)]
mod target_tests {
    use super::*;

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
                    let parts = compile_with_isa(&m, &opts, isa)
                        .unwrap_or_else(|e| panic!("{} {target} {level:?}: {e}", path.display()));
                    assert!(
                        parts.object.starts_with(magic),
                        "{} {target}",
                        path.display()
                    );
                    assert!(parts.llvm.is_none());
                }
            }
        }
    }
}
