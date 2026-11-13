//! Interface values over source types: implementation tables and coercion.

use crate::Error;
use crate::cx::Cx;
use crate::cx::VtableKey;
use crate::func::{FnLower, Val};
use ms_check::api::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncKind, Imm, Linkage, Mode, Module, Op, Param, VtableDef, VtableId};
use ms_mir::types::{IfaceId, Std, Ty as MTy, TyKind};

impl Cx {
    /// Adds a finished table under `key` and returns its id.
    pub(crate) fn intern_vtable(
        &mut self,
        m: &mut Module,
        key: VtableKey,
        iface: IfaceId,
        methods: Vec<ms_mir::ir::FuncId>,
        data_ty: MTy,
    ) -> VtableId {
        let id = VtableId(m.vtables.len() as u32);
        m.vtables.push(VtableDef {
            name: key.name(self.syms),
            iface,
            methods,
            data_ty,
        });
        self.vtables.insert(key, id);
        id
    }

    /// The table of `concrete`'s methods for the interface, created on first use.
    pub(crate) fn vtable_id(
        &mut self,
        m: &mut Module,
        concrete: &ct::Ty,
        iface: IfaceId,
        scope: ct::Name,
    ) -> Result<VtableId, Error> {
        let data_ty = self.lower_ty(m, concrete)?;
        self.vtable_for(m, concrete, data_ty, iface, scope)
    }

    /// The table of `concrete`'s methods for the interface, one wrapper per operation. Local
    /// extensions of other modules than `scope` are not candidates.
    pub(crate) fn vtable_for(
        &mut self,
        m: &mut Module,
        concrete: &ct::Ty,
        data_ty: MTy,
        iface: IfaceId,
        scope: ct::Name,
    ) -> Result<VtableId, Error> {
        let key = VtableKey::Impl {
            ty: self.tys.shape(concrete),
            iface: iface.0,
            scope: self.mentions_extension(concrete).then_some(scope),
        };
        if let Some(v) = self.vtables.get(&key) {
            return Ok(*v);
        }
        let sigs = m.ifaces[iface.index()].methods.clone();
        if m.ifaces[iface.index()].std == Std::Comparable
            && let Some(sym) = builtin_compare(m, data_ty)
        {
            let f =
                build_builtin_compare(m, &sigs[0], data_ty, sym, VtableId(m.vtables.len() as u32));
            return Ok(self.intern_vtable(m, key, iface, vec![f], data_ty));
        }
        // Reserve the table's id: wrappers test for it, and building a callee can create tables.
        let own = VtableId(m.vtables.len() as u32);
        self.intern_vtable(m, key.clone(), iface, Vec::new(), data_ty);
        let mut methods = Vec::new();
        for s in &sigs {
            let mut found = None;
            // A written `impl` wins; otherwise the type's own method of that name satisfies the
            // operation by shape.
            for inherent in [false, true] {
                for at in self.method_index.candidates(concrete.id, ct::n(&s.name)) {
                    let mm = &self.methods[at];
                    let Some(decl) = &mm.decl else { continue };
                    if self.syms.str(mm.id).is_empty()
                        || !mm.visible_in(scope)
                        || mm.is_inherent(self.syms) != inherent
                    {
                        continue;
                    }
                    let mut subst = ct::Subst::new();
                    let vars = ct::variable_set(&mm.variables);
                    if !ct::unify(&mm.receiver, concrete, &vars, &mut subst) {
                        continue;
                    }
                    // One receiver may implement several applications of a generic contract.
                    if !inherent
                        && let (Some(c), Some(want)) = (&mm.contract, self.contracts.get(&iface))
                        && !ct::unify(c, want, &vars, &mut subst)
                    {
                        continue;
                    }
                    found = Some((mm.module, decl.id(), subst, mm.native, mm.clone()));
                    break;
                }
                if found.is_some() {
                    break;
                }
            }
            if found.is_none() && s.name == "equals" && m.ifaces[iface.index()].std == Std::Equal {
                methods.push(self.builtin_equals(
                    m,
                    iface,
                    data_ty,
                    scope,
                    own,
                    &key.name(self.syms),
                )?);
                continue;
            }
            let (module, id, subst, native, mref) = found.ok_or_else(|| {
                Error::new(format!(
                    "{concrete_t} has no method {} for {}",
                    s.name,
                    m.ifaces[iface.index()].name,
                    concrete_t = concrete.display(self.syms)
                ))
            })?;
            let mut ps = vec![Param {
                ty: MTy::PTR,
                mode: Mode::Borrow,
            }];
            ps.extend(s.params.iter().map(|t| Param {
                ty: *t,
                mode: Mode::Borrow,
            }));
            let writes_back;
            let changed: Vec<usize>;
            let op_vars = self.iface_op_vars(iface, &s.name);
            // A hook a `TestHooks` implementation leaves out has no body: it does nothing.
            let missing = native == ct::Native::Source
                && s.ret == MTy::UNIT
                && !self.callables.contains_key(&(module, id));
            if missing {
                let mut b = FuncBuilder::new(m, &format!("vt.{}", s.name), ps, s.ret);
                b.func_mut().kind = FuncKind::Method;
                b.func_mut().linkage = Linkage::Internal;
                let u = b.unit();
                b.ret(Some(u));
                let f = b.into_func();
                methods.push(m.add_func(f));
                continue;
            }
            let callee = if native != ct::Native::Source {
                let f = self.iface_native_thunk(m, &mref, &subst, scope, data_ty, &ps, s.ret)?;
                methods.push(f);
                continue;
            } else {
                let c = self
                    .callables
                    .get(&(module, id))
                    .cloned()
                    .ok_or_else(|| Error::new("method callee not found"))?;
                let vars = self.var_positions(&c);
                // A parameter the method changes must be one the operation declares `var`, so
                // the caller passes its slot.
                if vars
                    .iter()
                    .any(|v| *v != 0 && !op_vars.get(v - 1).copied().unwrap_or(false))
                {
                    return Err(Error::new(
                        "an implementation changes a parameter its interface operation does not declare var",
                    ));
                }
                writes_back = vars.contains(&0);
                changed = vars;
                self.function_in(m, &c, &subst, scope)?
            };
            let mut b = FuncBuilder::new(m, &format!("vt.{}", s.name), ps, s.ret);
            b.func_mut().kind = FuncKind::Method;
            b.func_mut().linkage = Linkage::Internal;
            let args = b.params();
            // A method that changes `self` takes the box itself: it moves the data out and
            // puts the new value back.
            let recv = if writes_back {
                args[0]
            } else {
                b.emit(Op::Load, &[args[0]], Imm::Ty(data_ty), Some(data_ty))
                    .expect("load")
            };
            let mut call_args = vec![recv];
            // A `Self` argument is an interface value holding the implementing type: another type
            // is unequal (`False`) and has no order (a fault) and the same type passes its data.
            for (i, arg) in args[1..].iter().enumerate() {
                // A `var` argument arrives as the caller's slot; a method that only reads it
                // takes the value.
                if op_vars.get(i).copied().unwrap_or(false) && !changed.contains(&(i + 1)) {
                    let ty = b.m.funcs[callee.index()].params[i + 1].ty;
                    let v = b
                        .emit(Op::Load, &[*arg], Imm::Ty(ty), Some(ty))
                        .expect("load");
                    call_args.push(v);
                    continue;
                }
                if !s.self_params.get(i).copied().unwrap_or(false) {
                    call_args.push(*arg);
                    continue;
                }
                let hit = b
                    .emit(Op::IfaceIs, &[*arg], Imm::Vtable(own), Some(MTy::BOOL))
                    .expect("test");
                let (same, differ) = (b.new_block(), b.new_block());
                b.br_if(hit, same, &[], differ, &[]);
                b.seal_block(same);
                b.seal_block(differ);
                b.switch_to(differ);
                if s.ret == MTy::BOOL {
                    let no = b.bconst(false);
                    b.ret(Some(no));
                } else {
                    // An order between different types would contradict `equals`.
                    let msg = b.m.add_string("compared values of different types");
                    b.fault(ms_mir::ir::FaultKind::Message(msg));
                }
                b.switch_to(same);
                let data = b
                    .emit(Op::IfaceData, &[*arg], Imm::None, Some(MTy::PTR))
                    .expect("data");
                let inner = b
                    .emit(Op::Load, &[data], Imm::Ty(data_ty), Some(data_ty))
                    .expect("load");
                call_args.push(inner);
            }
            let r = b.call(callee, &call_args);
            b.ret(Some(r));
            let f = b.into_func();
            methods.push(m.add_func(f));
        }
        m.vtables[own.0 as usize].methods = methods;
        Ok(own)
    }
}

impl Cx {
    /// Which parameters of interface `iface`'s operation `name` are declared `var`.
    pub(crate) fn iface_op_vars(&self, iface: IfaceId, name: &str) -> Vec<bool> {
        let Some(def) = self.contracts.get(&iface).and_then(|t| t.def.clone()) else {
            return Vec::new();
        };
        def.operations
            .borrow()
            .iter()
            .find(|op| self.syms.str(op.name) == name)
            .map(crate::cx::op_var_params)
            .unwrap_or_default()
    }

    /// A table entry for a native method: it lowers like a direct call on the data.
    #[allow(clippy::too_many_arguments)]
    fn iface_native_thunk(
        &mut self,
        m: &mut Module,
        mref: &ct::MethodRef,
        subst: &ct::Subst,
        scope: ct::Name,
        data_ty: MTy,
        params: &[Param],
        ret: MTy,
    ) -> Result<ms_mir::ir::FuncId, Error> {
        let mut f = ms_mir::ir::Func::new(
            &format!("vt.{}", mref.native.text(self.syms)),
            params.to_vec(),
            ret,
        );
        f.kind = FuncKind::Method;
        f.linkage = Linkage::Internal;
        let id = m.add_func(f);
        let mut method = (**mref).clone();
        method.ty = ct::sub(&mref.ty, subst);
        let method = std::rc::Rc::new(method);
        // A standard module's native half has no queries of its own: its source twin or the
        // module of the use stands in.
        let twin = self
            .syms
            .intern(&format!("{}+source", self.syms.str(mref.module)));
        let hir = self
            .module(mref.module)
            .or_else(|_| self.module(twin))
            .or_else(|_| self.module(scope))?;
        self.queue.push(crate::cx::Job {
            func: id,
            kind: crate::cx::JobKind::IfaceNative(std::rc::Rc::new(crate::cx::IfaceNativeJob {
                method,
                hir,
                data: data_ty,
                scope,
            })),
        });
        Ok(id)
    }

    /// `equals` of data with built-in equality (scalars, collections, types without an
    /// `impl Equal`): structural equality against another value of the same type, and `False`
    /// against any other type.
    fn builtin_equals(
        &mut self,
        m: &mut Module,
        iface: IfaceId,
        data_ty: MTy,
        scope: ct::Name,
        vt: VtableId,
        key: &str,
    ) -> Result<ms_mir::ir::FuncId, Error> {
        let scope = self.glue_scope(m, data_ty, scope);
        let other_ty = m.ifaces[iface.index()].methods[0].params[0];
        let ps = vec![
            Param {
                ty: MTy::PTR,
                mode: Mode::Borrow,
            },
            Param {
                ty: other_ty,
                mode: Mode::Borrow,
            },
        ];
        let mut b = FuncBuilder::new(m, &format!("vt.equals.{key}"), ps, MTy::BOOL);
        b.func_mut().kind = FuncKind::Method;
        b.func_mut().linkage = Linkage::Internal;
        let (this, other) = (b.params()[0], b.params()[1]);
        let hit = b
            .emit(Op::IfaceIs, &[other], Imm::Vtable(vt), Some(MTy::BOOL))
            .expect("test");
        let (same, differ) = (b.new_block(), b.new_block());
        b.br_if(hit, same, &[], differ, &[]);
        b.seal_block(same);
        b.seal_block(differ);
        b.switch_to(differ);
        let no = b.bconst(false);
        b.ret(Some(no));
        b.switch_to(same);
        let a = b
            .emit(Op::Load, &[this], Imm::Ty(data_ty), Some(data_ty))
            .expect("load");
        let data = b
            .emit(Op::IfaceData, &[other], Imm::None, Some(MTy::PTR))
            .expect("data");
        let c = b
            .emit(Op::Load, &[data], Imm::Ty(data_ty), Some(data_ty))
            .expect("load");
        let r = crate::eq::element_eq(self, &mut b, scope, data_ty, a, c)?;
        b.ret(Some(r));
        let f = b.into_func();
        Ok(m.add_func(f))
    }
}

impl Cx {
    /// The source-declared method `name` of `concrete` (an `impl` of a standard interface).
    fn user_method(
        &mut self,
        m: &mut Module,
        concrete: &ct::Ty,
        name: &str,
        scope: ct::Name,
    ) -> Result<Option<ms_mir::ir::FuncId>, Error> {
        let mut found = None;
        for at in self.method_index.candidates(concrete.id, ct::n(name)) {
            let mm = &self.methods[at];
            let Some(decl) = &mm.decl else { continue };
            if self.syms.str(mm.id).is_empty()
                || mm.native != ct::Native::Source
                || !mm.visible_in(scope)
            {
                continue;
            }
            let mut subst = ct::Subst::new();
            let vars = ct::variable_set(&mm.variables);
            if ct::unify(&mm.receiver, concrete, &vars, &mut subst) {
                found = Some((mm.module, decl.id(), subst));
                break;
            }
        }
        let Some((module, id, subst)) = found else {
            return Ok(None);
        };
        let c = self
            .callables
            .get(&(module, id))
            .cloned()
            .ok_or_else(|| Error::new(format!("{name} callee not found")))?;
        Ok(Some(self.function_in(m, &c, &subst, scope)?))
    }

    /// The source-declared `equals` of `concrete` (an `impl Equal`), taking another `concrete`.
    pub(crate) fn user_equals(
        &mut self,
        m: &mut Module,
        concrete: &ct::Ty,
        scope: ct::Name,
    ) -> Result<Option<ms_mir::ir::FuncId>, Error> {
        self.user_method(m, concrete, "equals", scope)
    }

    /// The source-declared `hash` of `concrete` (an `impl Hashable`).
    pub(crate) fn user_hash(
        &mut self,
        m: &mut Module,
        concrete: &ct::Ty,
        scope: ct::Name,
    ) -> Result<Option<ms_mir::ir::FuncId>, Error> {
        let Some(f) = self.user_method(m, concrete, "hash", scope)? else {
            return Ok(None);
        };
        let ok = {
            let func = &m.funcs[f.index()];
            func.params.len() == 1 && func.ret == MTy::INT
        };
        Ok(ok.then_some(f))
    }
}

impl FnLower<'_> {
    /// Converts a value of checker type `concrete` to the interface type `want`.
    pub fn fit_ty(&mut self, x: Val, concrete: &ct::Ty, want: MTy) -> Result<Val, Error> {
        let have = self.ty_of(x.v);
        if have == want || self.dead {
            return Ok(x);
        }
        if let (TyKind::Alt(h), TyKind::Alt(w)) =
            (self.b.m.types.kind(have), self.b.m.types.kind(want))
        {
            let (dh, dw) = (&self.b.m.alts[h.index()], &self.b.m.alts[w.index()]);
            if dh.borrowed != 0 && dw.borrowed == 0 && dh.name == dw.name && dh.cases == dw.cases {
                // A borrowing variant read as the ordinary alternative: a borrow of the
                // value, which stays owned (and is dropped) where it was made.
                let v = self.borrow(x);
                let v = self.b.alt_plain(v, want);
                return Ok(Val { v, own: false });
            }
            return self.convert_result(x, concrete, want);
        }
        let TyKind::Iface(iface) = self.b.m.types.kind(want).clone() else {
            return Ok(x);
        };
        let scope = self.evidence();
        let vt = self.cx.vtable_for(self.b.m, concrete, have, iface, scope)?;
        let mutates = self
            .cx
            .contracts
            .get(&iface)
            .is_some_and(ms_check::api::types::contract_mutates);
        if !x.own && !mutates {
            // A borrowed value becomes a view: a box of its leaves as they are, which owns only
            // the box. The checker holds the value's owner for as long as the view lives. An
            // interface with a `var fn` copies instead: a call through it (a native stream
            // reader, say) would change leaves the view only borrows.
            let v = self.b.iface_borrow(vt, x.v, want);
            return Ok(Val { v, own: true });
        }
        let o = self.owned(x);
        let v = self
            .b
            .emit(Op::IfaceNew, &[o], Imm::Vtable(vt), Some(want))
            .expect("iface");
        Ok(Val { v, own: true })
    }
}

impl FnLower<'_> {
    /// A `Result[T, E]` rebuilt as `Result[T, F]` with the error converted to `F`.
    fn convert_result(&mut self, x: Val, concrete: &ct::Ty, want: MTy) -> Result<Val, Error> {
        let (TyKind::Alt(src), TyKind::Alt(dst)) = (
            self.b.m.types.kind(self.ty_of(x.v)).clone(),
            self.b.m.types.kind(want).clone(),
        ) else {
            return Err(Error::new("not a Result conversion"));
        };
        let case = |m: &Module, a: ms_mir::types::AltId, n: &str| {
            m.alts[a.index()].cases.iter().position(|c| c.name == n)
        };
        let (Some(sok), Some(serr), Some(dok), Some(derr)) = (
            case(self.b.m, src, "ok"),
            case(self.b.m, src, "error"),
            case(self.b.m, dst, "ok"),
            case(self.b.m, dst, "error"),
        ) else {
            return Err(Error::new("cannot convert a non-Result alternative"));
        };
        let failure = concrete
            .args
            .get(1)
            .ok_or_else(|| Error::new("not a Result conversion"))?
            .clone();
        let want_err = self.b.m.alts[dst.index()].cases[derr].fields[0].1;
        let res = self.b.declare_var(want, Mode::Move);
        let held = self.b.declare_var(
            self.ty_of(x.v),
            if x.own { Mode::Move } else { Mode::Borrow },
        );
        self.b.def_var(held, x.v);
        let (okb, errb, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        let tag = self.b.alt_tag(x.v);
        let k = self.b.iconst(serr as i64);
        let is_err = self.b.icmp(ms_mir::ir::Cc::Eq, tag, k);
        self.b.br_if(is_err, errb, &[], okb, &[]);
        self.b.seal_block(okb);
        self.b.seal_block(errb);
        for (blk, is_error) in [(okb, false), (errb, true)] {
            self.enter(blk);
            let cur = self.b.use_var(held);
            let (sc, dc) = if is_error { (serr, derr) } else { (sok, dok) };
            let mut p = if x.own {
                // The source is ours: the payload moves out and the rest is released.
                let v = self.b.alt_take(src, sc as u32, 0, cur);
                self.b.alt_release(src, sc as u32, 1, cur);
                Val { v, own: true }
            } else {
                let v = self.b.alt_get(src, sc as u32, 0, cur);
                Val { v, own: false }
            };
            if is_error {
                p = self.fit_ty(p, &failure, want_err)?;
            }
            let po = self.owned(p);
            let out = self.b.alt_new(dst, dc as u32, &[po]);
            self.b.def_var(res, out);
            self.b.br(join, &[]);
        }
        self.b.seal_block(join);
        self.enter(join);
        let v = self.b.use_var(res);
        Ok(Val { v, own: true })
    }
}

/// How a built-in type orders itself as `Comparable`: its runtime comparison function, or the
/// empty name for a type the IR compares directly.
fn builtin_compare(m: &Module, t: MTy) -> Option<&'static str> {
    if m.types.is_int(t) || m.types.is_float(t) {
        return Some("");
    }
    if t == MTy::STR {
        return Some("msrt_string_compare");
    }
    None
}

/// `compare(other)` of a built-in type: the sign of the comparison; a value of
/// another type faults.
fn build_builtin_compare(
    m: &mut Module,
    sig: &ms_mir::types::MethodSig,
    data_ty: MTy,
    sym: &str,
    own_table: VtableId,
) -> ms_mir::ir::FuncId {
    use ms_mir::ir::{Cc, ExternDef};
    let mut ps = vec![Param {
        ty: MTy::PTR,
        mode: Mode::Borrow,
    }];
    ps.extend(sig.params.iter().map(|t| Param {
        ty: *t,
        mode: Mode::Borrow,
    }));
    let mut b = FuncBuilder::new(m, "vt.compare", ps, sig.ret);
    b.func_mut().kind = FuncKind::Method;
    b.func_mut().linkage = Linkage::Internal;
    let args = b.params();
    let zero = b.iconst(0);
    let (same, other) = (b.new_block(), b.new_block());
    let hit = b
        .emit(
            Op::IfaceIs,
            &[args[1]],
            Imm::Vtable(own_table),
            Some(MTy::BOOL),
        )
        .expect("iface.is");
    b.br_if(hit, same, &[], other, &[]);
    b.seal_block(same);
    b.seal_block(other);
    b.switch_to(other);
    let msg = b.m.add_string("compared values of different types");
    b.fault(ms_mir::ir::FaultKind::Message(msg));
    b.switch_to(same);
    let me = b
        .emit(Op::Load, &[args[0]], Imm::Ty(data_ty), Some(data_ty))
        .expect("load");
    let data = b
        .emit(Op::IfaceData, &[args[1]], Imm::None, Some(MTy::PTR))
        .expect("iface.data");
    let you = b
        .emit(Op::Load, &[data], Imm::Ty(data_ty), Some(data_ty))
        .expect("load");
    let sign = if sym.is_empty() {
        let (gt, lt) = if b.m.types.is_int(data_ty) {
            (b.icmp(Cc::Gt, me, you), b.icmp(Cc::Lt, me, you))
        } else {
            (b.fcmp(Cc::Gt, me, you), b.fcmp(Cc::Lt, me, you))
        };
        let (one, minus) = (b.iconst(1), b.iconst(-1));
        let up = b.select(gt, one, zero);
        b.select(lt, minus, up)
    } else {
        let params = [me, you]
            .iter()
            .map(|_| Param {
                ty: data_ty,
                mode: Mode::Borrow,
            })
            .collect();
        let ext = b.m.add_extern(ExternDef {
            name: sym.to_string(),
            params,
            ret: MTy::INT,
            noreturn: false,
            pure_: false,
            fresh: false,
            role: crate::rtcall::extern_role(sym),
            leaf: crate::rtcall::rt_flags(sym).leaf,
            reads: crate::rtcall::rt_flags(sym).reads,
        });
        b.call_rt(ext, &[me, you])
    };
    b.ret(Some(sign));
    let f = b.into_func();
    m.add_func(f)
}
