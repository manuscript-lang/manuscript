//! Emits a whole program: every function straight from MIR, the glue they call, and the data they
//! address, into LLVM modules.

use crate::glue_llvm::{self, OwnKind, own_kind};
use crate::llvm_ir::{DirectLocs, NoSymbols};
use crate::mir_llvm::{self, ClosureSyms, Place, Plan};
use crate::state::Gen;
use crate::{Error, FuncInfo, Glue, Options, Program};
use ms_mir::ir::{Func, FuncKind, Imm, Module, Op};
use ms_mir::types::Ty;
use std::collections::{HashMap, HashSet};

/// Bytes of function text per module below which splitting costs more than it saves: each unit
/// parses the debug metadata and cannot inline functions of another.
const UNIT_BYTES: usize = 2 << 20;

/// How many modules to write: `requested`, else one per core up to the size that gives each
/// [`UNIT_BYTES`] of code.
fn llvm_units(requested: Option<usize>, bytes: usize) -> usize {
    if let Some(n) = requested {
        return n.max(1);
    }
    let cores = std::thread::available_parallelism().map_or(1, usize::from);
    (bytes / UNIT_BYTES).clamp(1, cores)
}

/// Emits `m` as LLVM modules. A function or glue the emitter cannot write is an error that lists
/// all of them.
pub fn emit(m: &Module, opts: &Options) -> Result<Program, Error> {
    let mut g = Gen::new(m, opts);
    g.define_statics();
    g.native = native_functions(&g);
    for (i, f) in m.funcs.iter().enumerate() {
        direct_function(&mut g, i, f);
    }
    while let Some((kind, ty)) = g.queue.pop() {
        direct_glue(&mut g, kind, ty);
    }
    if !g.unsupported.is_empty() {
        return Err(Error(format!(
            "the direct LLVM emitter cannot write:\n{}",
            g.unsupported.join("\n")
        )));
    }
    let mut llvm = g.llvm.take().expect("the module is set between functions");
    for (name, def) in std::mem::take(&mut g.data_defs) {
        llvm.define_data(name, def);
    }
    for (name, slots) in std::mem::take(&mut g.vtable_defs) {
        llvm.define_vtable(name, slots);
    }
    for sym in std::mem::take(&mut g.data_refs) {
        llvm.reference_data(&sym);
    }
    let units = llvm_units(opts.units, llvm.code_bytes());
    // Separate objects have no common anchor: every function keeps a symbol.
    let anchored = opts.anchor && units == 1 && !llvm.has_unoptimized();
    let units = llvm.finish_units(&opts.triple, &HashSet::new(), anchored, units);
    Ok(Program {
        units,
        funcs: g.funcs,
        anchored,
    })
}

/// The functions that take and return values in the native LLVM calling convention
/// (`abi_llvm`): aggregates by pointer, large results through a hidden pointer. Such a function
/// has no leaf entry, so every reference to it must be a call from a directly emitted function:
/// the rest of the program (the runtime, closures, vtables, cleanups, exports and the entry) only
/// knows the leaf convention. Its stack-growth shim is written for the native convention too (see
/// [`direct_shim`]).
fn native_functions(g: &Gen) -> HashSet<usize> {
    let m = g.m;
    let n = m.funcs.len();
    // The code of a closure and the methods of a vtable are called by address: they keep the leaf
    // convention, though they call native functions.
    let mut keep: Vec<bool> = m
        .funcs
        .iter()
        .map(|f| matches!(f.kind, FuncKind::Normal))
        .collect();
    let mut clear = |k: usize| keep[k] = false;
    for f in [m.entry.map(|e| e.index())].into_iter().flatten() {
        clear(f);
    }
    for v in &m.vtables {
        v.methods.iter().for_each(|f| clear(f.index()));
    }
    for (_, a, b) in &m.desc_glue {
        clear(a.index());
        clear(b.index());
    }
    for f in m.funcs.iter() {
        f.capture_closers.iter().for_each(|(_, c)| clear(c.index()));
        let others = [
            f.slot_result,
            f.close_exit.map(|c| c.0),
            f.close_exit.map(|c| c.1),
        ];
        others.into_iter().flatten().for_each(|c| clear(c.index()));
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            let Imm::Func(c) = inst.imm else { continue };
            // Any use but a call from a directly emitted function needs the leaf entry.
            if inst.op != Op::Call {
                clear(c.index());
            }
        }
    }
    for i in 0..n {
        if g.is_public(i) {
            clear(i);
        }
    }
    (0..n).filter(|&i| keep[i]).collect()
}

/// Emits `f` straight from MIR. A function `mir_llvm` cannot write is recorded in
/// `Gen::unsupported`, and the build fails with all of them once emission is done.
fn direct_function(g: &mut Gen, i: usize, f: &Func) {
    if let Some(why) = mir_llvm::unsupported(g.m, &g.lay, f) {
        return note_unsupported(g, &f.name, &why);
    }
    // A recursive function's stack-depth check runs it again through its grow shim.
    let grow_shim = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .any(|inst| inst.op == Op::DepthEnter)
        .then(|| g.glue_symbol(Glue::GrowShim(i as u32), Ty::UNIT));
    g.locs.add_scopes(f);
    let mut bits = HashMap::new();
    let locs = f
        .blocks
        .iter()
        .flat_map(|b| b.insts.iter().map(|i| i.loc).chain([b.term_loc]));
    for loc in locs {
        bits.entry(loc).or_insert_with(|| g.locs.bits(loc));
    }
    let sym = g.func_symbol(i);
    let public = g.is_public(i);
    let fn_loc = if f.loc.file != u32::MAX {
        (f.loc.file, f.loc.line)
    } else {
        (0, f.loc.line)
    };
    let plan = direct_plan(g, f);
    let symbol_of = |k: usize| g.syms[k].clone();
    let mut llvm = g.llvm.take().expect("the module is set between functions");
    llvm.add_direct(
        &sym,
        &f.name,
        fn_loc,
        public,
        DirectLocs {
            syms: &g.locs,
            bits: &bits,
        },
        |env| {
            let place = Place {
                idx: i,
                grow_shim,
                native: &g.native,
            };
            mir_llvm::emit(g.m, &g.lay, place, f, &plan, env, &symbol_of)
        },
    );
    g.llvm = Some(llvm);
    g.funcs.push(FuncInfo {
        symbol: sym,
        name: f.name.clone(),
        file: f.loc.file,
        line: f.loc.line,
    });
}

/// Records a function or glue the direct emitter cannot write.
fn note_unsupported(g: &mut Gen, what: &str, why: &str) {
    g.unsupported.push(format!("  {what}: {why}"));
}

/// The glue, descriptors, closures and vtables `f`'s instructions refer to, declared now so that
/// emission can name them: glue is queued for generation like any other.
fn direct_plan(g: &mut Gen, f: &Func) -> Plan {
    let mut plan = Plan {
        checks: g.opts.checks,
        framed_closures: ms_mir::frames::framed_closure_objects(g.m, f),
        framed_ifaces: ms_mir::frames::framed_iface_borrows(g.m, f),
        ..Default::default()
    };
    for bd in &f.blocks {
        for i in &bd.insts {
            match (i.op, i.imm) {
                (Op::Clone | Op::AltOwn | Op::OptUnwrap, _) => {
                    // `opt.unwrap` clones the payload of its operand.
                    let ty = match i.op {
                        Op::OptUnwrap => g.m.opt_inner(f.ty(i.args[0])).expect("an optional"),
                        _ => mir_llvm::cloned_ty(f, i),
                    };
                    plan_clone(g, &mut plan, ty);
                }
                (Op::Drop | Op::DropIf, _) => {
                    let ty = f.ty(i.args[usize::from(i.op == Op::DropIf)]);
                    plan_drop(g, &mut plan, ty);
                }
                (Op::AltRelease | Op::AltUnbox | Op::TypeRelease, _) => {
                    for ty in mir_llvm::released_types(&g.lay, f, i) {
                        plan_drop(g, &mut plan, ty);
                    }
                }
                (
                    Op::ListSet | Op::ListSetNn | Op::ListSetU | Op::ListDropLast | Op::ListRelease,
                    _,
                ) => {
                    if let Some(ty) = g.m.seq_elem(f.ty(i.args[0])) {
                        plan_drop(g, &mut plan, ty);
                    }
                }
                (Op::CleanupPush, Imm::Func(c)) => {
                    let sym = g.glue_symbol(Glue::CleanupThunk(c.0), Ty::UNIT);
                    plan.cleanup.insert(c.index(), sym);
                }
                (Op::TypeDesc, Imm::Ty(t)) => {
                    let sym = g.typedesc_symbol(t);
                    plan.desc.insert(t, sym);
                }
                (Op::ClosureNew, Imm::Func(c)) => {
                    let framed = i
                        .res
                        .is_some_and(|r| plan.framed_closures.contains(&r.index()));
                    let clone = g.glue_symbol(Glue::ClosureClone(c.0), Ty::UNIT);
                    let drop = g.glue_symbol(
                        if framed {
                            Glue::ClosureDropFramed(c.0)
                        } else {
                            Glue::ClosureDrop(c.0)
                        },
                        Ty::UNIT,
                    );
                    plan.closures
                        .insert((c.index(), framed), ClosureSyms { clone, drop });
                }
                (Op::AltNew | Op::AltView, Imm::Case(a, c)) => {
                    let ty = f.ty(i.res.expect("an enum result"));
                    let unit = g.m.alts[a.index()].cases[c as usize].fields.is_empty();
                    if unit
                        && g.lay.is_boxed(a)
                        && let Some(size) = g.lay.boxed_block_size(ty)
                    {
                        let sym = g.unit_block_symbol(a, c as usize, size);
                        plan.units.insert((a.index(), c as usize), sym);
                    }
                }
                (Op::GlobalGet | Op::GlobalSet, Imm::Global(gl)) => {
                    plan.globals
                        .insert(gl.index(), g.globals[gl.index()].clone());
                }
                (Op::IfaceNew | Op::IfaceBorrow | Op::IfaceIs, Imm::Vtable(vt)) => {
                    plan.vtables
                        .insert(vt.index(), g.vtables[vt.index()].clone());
                }
                _ => {}
            }
        }
    }
    plan
}

/// Declares the clone glue of `ty` for the function being planned, when it has some.
fn plan_clone(g: &mut Gen, plan: &mut Plan, ty: Ty) {
    if own_kind(&g.lay, ty) == OwnKind::Glue && !plan.clone.contains_key(&ty) {
        let sym = g.glue_symbol(Glue::Clone, ty);
        plan.clone
            .insert(ty, glue_llvm::target(g, Glue::Clone, ty, sym));
    }
}

/// Declares the drop glue of `ty` for the function being planned, when it has some.
fn plan_drop(g: &mut Gen, plan: &mut Plan, ty: Ty) {
    if own_kind(&g.lay, ty) == OwnKind::Glue && !plan.drop.contains_key(&ty) {
        let sym = g.glue_symbol(Glue::Drop, ty);
        plan.drop
            .insert(ty, glue_llvm::target(g, Glue::Drop, ty, sym));
    }
}

/// Emits the stack-growth shim of the directly emitted function `f`, in its calling convention.
fn direct_shim(g: &mut Gen, kind: Glue, ty: Ty, f: usize, native: bool) {
    let sym = g.existing_glue(kind, ty);
    let callee = g.func_symbol(f);
    let mut llvm = g.llvm.take().expect("the module is set between functions");
    let no_bits = HashMap::new();
    let locs = DirectLocs {
        syms: &NoSymbols,
        bits: &no_bits,
    };
    let (m, lay) = (g.m, &g.lay);
    llvm.add_direct(&sym, "glue", (0, 0), false, locs, |env| {
        let shim = if native {
            mir_llvm::grow_shim
        } else {
            mir_llvm::leaf_grow_shim
        };
        shim(env.types, lay, &m.funcs[f], &callee, env.loc)
    });
    llvm.mark_glue();
    g.llvm = Some(llvm);
    g.funcs.push(glue_info(sym));
}

/// A glue function as the caller's tables list it.
fn glue_info(symbol: String) -> FuncInfo {
    FuncInfo {
        symbol,
        name: "glue".to_string(),
        file: u32::MAX,
        line: 0,
    }
}

/// Emits the closure glue `kind` under its leaf symbol `sym`: the closure header and the runtime
/// call it through a pointer, so it has no native twin.
fn direct_closure_glue(g: &mut Gen, kind: Glue, sym: String) {
    let mut llvm = g.llvm.take().expect("the module is set between functions");
    let no_bits = HashMap::new();
    let locs = DirectLocs {
        syms: &NoSymbols,
        bits: &no_bits,
    };
    llvm.add_direct(&sym, "glue", (0, 0), false, locs, |env| {
        glue_llvm::closure::emit(g, kind, env.types, env.loc)
    });
    llvm.mark_glue();
    g.llvm = Some(llvm);
    g.funcs.push(glue_info(sym));
}

/// Emits the glue `kind` for `ty` straight to LLVM IR, or records it in `Gen::unsupported`.
fn direct_glue(g: &mut Gen, kind: Glue, ty: Ty) {
    if let Glue::GrowShim(f) = kind {
        let f = f as usize;
        let native = g.native.contains(&f);
        if native || mir_llvm::supports(g.m, &g.lay, &g.m.funcs[f]) {
            return direct_shim(g, kind, ty, f, native);
        }
    }
    if !glue_llvm::supports(g, kind, ty) {
        let ty_kind = format!("{:?}", g.m.types.kind(ty));
        let end = ty_kind.find(['(', ' ', '{']).unwrap_or(ty_kind.len());
        return note_unsupported(g, &format!("glue {kind:?}"), &ty_kind[..end]);
    }
    let sym = g.existing_glue(kind, ty);
    if glue_llvm::closure::is_closure(kind) {
        return direct_closure_glue(g, kind, sym);
    }
    let mut llvm = g.llvm.take().expect("the module is set between functions");
    let nat = glue_llvm::native(&sym);
    let no_bits = HashMap::new();
    let locs = DirectLocs {
        syms: &NoSymbols,
        bits: &no_bits,
    };
    llvm.add_direct(&nat, "glue", (0, 0), false, locs, |env| {
        glue_llvm::emit(g, kind, ty, env.types, env.loc)
    });
    llvm.mark_glue();
    let locs = DirectLocs {
        syms: &NoSymbols,
        bits: &no_bits,
    };
    llvm.add_direct(&sym, "glue", (0, 0), false, locs, |env| {
        glue_llvm::thunk(g, kind, ty, &sym, env.types, env.loc)
    });
    llvm.mark_glue();
    g.llvm = Some(llvm);
    g.funcs.push(glue_info(nat));
}
