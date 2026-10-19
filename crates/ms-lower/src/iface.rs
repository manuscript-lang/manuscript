//! Interface values over source types: implementation tables and coercion.

use crate::Error;
use crate::cx::Cx;
use crate::func::{FnLower, Val};
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncKind, Imm, Linkage, Mode, Module, Op, Param, VtableDef, VtableId};
use ms_mir::types::{IfaceId, Ty as MTy, TyKind};

impl Cx {
    /// The table of `concrete`'s methods for the interface, created on first use.
    pub(crate) fn vtable_id(
        &mut self,
        m: &mut Module,
        concrete: &ct::Ty,
        iface: IfaceId,
    ) -> Result<VtableId, Error> {
        let data_ty = self.lower_ty(m, concrete)?;
        self.vtable_for(m, concrete, data_ty, iface)
    }

    /// The table of `concrete`'s methods for the interface, one wrapper per operation.
    fn vtable_for(
        &mut self,
        m: &mut Module,
        concrete: &ct::Ty,
        data_ty: MTy,
        iface: IfaceId,
    ) -> Result<VtableId, Error> {
        let key = format!("impl:{}:{}", ct::type_key(concrete), iface.0);
        if let Some(v) = self.vtables.get(&key) {
            return Ok(*v);
        }
        let sigs = m.ifaces[iface.index()].methods.clone();
        let mut methods = Vec::new();
        for s in &sigs {
            let mut found = None;
            for mm in &self.methods {
                let Some(decl) = &mm.decl else { continue };
                if mm.id.as_str().is_empty() {
                    continue;
                }
                if mm.name().map(|n| n.to_string()).as_deref() != Some(s.name.as_str()) {
                    continue;
                }
                let mut subst = ct::Subst::new();
                let vars = ct::variable_set(&mm.variables);
                if ct::unify(&mm.receiver, concrete, &vars, &mut subst) {
                    found = Some((mm.module, decl.id(), subst, mm.native));
                    break;
                }
            }
            let (module, id, subst, native) = found.ok_or_else(|| {
                Error::new(format!(
                    "{concrete} has no method {} for {}",
                    s.name,
                    m.ifaces[iface.index()].name
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
            let mut writes_back = false;
            // A hook a `TestHooks` implementation leaves out has no body: it does nothing.
            let missing = native.as_str().is_empty()
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
            let callee = if !native.as_str().is_empty() {
                self.native_method_fn(m, native.as_str(), concrete, data_ty)?
            } else {
                let c = self
                    .callables
                    .get(&(module, id))
                    .cloned()
                    .ok_or_else(|| Error::new("method callee not found"))?;
                let vars = self.var_positions(&c);
                if vars.iter().any(|v| *v != 0) {
                    return Err(Error::new(
                        "interface methods with var parameters are not supported",
                    ));
                }
                writes_back = !vars.is_empty();
                self.function_for(m, &c, &subst)?
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
            call_args.extend_from_slice(&args[1..]);
            let r = b.call(callee, &call_args);
            b.ret(Some(r));
            let f = b.into_func();
            methods.push(m.add_func(f));
        }
        m.vtables.push(VtableDef {
            name: key.clone(),
            iface,
            methods,
            data_ty,
        });
        let id = VtableId(m.vtables.len() as u32 - 1);
        self.vtables.insert(key, id);
        Ok(id)
    }
}

impl Cx {
    /// The source-declared method `name` of `concrete` (an `impl` of a standard interface).
    fn user_method(
        &mut self,
        m: &mut Module,
        concrete: &ct::Ty,
        name: &str,
    ) -> Result<Option<ms_mir::ir::FuncId>, Error> {
        let mut found = None;
        for mm in &self.methods {
            let Some(decl) = &mm.decl else { continue };
            if mm.id.as_str().is_empty() || !mm.native.as_str().is_empty() {
                continue;
            }
            if mm.name().map(|n| n.to_string()).as_deref() != Some(name) {
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
        Ok(Some(self.function_for(m, &c, &subst)?))
    }

    /// The source-declared `equals` of `concrete` (an `impl Equal`) and the interface of its argument.
    pub(crate) fn user_equals(
        &mut self,
        m: &mut Module,
        concrete: &ct::Ty,
    ) -> Result<Option<(ms_mir::ir::FuncId, IfaceId)>, Error> {
        let Some(f) = self.user_method(m, concrete, "equals")? else {
            return Ok(None);
        };
        let params = &m.funcs[f.index()].params;
        let [_, other] = params.as_slice() else {
            return Ok(None);
        };
        let TyKind::Iface(iface) = m.types.kind(other.ty).clone() else {
            return Ok(None);
        };
        Ok(Some((f, iface)))
    }

    /// The source-declared `hash` of `concrete` (an `impl Hashable`).
    pub(crate) fn user_hash(
        &mut self,
        m: &mut Module,
        concrete: &ct::Ty,
    ) -> Result<Option<ms_mir::ir::FuncId>, Error> {
        let Some(f) = self.user_method(m, concrete, "hash")? else {
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
        if let (TyKind::Alt(_), TyKind::Alt(_)) =
            (self.b.m.types.kind(have), self.b.m.types.kind(want))
        {
            return self.convert_result(x, concrete, want);
        }
        let TyKind::Iface(iface) = self.b.m.types.kind(want).clone() else {
            return Ok(x);
        };
        let vt = self.cx.vtable_for(self.b.m, concrete, have, iface)?;
        let o = self.owned(x);
        let v = self
            .b
            .emit(Op::IfaceNew, &[o], Imm::Vtable(vt), Some(want))
            .expect("iface");
        Ok(Val { v, own: true })
    }
}

/// How a case of a standard error type reads in `message()`.
pub(crate) enum Message {
    Text(&'static str),
    /// The case's first field.
    Payload,
    /// The message of the case's first field, itself a standard error of this name.
    Cause(&'static str),
}

impl Cx {
    /// A function computing a native `Error` implementation's message from a borrowed receiver.
    pub(crate) fn native_method_fn(
        &mut self,
        m: &mut Module,
        native: &str,
        concrete: &ct::Ty,
        data_ty: MTy,
    ) -> Result<ms_mir::ir::FuncId, Error> {
        if native != "errors/message" {
            return Err(Error::new(format!("unsupported native method {native}")));
        }
        self.message_fn(m, &concrete.to_string(), data_ty)
    }

    fn message_fn(
        &mut self,
        m: &mut Module,
        name: &str,
        data_ty: MTy,
    ) -> Result<ms_mir::ir::FuncId, Error> {
        let key = format!("native.message:{name}");
        if let Some(f) = self.helpers.get(&key) {
            return Ok(*f);
        }
        // Wrapped causes are named first: the builder borrows the module.
        let mut causes = Vec::new();
        if let (Some(table), TyKind::Alt(a)) =
            (crate::messages::table(name), m.types.kind(data_ty).clone())
        {
            for (i, c) in m.alts[a.index()].cases.clone().iter().enumerate() {
                if let Some((_, Message::Cause(inner))) = table.iter().find(|(n, _)| *n == c.name) {
                    let payload = c
                        .fields
                        .first()
                        .map(|f| f.1)
                        .ok_or_else(|| Error::new("cause without payload"))?;
                    causes.push((i, self.message_fn(m, inner, payload)?));
                }
            }
        }
        let ps = vec![Param {
            ty: data_ty,
            mode: Mode::Borrow,
        }];
        let mut b = FuncBuilder::new(m, &format!("{name}.message"), ps, MTy::STR);
        b.func_mut().linkage = Linkage::Internal;
        let recv = b.params()[0];
        let copy = |b: &mut FuncBuilder<'_>, v| {
            b.emit(Op::Copy, &[v], Imm::None, Some(MTy::STR))
                .expect("copy")
        };
        match (name, b.m.types.kind(data_ty).clone()) {
            ("TextError", TyKind::Rec(r)) => {
                let t = b.rec_get(r, 0, recv);
                let t = copy(&mut b, t);
                b.ret(Some(t));
            }
            ("MissingValue", TyKind::Alt(a)) => {
                let loc = b.alt_get(a, 0, 0, recv);
                let prefix = b.str_lit("missing value at ");
                let ext = crate::text::runtime_fn(
                    b.m,
                    "msrt_string_concat",
                    &[MTy::STR, MTy::STR],
                    MTy::STR,
                );
                let t = b.call_rt(ext, &[prefix, loc]);
                b.ret(Some(t));
            }
            (n, TyKind::Alt(a)) => {
                let table = crate::messages::table(n)
                    .ok_or_else(|| Error::new(format!("unsupported native message of {n}")))?;
                let cases = b.m.alts[a.index()].cases.clone();
                let tag = b.alt_tag(recv);
                let blocks: Vec<_> = cases.iter().map(|_| b.new_block()).collect();
                let arms: Vec<(i64, _)> = blocks
                    .iter()
                    .enumerate()
                    .map(|(i, k)| (i as i64, *k))
                    .collect();
                let default = blocks[0];
                b.switch(tag, &arms, default);
                for (i, c) in cases.iter().enumerate() {
                    b.seal_block(blocks[i]);
                    b.switch_to(blocks[i]);
                    let msg = table.iter().find(|(case, _)| *case == c.name);
                    let v = match msg {
                        Some((_, Message::Text(t))) => {
                            let l = b.str_lit(t);
                            copy(&mut b, l)
                        }
                        Some((_, Message::Payload)) => {
                            let p = b.alt_get(a, i as u32, 0, recv);
                            copy(&mut b, p)
                        }
                        Some((_, Message::Cause(_))) => {
                            let f = causes
                                .iter()
                                .find(|(k, _)| *k == i)
                                .map(|(_, f)| *f)
                                .ok_or_else(|| Error::new("cause message missing"))?;
                            let p = b.alt_get(a, i as u32, 0, recv);
                            b.call(f, &[p])
                        }
                        None => return Err(Error::new(format!("{n}.{} has no message", c.name))),
                    };
                    b.ret(Some(v));
                }
            }
            _ => return Err(Error::new(format!("unsupported native message of {name}"))),
        }
        let f = b.into_func();
        let id = m.add_func(f);
        self.helpers.insert(key, id);
        Ok(id)
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
        let res = self.b.declare_var(want, Mode::Own);
        let held = self.b.declare_var(
            self.ty_of(x.v),
            if x.own { Mode::Own } else { Mode::Borrow },
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
            let payload = self.b.alt_get(src, sc as u32, 0, cur);
            let mut p = Val {
                v: payload,
                own: false,
            };
            if is_error {
                p = self.fit_ty(p, &failure, want_err)?;
            }
            let po = self.owned(p);
            let out = self.b.alt_new(dst, dc as u32, &[po]);
            if x.own {
                self.drop_value(cur);
            }
            self.b.def_var(res, out);
            self.b.br(join, &[]);
        }
        self.b.seal_block(join);
        self.enter(join);
        let v = self.b.use_var(res);
        Ok(Val { v, own: true })
    }
}

impl Cx {
    /// A table for an `Error`-shaped interface over a message string (the testing failures).
    pub(crate) fn message_vtable(&mut self, m: &mut Module, iface: IfaceId) -> VtableId {
        let key = format!("vtable:message:{}", iface.0);
        if let Some(v) = self.vtables.get(&key) {
            return *v;
        }
        let sigs = m.ifaces[iface.index()].methods.clone();
        let mut methods = Vec::new();
        for s in &sigs {
            let ps = vec![Param {
                ty: MTy::PTR,
                mode: Mode::Borrow,
            }];
            let mut b = FuncBuilder::new(m, &format!("message.{}", s.name), ps, s.ret);
            b.func_mut().kind = FuncKind::Method;
            b.func_mut().linkage = Linkage::Internal;
            let p = b.params()[0];
            let text = b
                .emit(Op::Load, &[p], Imm::Ty(MTy::STR), Some(MTy::STR))
                .expect("load");
            let owned = b
                .emit(Op::Copy, &[text], Imm::None, Some(MTy::STR))
                .expect("copy");
            b.ret(Some(owned));
            let f = b.into_func();
            methods.push(m.add_func(f));
        }
        m.vtables.push(VtableDef {
            name: key.clone(),
            iface,
            methods,
            data_ty: MTy::STR,
        });
        let id = VtableId(m.vtables.len() as u32 - 1);
        self.vtables.insert(key, id);
        id
    }
}
