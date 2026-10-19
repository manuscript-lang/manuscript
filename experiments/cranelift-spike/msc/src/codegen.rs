//! Lowers checked programs to Cranelift and an object file.
//!
//! Values are flattened into scalar SSA variables (see `types`), so records
//! and list headers live in registers. A `mut` parameter is copy-in/copy-out:
//! the callee returns its final value after the result, which exclusivity
//! makes equivalent to passing a reference. Owned locals that need dropping
//! carry a drop flag cleared on move; scope exits and returns drop live
//! values. Int arithmetic is overflow-checked, list indexing is
//! bounds-checked, and every loop polls the cancellation flag.

use crate::check::{Checked, Res};
use crate::syntax::{Arm, BinOp, Block, Expr, ExprKind, FnDecl, Program, StmtKind, UnOp};
use crate::types::{Leaf, Ty};
use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::{self, types, AbiParam, BlockArg, FuncRef, GlobalValue, InstBuilder, MemFlagsData, Signature, StackSlotData, StackSlotKind, TrapCode, UserFuncName, Value};
use cranelift_codegen::settings::{self, Configurable};
use cranelift_codegen::inline::{Inline, InlineCommand};
use cranelift_codegen::Context;
use std::borrow::Cow;
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Variable};
use cranelift_module::{default_libcall_names, DataDescription, DataId, FuncId, Linkage, Module};
use cranelift_object::{ObjectBuilder, ObjectModule};
use std::collections::HashMap;

const FAULT_OVERFLOW: i64 = 0;
const FAULT_DIVZERO: i64 = 1;
const FAULT_BOUNDS: i64 = 2;
const FAULT_CANCELLED: i64 = 3;

pub struct Options {
    pub checks: bool,
    pub poll: bool,
    pub inline: bool,
}

const INLINE_LIMIT: usize = 150;

fn callee_index(func: &ir::Function, callee: FuncRef) -> Option<u32> {
    let ir::ExternalName::User(r) = &func.dfg.ext_funcs[callee].name else { return None };
    Some(func.params.user_named_funcs()[*r].index)
}

/// Whether `func` calls the function with this index.
fn calls(func: &ir::Function, index: u32) -> bool {
    func.dfg.ext_funcs.keys().any(|r| callee_index(func, r) == Some(index))
}

struct Inliner<'a> {
    bodies: &'a HashMap<u32, ir::Function>,
}

impl Inline for Inliner<'_> {
    fn inline(&mut self, caller: &ir::Function, _: ir::Inst, _: ir::Opcode, callee: FuncRef, _: &[Value]) -> InlineCommand<'_> {
        match callee_index(caller, callee).and_then(|i| self.bodies.get(&i)) {
            Some(body) => InlineCommand::Inline { callee: Cow::Borrowed(body), visit_callee: true },
            None => InlineCommand::KeepCall,
        }
    }
}

struct Runtime {
    fault: FuncId,
    alloc: FuncId,
    free: FuncId,
    grow: FuncId,
    map_new: FuncId,
    map_free: FuncId,
    map_get: FuncId,
    map_add: FuncId,
    map_len: FuncId,
    now_us: FuncId,
    report: FuncId,
    cancelled: DataId,
}

struct Gen<'p> {
    ck: &'p Checked,
    opts: Options,
    module: ObjectModule,
    fns: Vec<FuncId>,
    rt: Runtime,
    drops: HashMap<Ty, FuncId>,
    drop_queue: Vec<Ty>,
    strings: HashMap<String, DataId>,
}

fn clif(leaf: Leaf) -> ir::Type {
    match leaf {
        Leaf::I64 => types::I64,
        Leaf::F64 => types::F64,
        Leaf::I8 => types::I8,
    }
}

pub fn compile(prog: &Program, ck: &Checked, opts: Options) -> Result<Vec<u8>, String> {
    let mut flags = settings::builder();
    flags.set("opt_level", "speed").map_err(|e| e.to_string())?;
    flags.set("is_pic", "true").map_err(|e| e.to_string())?;
    flags.set("enable_multi_ret_implicit_sret", "true").map_err(|e| e.to_string())?;
    let isa = cranelift_native::builder()
        .map_err(|e| e.to_string())?
        .finish(settings::Flags::new(flags))
        .map_err(|e| e.to_string())?;
    let builder = ObjectBuilder::new(isa, "ms", default_libcall_names()).map_err(|e| e.to_string())?;
    let mut module = ObjectModule::new(builder);
    let rt = declare_runtime(&mut module)?;
    let mut g = Gen { ck, opts, module, fns: Vec::new(), rt, drops: HashMap::new(), drop_queue: Vec::new(), strings: HashMap::new() };
    for (i, f) in prog.fns.iter().enumerate() {
        let sig = g.fn_sig(i);
        let (name, linkage) = if f.name == "main" { ("ms_main".to_string(), Linkage::Export) } else { (format!("ms_{}", f.name), Linkage::Local) };
        let id = g.module.declare_function(&name, linkage, &sig).map_err(|e| e.to_string())?;
        g.fns.push(id);
    }
    let mut ctx = g.module.make_context();
    let mut fctx = FunctionBuilderContext::new();
    let mut bodies = Vec::new();
    for (i, f) in prog.fns.iter().enumerate() {
        ctx.func.signature = g.fn_sig(i);
        ctx.func.name = UserFuncName::user(0, g.fns[i].as_u32());
        g.lower_fn(&mut ctx, &mut fctx, f, i);
        bodies.push(std::mem::replace(&mut ctx.func, ir::Function::new()));
    }
    // Small non-recursive functions are inlined into their callers.
    let inlinable: HashMap<u32, ir::Function> = bodies
        .iter()
        .zip(&g.fns)
        .filter(|(body, id)| {
            let only_poll_symbol = body.global_values.len() <= 1;
            g.opts.inline && only_poll_symbol && body.dfg.num_insts() <= INLINE_LIMIT && !calls(body, id.as_u32())
        })
        .map(|(body, id)| (id.as_u32(), body.clone()))
        .collect();
    for (i, body) in bodies.into_iter().enumerate() {
        ctx.func = body;
        ctx.inline(Inliner { bodies: &inlinable }).map_err(|e| format!("{}: {e:?}", prog.fns[i].name))?;
        g.define(&mut ctx, g.fns[i], &prog.fns[i].name)?;
    }
    while let Some(ty) = g.drop_queue.pop() {
        let id = g.drops[&ty];
        ctx.func.signature = g.leaf_sig(&g.ck.types.leaves(&ty), &[]);
        ctx.func.name = UserFuncName::user(0, id.as_u32());
        g.lower_drop(&mut ctx, &mut fctx, &ty);
        g.define(&mut ctx, id, "drop")?;
    }
    g.module.finish().emit().map_err(|e| e.to_string())
}

fn declare_runtime(m: &mut ObjectModule) -> Result<Runtime, String> {
    let mut f = |name: &str, params: &[ir::Type], rets: &[ir::Type]| -> Result<FuncId, String> {
        let mut sig = m.make_signature();
        sig.params.extend(params.iter().map(|t| AbiParam::new(*t)));
        sig.returns.extend(rets.iter().map(|t| AbiParam::new(*t)));
        m.declare_function(name, Linkage::Import, &sig).map_err(|e| e.to_string())
    };
    let (i, b) = (types::I64, types::I8);
    Ok(Runtime {
        fault: f("msrt_fault", &[i], &[])?,
        alloc: f("msrt_alloc", &[i], &[i])?,
        free: f("msrt_free", &[i], &[])?,
        grow: f("msrt_grow", &[i, i, i], &[i])?,
        map_new: f("msrt_map_new", &[], &[i])?,
        map_free: f("msrt_map_free", &[i], &[])?,
        map_get: f("msrt_map_get", &[i, i, i], &[b])?,
        map_add: f("msrt_map_add", &[i, i, i], &[])?,
        map_len: f("msrt_map_len", &[i], &[i])?,
        now_us: f("msrt_now_us", &[], &[i])?,
        report: f("msrt_report", &[i, i, i, i], &[])?,
        cancelled: m.declare_data("msrt_cancelled", Linkage::Import, true, false).map_err(|e| e.to_string())?,
    })
}

impl<'p> Gen<'p> {
    fn leaf_sig(&self, params: &[Leaf], rets: &[Leaf]) -> Signature {
        let mut sig = self.module.make_signature();
        sig.params.extend(params.iter().map(|l| AbiParam::new(clif(*l))));
        sig.returns.extend(rets.iter().map(|l| AbiParam::new(clif(*l))));
        sig
    }

    /// Parameters' leaves in; the result's leaves then each `mut` parameter's leaves out.
    fn fn_sig(&self, f: usize) -> Signature {
        let s = &self.ck.sigs[f];
        let t = &self.ck.types;
        let params: Vec<Leaf> = s.params.iter().flat_map(|(ty, _)| t.leaves(ty)).collect();
        let mut rets = t.leaves(&s.ret);
        rets.extend(s.params.iter().filter(|(_, m)| *m).flat_map(|(ty, _)| t.leaves(ty)));
        self.leaf_sig(&params, &rets)
    }

    fn define(&mut self, ctx: &mut Context, id: FuncId, name: &str) -> Result<(), String> {
        if std::env::var_os("MSC_PRINT_CLIF").is_some() {
            eprintln!("; {name}\n{}", ctx.func.display());
        }
        self.module.define_function(id, ctx).map_err(|e| format!("{name}: {e:?}"))?;
        self.module.clear_context(ctx);
        Ok(())
    }

    fn drop_fn(&mut self, ty: &Ty) -> FuncId {
        if let Some(id) = self.drops.get(ty) {
            return *id;
        }
        let sig = self.leaf_sig(&self.ck.types.leaves(ty), &[]);
        let id = self.module.declare_anonymous_function(&sig).unwrap();
        self.drops.insert(ty.clone(), id);
        self.drop_queue.push(ty.clone());
        id
    }

    fn string(&mut self, s: &str) -> DataId {
        if let Some(id) = self.strings.get(s) {
            return *id;
        }
        let id = self.module.declare_anonymous_data(false, false).unwrap();
        let mut desc = DataDescription::new();
        desc.define(s.as_bytes().to_vec().into_boxed_slice());
        self.module.define_data(id, &desc).unwrap();
        self.strings.insert(s.to_string(), id);
        id
    }

    fn lower_fn(&mut self, ctx: &mut Context, fctx: &mut FunctionBuilderContext, f: &FnDecl, index: usize) {
        let b = FunctionBuilder::new(&mut ctx.func, fctx);
        let mut l = Lower::new(self, b);
        // Cranelift's inliner copies symbol global values without remapping
        // their name, so the poll symbol must have the same name index in
        // every function: declare it first.
        l.cancel = Some(l.g.module.declare_data_in_func(l.g.rt.cancelled, l.b.func));
        let entry = l.b.create_block();
        l.b.append_block_params_for_function_params(entry);
        l.b.switch_to_block(entry);
        let mut params = l.b.block_params(entry).to_vec().into_iter();
        l.scopes.push(Vec::new());
        let sig: Vec<(Ty, bool)> = l.g.ck.sigs[index].params.clone();
        for (p, (ty, mutable)) in f.params.iter().zip(sig) {
            let n = l.g.ck.types.leaves(&ty).len();
            let vals: Vec<Value> = params.by_ref().take(n).collect();
            let local = l.declare(&p.name, &ty, false);
            l.set_local(local, &vals);
            if mutable {
                l.mut_params.push(local);
            }
        }
        l.ret = l.g.ck.sigs[index].ret.clone();
        l.block(&f.body);
        if !l.terminated {
            if l.ret == Ty::Unit {
                l.ret_with(Vec::new());
            } else {
                l.b.ins().trap(TrapCode::unwrap_user(1));
            }
        }
        l.finish();
    }

    fn lower_drop(&mut self, ctx: &mut Context, fctx: &mut FunctionBuilderContext, ty: &Ty) {
        let b = FunctionBuilder::new(&mut ctx.func, fctx);
        let mut l = Lower::new(self, b);
        let entry = l.b.create_block();
        l.b.append_block_params_for_function_params(entry);
        l.b.switch_to_block(entry);
        let vals = l.b.block_params(entry).to_vec();
        l.drop_contents(ty, &vals);
        l.b.ins().return_(&[]);
        l.finish();
    }
}

struct LocalSlot {
    ty: Ty,
    vars: Vec<Variable>,
    flag: Option<Variable>,
}

enum Place {
    Var { local: usize, start: usize, ty: Ty },
    Mem { addr: Value, ty: Ty },
}

struct Lower<'g, 'p, 'b> {
    g: &'g mut Gen<'p>,
    b: FunctionBuilder<'b>,
    locals: Vec<LocalSlot>,
    scopes: Vec<Vec<(String, usize)>>,
    temps: Vec<(Ty, Vec<Value>)>,
    faults: HashMap<i64, ir::Block>,
    refs: HashMap<FuncId, FuncRef>,
    cancel: Option<GlobalValue>,
    mut_params: Vec<usize>,
    ret: Ty,
    terminated: bool,
}

impl<'g, 'p, 'b> Lower<'g, 'p, 'b> {
    fn new(g: &'g mut Gen<'p>, b: FunctionBuilder<'b>) -> Self {
        Lower {
            g,
            b,
            locals: Vec::new(),
            scopes: Vec::new(),
            temps: Vec::new(),
            faults: HashMap::new(),
            refs: HashMap::new(),
            cancel: None,
            mut_params: Vec::new(),
            ret: Ty::Unit,
            terminated: false,
        }
    }

    fn finish(mut self) {
        self.b.seal_all_blocks();
        let config = self.g.module.target_config();
        self.b.finalize(config);
    }

    fn ty(&self, e: &Expr) -> Ty {
        self.g.ck.expr_ty[e.id].clone()
    }

    fn needs_drop(&self, ty: &Ty) -> bool {
        self.g.ck.types.needs_drop(ty)
    }

    fn fref(&mut self, id: FuncId) -> FuncRef {
        if let Some(r) = self.refs.get(&id) {
            return *r;
        }
        let r = self.g.module.declare_func_in_func(id, self.b.func);
        self.refs.insert(id, r);
        r
    }

    fn call(&mut self, id: FuncId, args: &[Value]) -> Vec<Value> {
        let r = self.fref(id);
        let inst = self.b.ins().call(r, args);
        self.b.inst_results(inst).to_vec()
    }

    fn iconst(&mut self, v: i64) -> Value {
        self.b.ins().iconst(types::I64, v)
    }

    // ---- locals, places, drops -------------------------------------------

    fn declare(&mut self, name: &str, ty: &Ty, owned: bool) -> usize {
        let vars = self.g.ck.types.leaves(ty).into_iter().map(|leaf| self.b.declare_var(clif(leaf))).collect();
        let flag = (owned && self.needs_drop(ty)).then(|| {
            let v = self.b.declare_var(types::I8);
            let zero = self.b.ins().iconst(types::I8, 0);
            self.b.def_var(v, zero);
            v
        });
        self.locals.push(LocalSlot { ty: ty.clone(), vars, flag });
        let idx = self.locals.len() - 1;
        self.scopes.last_mut().unwrap().push((name.to_string(), idx));
        idx
    }

    fn set_local(&mut self, local: usize, vals: &[Value]) {
        for (var, v) in self.locals[local].vars.clone().into_iter().zip(vals) {
            self.b.def_var(var, *v);
        }
    }

    fn set_flag(&mut self, local: usize, live: bool) {
        if let Some(flag) = self.locals[local].flag {
            let v = self.b.ins().iconst(types::I8, live as i64);
            self.b.def_var(flag, v);
        }
    }

    fn lookup(&self, name: &str) -> usize {
        self.scopes.iter().rev().flat_map(|s| s.iter().rev()).find(|(n, _)| n == name).map(|(_, i)| *i).expect("checked name")
    }

    fn read(&mut self, p: &Place) -> Vec<Value> {
        match p {
            Place::Var { local, start, ty } => {
                let n = self.g.ck.types.leaves(ty).len();
                let vars = self.locals[*local].vars[*start..*start + n].to_vec();
                vars.into_iter().map(|v| self.b.use_var(v)).collect()
            }
            Place::Mem { addr, ty } => {
                let layout = self.g.ck.types.layout(ty);
                layout.leaves.iter().map(|(leaf, off)| self.b.ins().load(clif(*leaf), MemFlagsData::trusted(), *addr, *off as i32)).collect()
            }
        }
    }

    fn write(&mut self, p: &Place, vals: &[Value]) {
        match p {
            Place::Var { local, start, .. } => {
                let vars = self.locals[*local].vars[*start..*start + vals.len()].to_vec();
                for (var, v) in vars.into_iter().zip(vals) {
                    self.b.def_var(var, *v);
                }
            }
            Place::Mem { addr, ty } => {
                let layout = self.g.ck.types.layout(ty);
                for ((_, off), v) in layout.leaves.iter().zip(vals) {
                    self.b.ins().store(MemFlagsData::trusted(), *v, *addr, *off as i32);
                }
            }
        }
    }

    fn place(&mut self, e: &Expr) -> Place {
        match &e.kind {
            ExprKind::Name(name) if matches!(self.g.ck.res.get(&e.id), Some(Res::Local)) => {
                let local = self.lookup(name);
                Place::Var { local, start: 0, ty: self.locals[local].ty.clone() }
            }
            ExprKind::Field(base, field) => {
                let p = self.place(base);
                let Ty::Record(r) = self.ty(base) else { unreachable!() };
                let fi = self.g.ck.types.records[r].fields.iter().position(|(n, _)| n == field).unwrap();
                let fty = self.g.ck.types.records[r].fields[fi].1.clone();
                let leaf = self.g.ck.types.field_leaf(r, fi);
                match p {
                    Place::Var { local, start, .. } => Place::Var { local, start: start + leaf, ty: fty },
                    Place::Mem { addr, ty } => {
                        let off = self.g.ck.types.layout(&ty).leaves[leaf].1;
                        let addr = self.b.ins().iadd_imm_s(addr, off);
                        Place::Mem { addr, ty: fty }
                    }
                }
            }
            ExprKind::Index(base, index) => {
                let p = self.place(base);
                let list = self.read(&p);
                let i = self.expr(index)[0];
                if self.g.opts.checks {
                    let out = self.b.ins().icmp(IntCC::UnsignedGreaterThanOrEqual, i, list[1]);
                    self.fault_if(out, FAULT_BOUNDS);
                }
                let elem = self.ty(e);
                let size = self.g.ck.types.layout(&elem).size;
                let off = self.b.ins().imul_imm_s(i, size);
                let addr = self.b.ins().iadd(list[0], off);
                Place::Mem { addr, ty: elem }
            }
            _ => {
                let ty = self.ty(e);
                let vals = self.expr(e);
                let local = self.declare("", &ty, false);
                self.set_local(local, &vals);
                Place::Var { local, start: 0, ty }
            }
        }
    }

    fn drop_value(&mut self, ty: &Ty, vals: &[Value]) {
        match ty {
            _ if !self.needs_drop(ty) => {}
            Ty::List(elem) if !self.needs_drop(elem) => {
                let free = self.g.rt.free;
                self.call(free, &vals[..1]);
            }
            Ty::Map => {
                let f = self.g.rt.map_free;
                self.call(f, vals);
            }
            _ => {
                let f = self.g.drop_fn(ty);
                self.call(f, vals);
            }
        }
    }

    /// Body of a generated drop function.
    fn drop_contents(&mut self, ty: &Ty, vals: &[Value]) {
        let types = &self.g.ck.types;
        match ty {
            Ty::List(elem) => {
                let elem = (**elem).clone();
                let size = types.layout(&elem).size;
                let (head, body, done) = (self.b.create_block(), self.b.create_block(), self.b.create_block());
                self.b.append_block_param(head, types::I64);
                let zero = self.iconst(0);
                self.b.ins().jump(head, &[BlockArg::Value(zero)]);
                self.b.switch_to_block(head);
                let i = self.b.block_params(head)[0];
                let more = self.b.ins().icmp(IntCC::SignedLessThan, i, vals[1]);
                self.b.ins().brif(more, body, &[], done, &[]);
                self.b.switch_to_block(body);
                let off = self.b.ins().imul_imm_s(i, size);
                let addr = self.b.ins().iadd(vals[0], off);
                let item = self.read(&Place::Mem { addr, ty: elem.clone() });
                self.drop_value(&elem, &item);
                let next = self.b.ins().iadd_imm_s(i, 1);
                self.b.ins().jump(head, &[BlockArg::Value(next)]);
                self.b.switch_to_block(done);
                let free = self.g.rt.free;
                self.call(free, &vals[..1]);
            }
            Ty::Record(r) => {
                let fields = types.records[*r].fields.clone();
                let mut at = 0;
                for (_, fty) in fields {
                    let n = self.g.ck.types.leaves(&fty).len();
                    self.drop_value(&fty, &vals[at..at + n]);
                    at += n;
                }
            }
            Ty::Alt(a) => {
                let alt = &types.alts[*a];
                let nullary = alt.nullary_count();
                let tagged = alt.boxed_count() > 1;
                let cases: Vec<(i64, Vec<Ty>)> = alt
                    .cases
                    .iter()
                    .enumerate()
                    .filter(|(_, c)| !c.fields.is_empty())
                    .map(|(i, c)| (alt.code(i), c.fields.iter().map(|(_, t)| t.clone()).collect()))
                    .collect();
                let (boxed, done) = (self.b.create_block(), self.b.create_block());
                let small = self.b.ins().icmp_imm_s(IntCC::UnsignedLessThan, vals[0], nullary);
                self.b.ins().brif(small, done, &[], boxed, &[]);
                self.b.switch_to_block(boxed);
                for (code, fields) in cases {
                    let next = self.b.create_block();
                    if tagged {
                        let (this, _) = (self.b.create_block(), ());
                        let tag = self.b.ins().load(types::I64, MemFlagsData::trusted(), vals[0], 0);
                        let is = self.b.ins().icmp_imm_s(IntCC::Equal, tag, code);
                        self.b.ins().brif(is, this, &[], next, &[]);
                        self.b.switch_to_block(this);
                    }
                    let fvals = self.box_fields(vals[0], &fields, tagged);
                    let mut at = 0;
                    for fty in &fields {
                        let n = self.g.ck.types.leaves(fty).len();
                        self.drop_value(fty, &fvals[at..at + n]);
                        at += n;
                    }
                    let free = self.g.rt.free;
                    self.call(free, &vals[..1]);
                    self.b.ins().jump(done, &[]);
                    self.b.switch_to_block(next);
                    if !tagged {
                        break;
                    }
                }
                self.b.ins().jump(done, &[]);
                self.b.switch_to_block(done);
            }
            _ => self.drop_value(ty, vals),
        }
    }

    /// Box layout for a case: an Int tag first when several cases are boxed.
    fn box_layout(&self, fields: &[Ty], tagged: bool) -> crate::types::Layout {
        let tag = [Ty::Int];
        let head: &[Ty] = if tagged { &tag } else { &[] };
        self.g.ck.types.layout_fields(head.iter().chain(fields))
    }

    fn box_fields(&mut self, ptr: Value, fields: &[Ty], tagged: bool) -> Vec<Value> {
        let layout = self.box_layout(fields, tagged);
        let skip = tagged as usize;
        layout.leaves[skip..].iter().map(|(leaf, off)| self.b.ins().load(clif(*leaf), MemFlagsData::trusted(), ptr, *off as i32)).collect()
    }

    fn drop_scope(&mut self, scope: &[(String, usize)]) {
        for (_, local) in scope.iter().rev() {
            let Some(flag) = self.locals[*local].flag else { continue };
            let ty = self.locals[*local].ty.clone();
            let live = self.b.use_var(flag);
            let (yes, done) = (self.b.create_block(), self.b.create_block());
            self.b.ins().brif(live, yes, &[], done, &[]);
            self.b.switch_to_block(yes);
            let vals = self.read(&Place::Var { local: *local, start: 0, ty: ty.clone() });
            self.drop_value(&ty, &vals);
            self.b.ins().jump(done, &[]);
            self.b.switch_to_block(done);
        }
    }

    fn drop_temps(&mut self, mark: usize) {
        if mark >= self.temps.len() {
            return;
        }
        let temps: Vec<_> = self.temps.drain(mark..).collect();
        if self.terminated {
            return;
        }
        for (ty, vals) in temps.into_iter().rev() {
            self.drop_value(&ty, &vals);
        }
    }

    // ---- control -----------------------------------------------------------

    fn fault_if(&mut self, cond: Value, code: i64) {
        let fault = match self.faults.get(&code) {
            Some(b) => *b,
            None => {
                let here = self.b.current_block().unwrap();
                let fb = self.b.create_block();
                self.b.set_cold_block(fb);
                self.b.switch_to_block(fb);
                let c = self.iconst(code);
                let f = self.g.rt.fault;
                self.call(f, &[c]);
                self.b.ins().trap(TrapCode::unwrap_user(2));
                self.b.switch_to_block(here);
                self.faults.insert(code, fb);
                fb
            }
        };
        let cont = self.b.create_block();
        self.b.ins().brif(cond, fault, &[], cont, &[]);
        self.b.switch_to_block(cont);
    }

    fn poll(&mut self) {
        if !self.g.opts.poll {
            return;
        }
        let gv = match self.cancel {
            Some(gv) => gv,
            None => {
                let gv = self.g.module.declare_data_in_func(self.g.rt.cancelled, self.b.func);
                self.cancel = Some(gv);
                gv
            }
        };
        let addr = self.b.ins().symbol_value(types::I64, gv);
        // Atomic so the optimizer never hoists the poll out of the loop.
        let v = self.b.ins().atomic_load(types::I32, MemFlagsData::trusted(), addr);
        self.fault_if(v, FAULT_CANCELLED);
    }

    fn dead_block(&mut self) {
        let dead = self.b.create_block();
        self.b.switch_to_block(dead);
        self.terminated = true;
    }

    fn ret_with(&mut self, mut vals: Vec<Value>) {
        let scopes = self.scopes.clone();
        for scope in scopes.iter().rev() {
            self.drop_scope(scope);
        }
        for local in self.mut_params.clone() {
            let ty = self.locals[local].ty.clone();
            vals.extend(self.read(&Place::Var { local, start: 0, ty }));
        }
        self.b.ins().return_(&vals);
        self.dead_block();
    }

    fn block(&mut self, block: &Block) {
        self.scopes.push(Vec::new());
        for s in block {
            if self.terminated {
                break;
            }
            let mark = self.temps.len();
            self.stmt(&s.kind);
            self.drop_temps(mark);
        }
        let scope = self.scopes.pop().unwrap();
        if !self.terminated {
            self.drop_scope(&scope);
        }
    }

    /// Lowers a nested block; a block that returned leaves code dead until the join.
    fn branch(&mut self, block: &Block, join: ir::Block) -> bool {
        self.terminated = false;
        self.block(block);
        let reached = !self.terminated;
        if reached {
            self.b.ins().jump(join, &[]);
        }
        reached
    }

    fn stmt(&mut self, kind: &StmtKind) {
        match kind {
            StmtKind::Let { name, init, .. } => {
                let ty = self.ty(init);
                let vals = self.consume(init);
                let local = self.declare(name, &ty, true);
                self.set_local(local, &vals);
                self.set_flag(local, true);
            }
            StmtKind::Assign { target, op: Some(op), value } => {
                let p = self.place(target);
                let old = self.read(&p)[0];
                let v = self.expr(value)[0];
                let ty = self.ty(target);
                let new = self.arith(*op, &ty, old, v, Some(value));
                self.write(&p, &[new]);
            }
            StmtKind::Assign { target, op: None, value } => {
                let vals = self.consume(value);
                let p = self.place(target);
                let ty = self.ty(target);
                if let (ExprKind::Name(_), Place::Var { local, .. }) = (&target.kind, &p) {
                    let local = *local;
                    self.drop_scope(&[(String::new(), local)]);
                    self.write(&p, &vals);
                    self.set_flag(local, true);
                    return;
                }
                if self.needs_drop(&ty) {
                    let old = self.read(&p);
                    self.drop_value(&ty, &old);
                }
                self.write(&p, &vals);
            }
            StmtKind::While { cond, body } => {
                let (head, inner, exit) = (self.b.create_block(), self.b.create_block(), self.b.create_block());
                self.b.ins().jump(head, &[]);
                self.b.switch_to_block(head);
                self.poll();
                let mark = self.temps.len();
                let c = self.expr(cond)[0];
                self.drop_temps(mark);
                self.b.ins().brif(c, inner, &[], exit, &[]);
                self.b.switch_to_block(inner);
                self.branch(body, head);
                self.b.switch_to_block(exit);
                self.terminated = false;
            }
            StmtKind::If { cond, then, els } => {
                let mark = self.temps.len();
                let c = self.expr(cond)[0];
                self.drop_temps(mark);
                let (yes, no, join) = (self.b.create_block(), self.b.create_block(), self.b.create_block());
                self.b.ins().brif(c, yes, &[], no, &[]);
                self.b.switch_to_block(yes);
                let a = self.branch(then, join);
                self.b.switch_to_block(no);
                let b = match els {
                    Some(els) => self.branch(els, join),
                    None => {
                        self.terminated = false;
                        self.b.ins().jump(join, &[]);
                        true
                    }
                };
                self.b.switch_to_block(join);
                self.terminated = !(a || b);
            }
            StmtKind::Return(value) => {
                let vals = self.consume(value);
                // Temporaries stay listed: paths that do not return still drop them.
                for (ty, temp) in self.temps.clone().into_iter().rev() {
                    self.drop_value(&ty, &temp);
                }
                self.ret_with(vals);
            }
            StmtKind::Match { scrutinee, arms } => self.match_stmt(scrutinee, arms),
            StmtKind::Expr(e) => {
                self.expr(e);
            }
        }
    }

    fn match_stmt(&mut self, scrutinee: &Expr, arms: &[Arm]) {
        let Ty::Alt(a) = self.ty(scrutinee) else { unreachable!() };
        let p = self.expr(scrutinee)[0];
        let alt = &self.g.ck.types.alts[a];
        let nullary = alt.nullary_count();
        let tagged = alt.boxed_count() > 1;
        let index: HashMap<String, usize> = alt.cases.iter().enumerate().map(|(i, c)| (c.name.clone(), i)).collect();
        let codes: Vec<i64> = (0..alt.cases.len()).map(|i| alt.code(i)).collect();
        let fields: Vec<Vec<Ty>> = alt.cases.iter().map(|c| c.fields.iter().map(|(_, t)| t.clone()).collect()).collect();
        let join = self.b.create_block();
        let blocks: Vec<ir::Block> = arms.iter().map(|_| self.b.create_block()).collect();
        let arm_of = |case: usize| arms.iter().position(|arm| index[&arm.case] == case).unwrap();
        // Dispatch: small words are cases without fields; anything else is a box.
        let (small, boxed) = (self.b.create_block(), self.b.create_block());
        let is_small = self.b.ins().icmp_imm_s(IntCC::UnsignedLessThan, p, nullary);
        self.b.ins().brif(is_small, small, &[], boxed, &[]);
        for (word, is_boxed) in [(small, false), (boxed, true)] {
            self.b.switch_to_block(word);
            let cases: Vec<usize> = (0..codes.len()).filter(|c| fields[*c].is_empty() != is_boxed).collect();
            let key = if is_boxed && tagged { Some(self.b.ins().load(types::I64, MemFlagsData::trusted(), p, 0)) } else if is_boxed { None } else { Some(p) };
            for (n, case) in cases.iter().enumerate() {
                let target = blocks[arm_of(*case)];
                match key {
                    Some(k) if n + 1 < cases.len() => {
                        let next = self.b.create_block();
                        let is = self.b.ins().icmp_imm_s(IntCC::Equal, k, codes[*case]);
                        self.b.ins().brif(is, target, &[], next, &[]);
                        self.b.switch_to_block(next);
                    }
                    _ => {
                        self.b.ins().jump(target, &[]);
                        break;
                    }
                }
            }
            if cases.is_empty() {
                self.b.ins().trap(TrapCode::unwrap_user(1));
            }
        }
        let mut reached = false;
        for (arm, block) in arms.iter().zip(blocks) {
            self.b.switch_to_block(block);
            let case = index[&arm.case];
            self.scopes.push(Vec::new());
            if !fields[case].is_empty() {
                let vals = self.box_fields(p, &fields[case], tagged);
                let mut at = 0;
                for (name, fty) in arm.binds.iter().zip(&fields[case]) {
                    let n = self.g.ck.types.leaves(fty).len();
                    let local = self.declare(name, fty, false);
                    self.set_local(local, &vals[at..at + n]);
                    at += n;
                }
            }
            reached |= self.branch(&arm.body, join);
            self.scopes.pop();
        }
        self.b.switch_to_block(join);
        self.terminated = !reached;
    }

    // ---- expressions -------------------------------------------------------

    /// A value used in place: a fresh droppable value becomes a temporary
    /// dropped at the end of the statement.
    fn expr(&mut self, e: &Expr) -> Vec<Value> {
        let vals = self.eval(e);
        let ty = self.ty(e);
        let fresh = matches!(e.kind, ExprKind::Call { .. } | ExprKind::New(_));
        if fresh && self.needs_drop(&ty) {
            self.temps.push((ty, vals.clone()));
        }
        vals
    }

    /// A value taken over by its consumer: no temporary.
    fn consume(&mut self, e: &Expr) -> Vec<Value> {
        self.eval(e)
    }

    fn eval(&mut self, e: &Expr) -> Vec<Value> {
        match &e.kind {
            ExprKind::Int(v) => vec![self.iconst(*v)],
            ExprKind::Float(v) => vec![self.b.ins().f64const(*v)],
            ExprKind::Bool(v) => vec![self.b.ins().iconst(types::I8, *v as i64)],
            ExprKind::Str(s) => {
                let id = self.g.string(s);
                let gv = self.g.module.declare_data_in_func(id, self.b.func);
                let ptr = self.b.ins().symbol_value(types::I64, gv);
                vec![ptr, self.iconst(s.len() as i64)]
            }
            ExprKind::Name(name) => match self.g.ck.res[&e.id] {
                Res::Case(a, c) => vec![self.iconst(self.g.ck.types.alts[a].code(c))],
                _ => {
                    let local = self.lookup(name);
                    let ty = self.locals[local].ty.clone();
                    let vals = self.read(&Place::Var { local, start: 0, ty });
                    if self.g.ck.moves.contains(&e.id) {
                        self.set_flag(local, false);
                    }
                    vals
                }
            },
            ExprKind::Unary(op, x) => {
                let v = self.expr(x)[0];
                let ty = self.ty(x);
                vec![match (op, ty) {
                    (UnOp::Not, _) => self.b.ins().bxor_imm_s(v, 1),
                    (UnOp::Neg, Ty::Float) => self.b.ins().fneg(v),
                    _ => {
                        let zero = self.iconst(0);
                        self.arith(BinOp::Sub, &Ty::Int, zero, v, None)
                    }
                }]
            }
            ExprKind::Binary(op @ (BinOp::And | BinOp::Or), l, r) => {
                let lv = self.expr(l)[0];
                let (rhs, join) = (self.b.create_block(), self.b.create_block());
                self.b.append_block_param(join, types::I8);
                let short = BlockArg::Value(lv);
                if *op == BinOp::And {
                    self.b.ins().brif(lv, rhs, &[], join, &[short]);
                } else {
                    self.b.ins().brif(lv, join, &[short], rhs, &[]);
                }
                self.b.switch_to_block(rhs);
                let rv = self.expr(r)[0];
                self.b.ins().jump(join, &[BlockArg::Value(rv)]);
                self.b.switch_to_block(join);
                vec![self.b.block_params(join)[0]]
            }
            ExprKind::Binary(op, l, r) => {
                let ty = self.ty(l);
                let lv = self.expr(l)[0];
                let rv = self.expr(r)[0];
                vec![self.binary(*op, &ty, lv, rv, r)]
            }
            ExprKind::Call { args, .. } => self.call_expr(e, args),
            ExprKind::Method { recv, name, args } => self.method(recv, name, args),
            ExprKind::Field(..) | ExprKind::Index(..) => {
                let p = self.place(e);
                self.read(&p)
            }
            ExprKind::New(_) => match self.ty(e) {
                Ty::Map => {
                    let f = self.g.rt.map_new;
                    self.call(f, &[])
                }
                _ => vec![self.iconst(0), self.iconst(0), self.iconst(0)],
            },
        }
    }

    fn binary(&mut self, op: BinOp, ty: &Ty, l: Value, r: Value, rhs: &Expr) -> Value {
        let int = |op| match op {
            BinOp::Eq => IntCC::Equal,
            BinOp::Ne => IntCC::NotEqual,
            BinOp::Lt => IntCC::SignedLessThan,
            BinOp::Le => IntCC::SignedLessThanOrEqual,
            BinOp::Gt => IntCC::SignedGreaterThan,
            _ => IntCC::SignedGreaterThanOrEqual,
        };
        let float = |op| match op {
            BinOp::Eq => FloatCC::Equal,
            BinOp::Ne => FloatCC::NotEqual,
            BinOp::Lt => FloatCC::LessThan,
            BinOp::Le => FloatCC::LessThanOrEqual,
            BinOp::Gt => FloatCC::GreaterThan,
            _ => FloatCC::GreaterThanOrEqual,
        };
        match op {
            BinOp::Eq | BinOp::Ne | BinOp::Lt | BinOp::Le | BinOp::Gt | BinOp::Ge => {
                if *ty == Ty::Float {
                    self.b.ins().fcmp(float(op), l, r)
                } else {
                    self.b.ins().icmp(int(op), l, r)
                }
            }
            _ => self.arith(op, ty, l, r, Some(rhs)),
        }
    }

    fn arith(&mut self, op: BinOp, ty: &Ty, l: Value, r: Value, rhs: Option<&Expr>) -> Value {
        if *ty == Ty::Float {
            return match op {
                BinOp::Add => self.b.ins().fadd(l, r),
                BinOp::Sub => self.b.ins().fsub(l, r),
                BinOp::Mul => self.b.ins().fmul(l, r),
                _ => self.b.ins().fdiv(l, r),
            };
        }
        let checks = self.g.opts.checks;
        let literal = match rhs.map(|e| &e.kind) {
            Some(ExprKind::Int(v)) => Some(*v),
            _ => None,
        };
        match op {
            BinOp::Add | BinOp::Sub | BinOp::Mul if checks => {
                let (v, of) = match op {
                    BinOp::Add => self.b.ins().sadd_overflow(l, r),
                    BinOp::Sub => self.b.ins().ssub_overflow(l, r),
                    _ => self.b.ins().smul_overflow(l, r),
                };
                self.fault_if(of, FAULT_OVERFLOW);
                v
            }
            BinOp::Add => self.b.ins().iadd(l, r),
            BinOp::Sub => self.b.ins().isub(l, r),
            BinOp::Mul => self.b.ins().imul(l, r),
            BinOp::Div | BinOp::Mod => {
                // A literal divisor other than 0 and -1 needs no checks.
                let safe = matches!(literal, Some(v) if v != 0 && v != -1);
                if !safe && checks {
                    let zero = self.b.ins().icmp_imm_s(IntCC::Equal, r, 0);
                    self.fault_if(zero, FAULT_DIVZERO);
                }
                if safe {
                    return if op == BinOp::Div { self.b.ins().sdiv(l, r) } else { self.b.ins().srem(l, r) };
                }
                let minus_one = self.b.ins().icmp_imm_s(IntCC::Equal, r, -1);
                if op == BinOp::Div {
                    if checks {
                        let min = self.b.ins().icmp_imm_s(IntCC::Equal, l, i64::MIN);
                        let both = self.b.ins().band(min, minus_one);
                        self.fault_if(both, FAULT_OVERFLOW);
                    }
                    let one = self.iconst(1);
                    let d = self.b.ins().select(minus_one, one, r);
                    let q = self.b.ins().sdiv(l, d);
                    let neg = self.b.ins().ineg(l);
                    return self.b.ins().select(minus_one, neg, q);
                }
                let one = self.iconst(1);
                let d = self.b.ins().select(minus_one, one, r);
                let rem = self.b.ins().srem(l, d);
                let zero = self.iconst(0);
                self.b.ins().select(minus_one, zero, rem)
            }
            _ => unreachable!(),
        }
    }

    fn call_expr(&mut self, e: &Expr, args: &[crate::syntax::Arg]) -> Vec<Value> {
        match self.g.ck.res[&e.id] {
            Res::Fn(f) => {
                let mut vals = Vec::new();
                let mut outs = Vec::new();
                for a in args {
                    if a.mutable {
                        let p = self.place(&a.expr);
                        vals.extend(self.read(&p));
                        outs.push(p);
                    } else {
                        vals.extend(self.expr(&a.expr));
                    }
                }
                let id = self.g.fns[f];
                let results = self.call(id, &vals);
                let ret = self.g.ck.sigs[f].ret.clone();
                let n = self.g.ck.types.leaves(&ret).len();
                let mut at = n;
                for p in outs {
                    let ty = match &p {
                        Place::Var { ty, .. } | Place::Mem { ty, .. } => ty.clone(),
                    };
                    let k = self.g.ck.types.leaves(&ty).len();
                    self.write(&p, &results[at..at + k]);
                    at += k;
                }
                results[..n].to_vec()
            }
            Res::Record(_) => args.iter().flat_map(|a| self.consume(&a.expr)).collect(),
            Res::Case(a, c) => {
                let fields: Vec<Ty> = self.g.ck.types.alts[a].cases[c].fields.iter().map(|(_, t)| t.clone()).collect();
                let code = self.g.ck.types.alts[a].code(c);
                if fields.is_empty() {
                    return vec![self.iconst(code)];
                }
                let tagged = self.g.ck.types.alts[a].boxed_count() > 1;
                let vals: Vec<Value> = args.iter().flat_map(|arg| self.consume(&arg.expr)).collect();
                let layout = self.box_layout(&fields, tagged);
                let size = self.iconst(layout.size);
                let alloc = self.g.rt.alloc;
                let ptr = self.call(alloc, &[size])[0];
                let mut leaves = layout.leaves.iter();
                if tagged {
                    let (_, off) = leaves.next().unwrap();
                    let tag = self.iconst(code);
                    self.b.ins().store(MemFlagsData::trusted(), tag, ptr, *off as i32);
                }
                for ((_, off), v) in leaves.zip(vals) {
                    self.b.ins().store(MemFlagsData::trusted(), v, ptr, *off as i32);
                }
                vec![ptr]
            }
            Res::NowUs => {
                let f = self.g.rt.now_us;
                self.call(f, &[])
            }
            Res::Report => {
                let vals: Vec<Value> = args.iter().flat_map(|a| self.expr(&a.expr)).collect();
                let f = self.g.rt.report;
                self.call(f, &vals);
                vec![]
            }
            Res::Local => unreachable!(),
        }
    }

    fn method(&mut self, recv: &Expr, name: &str, args: &[Expr]) -> Vec<Value> {
        match (self.ty(recv), name) {
            (Ty::List(elem), "append") => {
                let p = self.place(recv);
                let v = self.consume(&args[0]);
                let list = self.read(&p);
                let size = self.g.ck.types.layout(&elem).size;
                let (grow, ready) = (self.b.create_block(), self.b.create_block());
                self.b.append_block_param(ready, types::I64);
                self.b.append_block_param(ready, types::I64);
                let full = self.b.ins().icmp(IntCC::Equal, list[1], list[2]);
                self.b.ins().brif(full, grow, &[], ready, &[BlockArg::Value(list[0]), BlockArg::Value(list[2])]);
                self.b.switch_to_block(grow);
                self.b.set_cold_block(grow);
                let doubled = self.b.ins().ishl_imm_s(list[2], 1);
                let empty = self.b.ins().icmp_imm_s(IntCC::Equal, list[2], 0);
                let eight = self.iconst(8);
                let cap = self.b.ins().select(empty, eight, doubled);
                let esize = self.iconst(size);
                let f = self.g.rt.grow;
                let ptr = self.call(f, &[list[0], cap, esize])[0];
                self.b.ins().jump(ready, &[BlockArg::Value(ptr), BlockArg::Value(cap)]);
                self.b.switch_to_block(ready);
                let (ptr, cap) = (self.b.block_params(ready)[0], self.b.block_params(ready)[1]);
                let off = self.b.ins().imul_imm_s(list[1], size);
                let addr = self.b.ins().iadd(ptr, off);
                self.write(&Place::Mem { addr, ty: (*elem).clone() }, &v);
                let len = self.b.ins().iadd_imm_s(list[1], 1);
                self.write(&p, &[ptr, len, cap]);
                vec![]
            }
            (Ty::List(_), "length") => vec![self.expr(recv)[1]],
            (Ty::Map, "length") => {
                let m = self.expr(recv);
                let f = self.g.rt.map_len;
                self.call(f, &m)
            }
            (Ty::Map, "add") => {
                let p = self.place(recv);
                let m = self.read(&p)[0];
                let k = self.expr(&args[0])[0];
                let v = self.expr(&args[1])[0];
                let f = self.g.rt.map_add;
                self.call(f, &[m, k, v]);
                vec![]
            }
            (Ty::Map, "get") => {
                let m = self.expr(recv)[0];
                let k = self.expr(&args[0])[0];
                let slot = self.b.create_sized_stack_slot(StackSlotData::new(StackSlotKind::ExplicitSlot, 8, 3));
                let out = self.b.ins().stack_addr(types::I64, slot, 0);
                let f = self.g.rt.map_get;
                let found = self.call(f, &[m, k, out])[0];
                let v = self.b.ins().load(types::I64, MemFlagsData::trusted(), out, 0);
                vec![found, v]
            }
            (Ty::OptInt, "get") => {
                let o = self.expr(recv);
                let d = self.expr(&args[0])[0];
                vec![self.b.ins().select(o[0], o[1], d)]
            }
            (Ty::Int, "to_float") => {
                let v = self.expr(recv)[0];
                vec![self.b.ins().fcvt_from_sint(types::F64, v)]
            }
            (Ty::Float, "truncate_to_int") => {
                let v = self.expr(recv)[0];
                let lo = self.b.ins().f64const(-9223372036854775808.0);
                let hi = self.b.ins().f64const(9223372036854775808.0);
                let ge = self.b.ins().fcmp(FloatCC::GreaterThanOrEqual, v, lo);
                let lt = self.b.ins().fcmp(FloatCC::LessThan, v, hi);
                let ok = self.b.ins().band(ge, lt);
                vec![ok, self.b.ins().fcvt_to_sint_sat(types::I64, v)]
            }
            _ => unreachable!("checked method"),
        }
    }
}
