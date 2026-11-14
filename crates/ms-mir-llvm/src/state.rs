//! The module being emitted: symbol names, the glue queue, and the data the code addresses
//! (descriptors, vtables, globals, shared enum blocks). The functions refer to all of it by symbol,
//! so the backend defines it in the same LLVM module and needs nothing from any other backend.

use crate::llvm_ir::{LlvmModule, Symbols};
use crate::{FuncInfo, Glue, Options};
use ms_mir::ir::{Func, Module, Scope};
use ms_mir::layout::{Layouts, Leaf};
use ms_mir::types::{AltId, Native, Ty, TyKind};
use std::collections::{HashMap, HashSet};
use std::fmt::Write as _;

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

/// The `(file, line, scope)` triples and inlined scopes the functions' locations resolve to.
#[derive(Default)]
pub(crate) struct Locs {
    locs: Vec<(u32, u32, u32)>,
    ids: HashMap<(u32, u32, u32), u32>,
    scopes: Vec<Scope>,
    scope_base: u32,
}

impl Locs {
    /// Makes the inlined-callee scopes of `f` module-wide and sets the base for [`Locs::bits`].
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

    /// The source-location value of a MIR location (`!0` when unknown).
    pub fn bits(&mut self, loc: ms_mir::ir::Loc) -> u32 {
        if loc.is_none() || loc.line == 0 {
            return !0;
        }
        let scope = if loc.scope == 0 {
            0
        } else {
            self.scope_base + loc.scope
        };
        let key = (loc.file, loc.line, scope);
        if let Some(i) = self.ids.get(&key) {
            return *i;
        }
        let i = self.locs.len() as u32;
        self.locs.push(key);
        self.ids.insert(key, i);
        i
    }
}

impl Symbols for Locs {
    fn loc(&self, bits: u32) -> Option<(u32, u32, u32)> {
        self.locs.get(bits as usize).copied()
    }

    fn scope(&self, idx: u32) -> Option<(String, u32, u32, u32)> {
        let sc = self.scopes.get((idx as usize).checked_sub(1)?)?;
        Some((sc.name.clone(), sc.file, sc.parent, sc.call_line))
    }
}

pub(crate) struct Gen<'m> {
    pub m: &'m Module,
    pub lay: Layouts<'m>,
    pub opts: Options,
    /// The module under construction; taken while a function is being written.
    pub llvm: Option<LlvmModule>,
    /// Data definitions (symbol, `@"symbol" = ...` line) and vtables (symbol, slot symbols), and
    /// data symbols the descriptors name, handed to the module once emission is done.
    pub data_defs: Vec<(String, String)>,
    pub vtable_defs: Vec<(String, Vec<String>)>,
    pub data_refs: Vec<String>,
    /// Linkage symbol of each MIR function.
    pub syms: Vec<String>,
    /// Glue symbols by kind and type, in creation order (the serial in the name).
    glue: HashMap<(Glue, Ty), String>,
    pub queue: Vec<(Glue, Ty)>,
    desc: HashMap<Ty, String>,
    unit_blocks: HashMap<(AltId, usize), String>,
    pub vtables: Vec<String>,
    pub globals: Vec<String>,
    /// Functions that use the native LLVM calling convention (see `program::native_functions`).
    pub native: HashSet<usize>,
    pub locs: Locs,
    /// Functions and glue the emitter could not write, one line each.
    pub unsupported: Vec<String>,
    /// Every function defined, in table order.
    pub funcs: Vec<FuncInfo>,
}

impl<'m> Gen<'m> {
    pub fn new(m: &'m Module, opts: &Options) -> Self {
        let files = m
            .files
            .iter()
            .map(|p| (!p.is_empty() && !p.contains('\0')).then(|| p.clone()))
            .collect();
        let cwd = std::env::current_dir()
            .map_or_else(|_| ".".into(), |d| d.to_string_lossy().into_owned());
        let mut llvm = LlvmModule::new(files, cwd);
        llvm.heap_facts = opts.heap_facts;
        let syms = m
            .funcs
            .iter()
            .enumerate()
            .map(|(i, f)| {
                if m.entry.is_some_and(|e| e.index() == i) {
                    ENTRY_SYMBOL.to_string()
                } else if f.linkage == ms_mir::ir::Linkage::Export {
                    f.name.clone()
                } else {
                    format!("{}#{i}", sym_safe(&f.name))
                }
            })
            .collect();
        Gen {
            m,
            lay: Layouts::new(m),
            opts: opts.clone(),
            llvm: Some(llvm),
            data_defs: Vec::new(),
            vtable_defs: Vec::new(),
            data_refs: Vec::new(),
            syms,
            glue: HashMap::new(),
            queue: Vec::new(),
            desc: HashMap::new(),
            unit_blocks: HashMap::new(),
            vtables: Vec::new(),
            globals: Vec::new(),
            native: HashSet::new(),
            locs: Locs::default(),
            unsupported: Vec::new(),
            funcs: Vec::new(),
        }
    }

    /// Whether MIR function `i` is part of the program's external interface.
    pub fn is_public(&self, i: usize) -> bool {
        self.m.funcs[i].linkage == ms_mir::ir::Linkage::Export
            || self.m.entry.is_some_and(|e| e.index() == i)
    }

    /// The linkage symbol of MIR function `f`.
    pub fn func_symbol(&self, f: usize) -> String {
        self.syms[f].clone()
    }

    /// The symbol of the glue function of `kind` for `ty`, queued for generation.
    pub fn glue_symbol(&mut self, kind: Glue, ty: Ty) -> String {
        if let Some(s) = self.glue.get(&(kind, ty)) {
            return s.clone();
        }
        let name = format!(
            "{}{}.{}",
            crate::GLUE_PREFIX,
            self.glue.len(),
            kind.suffix()
        );
        self.glue.insert((kind, ty), name.clone());
        self.queue.push((kind, ty));
        name
    }

    /// The symbol of glue already requested.
    pub fn existing_glue(&self, kind: Glue, ty: Ty) -> String {
        self.glue[&(kind, ty)].clone()
    }

    /// Defines a data object in the module.
    fn define(&mut self, name: &str, def: String) {
        self.data_defs.push((name.to_string(), def));
    }

    /// Defines the global variables and vtables, which functions address by index.
    pub fn define_statics(&mut self) {
        for (i, gl) in self.m.globals.iter().enumerate() {
            let name = format!("ms.global.{i}.{}", sym_safe(&gl.name));
            let size = self.lay.mem(gl.ty).size.max(8);
            self.define(
                &name,
                format!("@\"{name}\" = hidden global [{size} x i8] zeroinitializer, align 8"),
            );
            self.globals.push(name);
        }
        // Slot 0 is the payload block destructor, the methods follow, then the payload copier.
        for (i, vt) in self.m.vtables.iter().enumerate() {
            let name = format!("ms.vtable.{i}.{}", sym_safe(&vt.name));
            let mut slots = vec![self.glue_symbol(Glue::BlockDrop, vt.data_ty)];
            slots.extend(vt.methods.iter().map(|f| self.func_symbol(f.index())));
            slots.push(self.glue_symbol(Glue::BlockClone, vt.data_ty));
            self.vtable_defs.push((name.clone(), slots));
            self.vtables.push(name);
        }
    }

    /// The symbol of the shared block of payloadless case `case` of boxed alternative `alt`: `size`
    /// zero bytes with the tag stored first. Such values never allocate, and dropping them frees
    /// nothing.
    pub fn unit_block_symbol(&mut self, alt: AltId, case: usize, size: usize) -> String {
        if let Some(s) = self.unit_blocks.get(&(alt, case)) {
            return s.clone();
        }
        let name = format!("ms.unit.{}", self.unit_blocks.len());
        let mut bytes = vec![0u8; size.max(8)];
        bytes[0..8].copy_from_slice(&(case as u64).to_le_bytes());
        self.define(
            &name,
            format!(
                "@\"{name}\" = hidden constant [{} x i8] c\"{}\", align 8",
                bytes.len(),
                escape_bytes(&bytes)
            ),
        );
        self.unit_blocks.insert((alt, case), name.clone());
        name
    }

    /// The symbol of the static `TypeDesc` for slots of type `ty` (`crates/ms-rt/ABI.md`,
    /// section 5).
    pub fn typedesc_symbol(&mut self, ty: Ty) -> String {
        use ms_rt_abi::{
            DESC_COPY_OFFSET, DESC_DROP_OFFSET, DESC_EQ_OFFSET, DESC_HASH_OFFSET,
            DESC_INNER0_OFFSET, DESC_INNER1_OFFSET, DESC_SIZE, KIND_CUSTOM, KIND_LIST, KIND_MAP,
            KIND_POD, KIND_SET, KIND_SHARED,
        };
        if let Some(s) = self.desc.get(&ty) {
            return s.clone();
        }
        let m = self.m;
        // A scoped key names the same layout with the glue of one module's local implementations.
        let (key, scope) = (ty, ty.scope());
        let ty = ty.unscoped();
        let builtin = match m.types.kind(ty) {
            // `Int8`..`Int32` and `UInt8`..`UInt64` are plain bits of their width and take the
            // `POD` path below.
            TyKind::Int => Some("msrt_desc_int"),
            TyKind::Float => Some("msrt_desc_float"),
            TyKind::Float32 => Some("msrt_desc_float32"),
            TyKind::Bool => Some("msrt_desc_bool"),
            TyKind::Str => Some("msrt_desc_string"),
            TyKind::Bytes => Some("msrt_desc_bytes"),
            _ => None,
        };
        if let Some(name) = builtin {
            self.desc.insert(key, name.to_string());
            return name.to_string();
        }
        let name = format!("ms.desc.{}", self.desc.len());
        self.desc.insert(key, name.clone());
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
        // The descriptor is words: size and alignment, the kind, then addresses.
        let mut words = vec![String::from("i64 0"); DESC_SIZE / 8];
        let head = u64::from(mem.size) | u64::from(mem.align) << 32;
        words[0] = format!("i64 {}", head as i64);
        words[1] = format!("i64 {kind}");
        let addr = |sym: &str| format!("i64 ptrtoint (ptr @\"{sym}\" to i64)");
        for (k, t) in inner.into_iter().enumerate() {
            if let Some(t) = t {
                let sym = self.typedesc_symbol(t.scoped(scope));
                self.data_refs.push(sym.clone());
                words[[DESC_INNER0_OFFSET, DESC_INNER1_OFFSET][k] / 8] = addr(&sym);
            }
        }
        if with_glue {
            let drop = self.glue_symbol(Glue::SlotDrop, ty);
            let copy = self.glue_symbol(Glue::SlotCopy, ty);
            words[DESC_DROP_OFFSET / 8] = addr(&drop);
            words[DESC_COPY_OFFSET / 8] = addr(&copy);
        }
        // The scope's own glue, else the unscoped one.
        let glue = m
            .desc_glue
            .iter()
            .find(|(t, _, _)| *t == key)
            .or_else(|| m.desc_glue.iter().find(|(t, _, _)| *t == ty));
        if let Some(&(_, eq, hash)) = glue {
            words[DESC_EQ_OFFSET / 8] = addr(&self.func_symbol(eq.index()));
            words[DESC_HASH_OFFSET / 8] = addr(&self.func_symbol(hash.index()));
        }
        let mut def = String::new();
        let _ = write!(
            def,
            "@\"{name}\" = hidden constant [{} x i64] [{}], align 8",
            words.len(),
            words.join(", ")
        );
        self.define(&name, def);
        name
    }

    /// The flattened parameter leaves of a function.
    pub fn param_leaves(&self, f: &Func) -> Vec<Leaf> {
        f.params
            .iter()
            .flat_map(|p| self.lay.leaves(p.ty))
            .collect()
    }
}

/// The symbol of the program's entry function.
pub const ENTRY_SYMBOL: &str = "ms_entry";

/// An LLVM quoted byte string body (`c"..."`).
fn escape_bytes(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 3);
    for b in bytes {
        let _ = write!(s, "\\{b:02X}");
    }
    s
}
