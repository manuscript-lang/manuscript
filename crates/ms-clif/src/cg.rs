//! Module-level code generation state: function declarations, runtime imports,
//! static data, and the glue functions (drop, copy) generated on demand.

use crate::layout::{Layouts, Leaf};
use crate::lower::Lower;
use crate::{Error, Options};
use cranelift_codegen::ir::{self, types, AbiParam, Signature, UserFuncName};
use cranelift_codegen::settings::{self, Configurable};
use cranelift_codegen::Context;
use cranelift_frontend::FunctionBuilderContext;
use cranelift_module::{default_libcall_names, DataDescription, DataId, FuncId, Linkage, Module as _};
use cranelift_object::{ObjectBuilder, ObjectModule};
use ms_mir::ir::{ExtId, Func, FuncKind, Module};
use ms_mir::types::{Ty, TyKind};
use std::collections::HashMap;

/// `rc` of static objects (`ms_rt_abi::STATIC_RC`).
pub const STATIC_RC: u64 = 1 << 62;
/// `ms_rt_abi::STR_DATA_OFFSET`.
pub const STR_DATA_OFFSET: usize = 32;
/// Size of the object header.
pub const OBJ_HEADER: u32 = 16;
/// Offset of `code` in a closure object.
pub const CLOSURE_CODE: i32 = 16;
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
    /// `fn(arg: *mut u8)` thunk used by cleanup.push; key carries the closer function.
    CleanupThunk(u32),
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
];

/// Runtime data symbols: `(name, is_writable)`.
const RT_DATA: &[(&str, bool)] = &[("msrt_cancel_flag", false), ("msrt_call_depth", true)];

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
    pub descs: HashMap<Ty, DataId>,
}

impl<'m> Gen<'m> {
    pub fn sig(&self, params: &[Leaf], rets: &[Leaf]) -> Signature {
        let mut sig = self.module.make_signature();
        sig.params.extend(params.iter().map(|l| AbiParam::new(leaf_type(*l))));
        sig.returns.extend(rets.iter().map(|l| AbiParam::new(leaf_type(*l))));
        sig
    }

    /// Flattened parameter leaves of a function.
    pub fn param_leaves(&self, f: &Func) -> Vec<Leaf> {
        f.params.iter().flat_map(|p| self.lay.leaves(p.ty)).collect()
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
        let (_, p, r) = RT.iter().find(|e| e.0 == name).unwrap_or_else(|| panic!("unknown runtime function {name}"));
        let mut sig = self.module.make_signature();
        sig.params.extend(p.chars().map(|c| AbiParam::new(clif_type(c))));
        sig.returns.extend(r.chars().map(|c| AbiParam::new(clif_type(c))));
        let id = self.module.declare_function(name, Linkage::Import, &sig).expect("declare runtime function");
        self.rt.insert(name, id);
        id
    }

    /// The runtime data symbol `name`.
    pub fn rt_data(&mut self, name: &'static str) -> DataId {
        if let Some(id) = self.rt_data.get(name) {
            return *id;
        }
        let writable = RT_DATA.iter().find(|e| e.0 == name).unwrap_or_else(|| panic!("unknown runtime data {name}")).1;
        let id = self.module.declare_data(name, Linkage::Import, writable, false).expect("declare runtime data");
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
            Glue::ClosureDrop(_) | Glue::BlockDrop | Glue::CleanupThunk(_) => self.sig(&[Leaf::I64], &[]),
        };
        let name = format!("ms.glue.{}.{}", self.glue.len(), match kind {
            Glue::Drop => "drop",
            Glue::Copy => "copy",
            Glue::ClosureDrop(_) => "closure_drop",
            Glue::BlockDrop => "block_drop",
            Glue::CleanupThunk(_) => "cleanup_thunk",
        });
        let id = self.module.declare_function(&name, Linkage::Local, &sig).expect("declare glue");
        self.glue.insert((kind, ty), id);
        self.queue.push((kind, ty));
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
        let id = self.module.declare_data(&format!("ms.str.{i}"), Linkage::Local, true, false).expect("declare string");
        let mut d = DataDescription::new();
        d.define(bytes.into_boxed_slice());
        d.set_align(16);
        self.module.define_data(id, &d).expect("define string");
        self.strs.insert(i, id);
        id
    }
}

pub fn compile(m: &Module, opts: &Options) -> Result<Vec<u8>, Error> {
    let mut flags = settings::builder();
    flags.set("opt_level", opts.opt_level).map_err(|e| e.to_string())?;
    flags.set("is_pic", "true").map_err(|e| e.to_string())?;
    flags.set("preserve_frame_pointers", "true").map_err(|e| e.to_string())?;
    flags.set("enable_multi_ret_implicit_sret", "true").map_err(|e| e.to_string())?;
    flags.set("unwind_info", "false").map_err(|e| e.to_string())?;
    let isa = cranelift_native::builder().map_err(|e| e.to_string())?.finish(settings::Flags::new(flags)).map_err(|e| e.to_string())?;
    let builder = ObjectBuilder::new(isa, m.name.as_str(), default_libcall_names()).map_err(|e| e.to_string())?;
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
        descs: HashMap::new(),
    };
    for (i, f) in m.funcs.iter().enumerate() {
        let sig = g.func_sig(f);
        let exported = f.linkage == ms_mir::ir::Linkage::Export || m.entry.is_some_and(|e| e.index() == i);
        let is_entry = m.entry.is_some_and(|e| e.index() == i);
        let name = if is_entry { "ms_entry".to_string() } else if exported { f.name.clone() } else { format!("{}#{i}", f.name) };
        let id = g.module.declare_function(&name, if exported { Linkage::Export } else { Linkage::Local }, &sig).map_err(|e| e.to_string())?;
        g.funcs.push(id);
    }
    for (i, gl) in m.globals.iter().enumerate() {
        let mem = g.lay.mem(gl.ty);
        let id = g.module.declare_data(&format!("ms.global.{i}.{}", gl.name), Linkage::Local, true, false).map_err(|e| e.to_string())?;
        let mut d = DataDescription::new();
        d.define_zeroinit(mem.size.max(8) as usize);
        d.set_align(8);
        g.module.define_data(id, &d).map_err(|e| e.to_string())?;
        g.globals.push(id);
    }
    // Vtables are defined after functions are declared: slot 0 is the payload block destructor.
    for (i, vt) in m.vtables.iter().enumerate() {
        let id = g.module.declare_data(&format!("ms.vtable.{i}.{}", vt.name), Linkage::Local, false, false).map_err(|e| e.to_string())?;
        g.vtables.push(id);
        let drop = g.glue(Glue::BlockDrop, vt.data_ty);
        let mut d = DataDescription::new();
        d.define(vec![0u8; 8 * (1 + vt.methods.len())].into_boxed_slice());
        d.set_align(8);
        let r = g.module.declare_func_in_data(drop, &mut d);
        d.write_function_addr(0, r);
        for (k, mf) in vt.methods.iter().enumerate() {
            let r = g.module.declare_func_in_data(g.funcs[mf.index()], &mut d);
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
            l.lower_func(f, i);
            if let Some(u) = l.unsupported.clone() {
                return Err(Error(format!("{}: unsupported: {u}", f.name)));
            }
            l.finish();
        }
        let fid = g.funcs[i];
        define(&mut g, &mut ctx, fid, &f.name)?;
    }
    while let Some((kind, ty)) = g.queue.pop() {
        let id = g.glue[&(kind, ty)];
        ctx.clear();
        let leaves = g.lay.leaves(ty);
        ctx.func.signature = match kind {
            Glue::Drop => g.sig(&leaves, &[]),
            Glue::Copy => g.sig(&leaves, &leaves),
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
    emit_main(&mut g, &mut ctx, &mut fctx)?;
    let product = g.module.finish();
    product.emit().map_err(|e| Error(e.to_string()))
}

fn define(g: &mut Gen, ctx: &mut Context, id: FuncId, name: &str) -> Result<(), Error> {
    if g.opts.dump_clif {
        eprintln!("; {name}\n{}", ctx.func.display());
    }
    g.module.define_function(id, ctx).map_err(|e| Error(format!("{name}: {e:?}")))?;
    g.module.clear_context(ctx);
    Ok(())
}

/// Emits the C `main(argc, argv)` that hands the entry function to the runtime.
fn emit_main(g: &mut Gen, ctx: &mut Context, fctx: &mut FunctionBuilderContext) -> Result<(), Error> {
    let Some(entry) = g.m.entry else { return Ok(()) };
    let mut sig = g.module.make_signature();
    sig.params.push(AbiParam::new(types::I32));
    sig.params.push(AbiParam::new(types::I64));
    sig.returns.push(AbiParam::new(types::I32));
    let id = g.module.declare_function("main", Linkage::Export, &sig).map_err(|e| e.to_string())?;
    ctx.clear();
    ctx.func.signature = sig;
    ctx.func.name = UserFuncName::user(0, id.as_u32());
    {
        let mut l = Lower::new(g, &mut ctx.func, fctx);
        l.lower_main(entry.index());
        l.finish();
    }
    define(g, ctx, id, "main")
}

/// Whether `ty` is a function-kind type (used by callers to pick calling conventions).
pub fn is_closure(m: &Module, ty: Ty) -> bool {
    matches!(m.types.kind(ty), TyKind::Fn(..))
}

/// Whether `f` is the code of a closure.
pub fn is_closure_code(f: &Func) -> bool {
    matches!(f.kind, FuncKind::Closure { .. })
}
