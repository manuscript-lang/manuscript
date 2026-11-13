//! `match` over alternatives and `Optional`.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::api::ast::*;
use ms_check::api::hir::Resolution;
use ms_mir::ir::{Block, Cc, Mode, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};

/// The case an arm names: `None` for the wildcard.
fn arm_case(syms: ms_check::api::Names, path: &Expr) -> Option<String> {
    match &path.kind {
        ExprKind::Name(n) if syms.str(n) == "_" => None,
        ExprKind::Name(n) => Some(syms.str(n).to_string()),
        ExprKind::Member { name, .. } => Some(syms.str(name).to_string()),
        ExprKind::Apply { left, .. } => arm_case(syms, left),
        _ => None,
    }
}

/// Whether a match arm names a literal value instead of a case.
pub(crate) fn is_literal(path: &Expr) -> bool {
    match &path.kind {
        ExprKind::Number(_) | ExprKind::Text(_) | ExprKind::Bool(_) => true,
        ExprKind::Unary {
            op: UnaryOp::Neg,
            operand,
        } => matches!(operand.kind, ExprKind::Number(_)),
        _ => false,
    }
}

impl FnLower<'_> {
    /// A variable that always holds the value of `e`, for use across blocks.
    /// The flag says the variable owns a hidden copy that must be dropped afterwards.
    pub fn hold(&mut self, e: &Expr) -> Result<Option<(ms_mir::builder::Var, bool)>, Error> {
        if let (ExprKind::Name(_), Resolution::Local(b)) = (&e.kind, self.hir.resolution(e))
            && !self.aliases.contains_key(&b.uid)
        {
            if self.moves_at(b.uid, e.id) && !self.dead {
                // The value leaves the binding here: the holder owns it.
                let l = self.local(&b)?;
                let v = self.take_local(b.uid, &l);
                self.moved_closer(b.uid, e);
                let var = self.b.declare_var(l.ty, Mode::Move);
                self.b.def_var(var, v);
                return Ok(Some((var, true)));
            }
            if let Some(l) = self.locals.get(&b.uid).copied() {
                if l.slot.is_none() && !l.opt {
                    return Ok(Some((l.var, false)));
                }
                // A binding that lives in memory, or that a move may have emptied, is read in
                // place: the match borrows it and leaves it to its scope end.
                let v = self.local_get(&l);
                let var = self.b.declare_var(l.ty, Mode::Borrow);
                self.b.def_var(var, v);
                return Ok(Some((var, false)));
            }
        }
        let x = self.expr(e)?;
        if self.dead {
            return Ok(None);
        }
        let t = self.ty_of(x.v);
        self.hold_declared = self.boundary_reads.contains(&x.v);
        if !x.own {
            // A borrowed part: the checker keeps its origin unchanged while payloads borrow it,
            // so it is read in place and a borrow-returning function can hand back those payloads.
            let var = self.b.declare_var(t, Mode::Borrow);
            self.b.def_var(var, x.v);
            return Ok(Some((var, false)));
        }
        let owned = self.needs_drop(t);
        let var = self
            .b
            .declare_var(t, if owned { Mode::Move } else { Mode::Borrow });
        let v = self.owned(x);
        self.b.def_var(var, v);
        Ok(Some((var, true)))
    }

    pub fn match_expr(&mut self, e: &Expr, scrutinee: &Expr, arms: &[Arm]) -> Result<Val, Error> {
        // The scope owns a hidden copy of the scrutinee, so an arm that returns releases it.
        self.push_scope();
        let Some((sv, hidden)) = self.hold(scrutinee)? else {
            self.pop_scope();
            return Ok(self.dummy(MTy::UNIT));
        };
        let scrut_declared = std::mem::take(&mut self.hold_declared);
        let sty = self.b.var_ty(sv);
        let kind = self.b.m.types.kind(sty).clone();
        // An owned scrutinee (`match make():`, or a local the match moving_params) is the match's
        // own: an arm that names its parts takes them out of it, and every other arm drops it
        // (closing what it holds) when the arm ends; `return` and the like close and drop it
        // on the way out. It lives in memory so that each path reads its own value.
        let mut owned_uid = None;
        if hidden {
            let ty = self.b.var_ty(sv);
            let uid = self.adopt_hidden(sv, ty);
            let cty = ms_check::api::types::sub(&self.hir.ty(scrutinee), &self.subst);
            let closer = self.part_closer(&cty)?;
            if !self.own_hidden(uid, closer.as_ref(), false) {
                let parts = matches!(kind, TyKind::Alt(_) | TyKind::Opt(_))
                    && arms
                        .iter()
                        .any(|arm| self.hir.arm(arm).bindings.iter().any(|b| b.is_some()));
                if parts || closer.is_some() {
                    self.slotted.insert(uid);
                    self.slotify(uid);
                }
                if let Some(kind) = closer {
                    self.own_hidden_slot(uid, &kind);
                }
            }
            owned_uid = Some(uid);
        }
        // The value the arms are chosen by: a read of the scrutinee in place.
        let s = match owned_uid {
            Some(uid) => {
                let l = self.locals[&uid];
                self.local_get(&l)
            }
            None => self.b.use_var(sv),
        };
        let rty = self.emty(e)?;
        // A reference on every arm is joined as one: the checker holds its origins.
        let borrowed = self.cx.fact(
            self.hir.data.file,
            e.id,
            ms_check::api::ownership::Fact::BorrowedMatch,
        );
        let owned = self.needs_drop(rty) && !borrowed;
        let res = self
            .b
            .declare_var(rty, if owned { Mode::Move } else { Mode::Borrow });
        let literal = self.b.m.types.is_int(sty) || sty == MTy::STR || sty == MTy::BOOL;
        let tag = match &kind {
            TyKind::Alt(_) => self.b.alt_tag(s),
            TyKind::Opt(_) => {
                let p = self.b.opt_is_some(s);
                let (one, zero) = (self.b.iconst(1), self.b.iconst(0));
                self.b.select(p, one, zero)
            }
            TyKind::Iface(_) => self.b.iconst(0),
            _ if literal => self.b.iconst(0),
            _ => return Err(Error::new("match on this type is not supported yet")),
        };
        let join = self.b.new_block();
        let mut blocks = Vec::new();
        let mut cases: Vec<(i64, Block)> = Vec::new();
        let mut default: Option<Block> = None;
        let mut arm_cases: Vec<Option<usize>> = Vec::new();
        let by_type = matches!(kind, TyKind::Iface(_));
        let mut tests: Vec<(Block, &Arm)> = Vec::new();
        // Tag of each case by name (the first on a duplicate): an arm looks its case up here
        // instead of scanning every case, which made a match over thousands of cases quadratic.
        let mut case_tags: std::collections::HashMap<String, usize> = Default::default();
        if let TyKind::Alt(a) = &kind {
            for (tag, c) in self.b.m.alts[a.index()].cases.iter().enumerate() {
                case_tags.entry(c.name.clone()).or_insert(tag);
            }
        }
        for arm in arms {
            let blk = self.b.new_block();
            if literal && is_literal(&arm.path) {
                tests.push((blk, arm));
                arm_cases.push(None);
                blocks.push(blk);
                continue;
            }
            let name = if arm.bare && matches!(kind, TyKind::Opt(_)) {
                Some("some".to_string())
            } else {
                arm_case(self.syms, &arm.path)
            };
            let case = match name {
                _ if by_type => {
                    // A concrete type pattern on a contract value; `_` is the fallback.
                    match self.hir.arm(arm).contract {
                        Some(_) => Some(0),
                        None => {
                            default.get_or_insert(blk);
                            None
                        }
                    }
                }
                None => {
                    default.get_or_insert(blk);
                    None
                }
                Some(name) => {
                    let k = match &kind {
                        TyKind::Alt(_) => case_tags.get(name.as_str()).copied(),
                        TyKind::Opt(_) => match name.as_str() {
                            "none" => Some(0),
                            "some" => Some(1),
                            _ => None,
                        },
                        _ => None,
                    }
                    .ok_or_else(|| Error::new(format!("unknown match case {name}")))?;
                    if !cases.iter().any(|(c, _)| *c == k as i64) {
                        cases.push((k as i64, blk));
                    }
                    Some(k)
                }
            };
            arm_cases.push(case);
            blocks.push(blk);
        }
        let fallback = default.unwrap_or_else(|| self.b.new_block());
        if literal {
            for (blk, arm) in &tests {
                let lit = self.expr(&arm.path)?;
                let eq = self.equal(sty, Val { v: s, own: false }, lit)?;
                let next = self.b.new_block();
                self.b.br_if(eq, *blk, &[], next, &[]);
                self.b.seal_block(next);
                self.b.switch_to(next);
            }
            self.b.br(fallback, &[]);
        } else if by_type {
            self.type_tests(s, arms, &blocks, fallback)?;
        } else {
            self.b.switch(tag, &cases, fallback);
        }
        for b in &blocks {
            self.b.seal_block(*b);
        }
        if default.is_none() {
            self.b.seal_block(fallback);
            self.b.switch_to(fallback);
            self.b.unreachable();
        }
        let mut live = false;
        let closed_before = self.closed_on_path.clone();
        for ((arm, blk), case) in arms.iter().zip(&blocks).zip(&arm_cases) {
            self.enter(*blk);
            self.push_scope();
            self.closed_on_path = closed_before.clone();
            let facts = self.hir.arm(arm);
            // A borrowed case of a borrowing variant stays in the scrutinee: its payload is
            // bound as a borrow, and the scrutinee drops only the cases it owns.
            let borrowed_case = matches!((&kind, case), (TyKind::Alt(a), Some(k))
                if self.b.m.alts[a.index()].borrows(*k));
            let takes = owned_uid.is_some()
                && !by_type
                && !borrowed_case
                && case.is_some()
                && facts.bindings.iter().any(|b| b.is_some());
            if let (Some(uid), true, Some(k)) = (owned_uid, takes, case) {
                let l = self.locals[&uid];
                let cur = self.local_take(&l);
                // The pass stops owning the scrutinee: its parts are taken out below.
                if self.raw_owned.contains(&uid) {
                    let owner = l.slot.unwrap_or(cur);
                    self.b
                        .emit(Op::ScopeDisown, &[owner], ms_mir::ir::Imm::None, None);
                }
                self.take_payloads(&kind, *k, cur, &facts.bindings)?;
                self.closed_on_path.insert(uid);
            }
            for (i, b) in facts.bindings.iter().enumerate() {
                if takes {
                    break;
                }
                let Some(b) = b else { continue };
                if arm.chain && self.cx.exclusive(b.uid) {
                    // `c?.f()` changing the payload: `?N` names the payload of `c` itself.
                    let mut alias = self.alias_chain(scrutinee)?;
                    alias.steps.push(crate::alias::AStep::Some);
                    self.aliases.insert(b.uid, alias);
                    continue;
                }
                let cur = match owned_uid {
                    // An owned scrutinee lives in its slot; a borrowed case is read in place.
                    Some(uid) => {
                        let l = self.locals[&uid];
                        self.local_get(&l)
                    }
                    None => self.b.use_var(sv),
                };
                let payload = match (&kind, case) {
                    (TyKind::Iface(_), Some(_)) => {
                        let concrete = facts
                            .contract
                            .clone()
                            .ok_or_else(|| Error::new("type pattern without a type"))?;
                        let data_ty = self.mty(&concrete)?;
                        let data = self.b.emit(
                            Op::IfaceData,
                            &[cur],
                            ms_mir::ir::Imm::None,
                            Some(MTy::PTR),
                        );
                        self.b
                            .emit(
                                Op::Load,
                                &[data.expect("data")],
                                ms_mir::ir::Imm::Ty(data_ty),
                                Some(data_ty),
                            )
                            .expect("load")
                    }
                    (TyKind::Alt(a), Some(k)) => self.b.alt_get(*a, *k as u32, i as u32, cur),
                    (TyKind::Opt(_), Some(_)) => self.b.opt_get(cur),
                    _ => return Err(Error::new("payload binding on a wildcard arm")),
                };
                if scrut_declared {
                    // A part of a payload an `Optional`/`Result` read borrows is the same declared read.
                    self.boundary_reads.insert(payload);
                }
                if by_type && owned_uid.is_some() {
                    // The checker moves the payload out of the last-use scrutinee; the box is
                    // dropped whole at scope end, so the move is realized as a declared copy.
                    self.boundary_reads.insert(payload);
                }
                self.scrutinee_lives = owned_uid.is_none();
                self.bind_local(
                    b,
                    Val {
                        v: payload,
                        own: false,
                    },
                );
                self.scrutinee_lives = false;
            }
            self.stmts(&arm.body)?;
            let mark = self.temps.len();
            if !self.dead {
                let x = match &arm.value {
                    Some(v) => Some(self.expr(v)?),
                    None => None,
                };
                if !self.dead {
                    let v = match x {
                        Some(x) if borrowed => x.v,
                        // An optional chain wraps the part it reaches in an `Optional`.
                        Some(x) if arm.chain => self.owned_boundary(x),
                        Some(x) => self.owned(x),
                        None => self.b.unit(),
                    };
                    self.b.def_var(res, v);
                }
            }
            self.flush_temps(mark);
            if let (Some(uid), false, false) = (owned_uid, takes, self.dead)
                && !self.raw_owned.contains(&uid)
            {
                // This arm left the scrutinee whole: it goes with the arm.
                let l = self.locals[&uid];
                let v = self.local_take(&l);
                self.drop_value(v);
                self.closed_on_path.insert(uid);
            }
            self.pop_scope();
            if !self.dead {
                self.b.br(join, &[]);
                live = true;
            }
        }
        self.closed_on_path = closed_before;
        if let Some(uid) = owned_uid {
            // Every path into the join consumed the scrutinee.
            self.closed_on_path.insert(uid);
        }
        self.b.seal_block(join);
        self.enter(join);
        self.dead = !live;
        self.pop_scope();
        if let Some(uid) = owned_uid {
            self.closed_on_path.remove(&uid);
        }
        if !live {
            return Ok(self.dummy(rty));
        }
        let v = self.b.use_var(res);
        Ok(Val { v, own: owned })
    }

    /// Takes the payload fields of case `k` out of the owned scrutinee `cur` into the arm's
    /// bindings; a field the arm does not name (`_`) closes and drops here. What is left of the
    /// scrutinee is released.
    fn take_payloads(
        &mut self,
        kind: &TyKind,
        k: usize,
        cur: Value,
        bindings: &[Option<ms_check::api::types::BindingRef>],
    ) -> Result<(), Error> {
        match kind {
            TyKind::Alt(a) => {
                let n = self.b.m.alts[a.index()].cases[k].fields.len();
                let mut fields = Vec::with_capacity(n);
                for i in 0..n {
                    fields.push(self.b.alt_take(*a, k as u32, i as u32, cur));
                }
                let mask = if n >= 32 { u32::MAX } else { (1u32 << n) - 1 };
                self.b.alt_release(*a, k as u32, mask, cur);
                // Named fields become bindings before omitted fields close, just as in a
                // type pattern. The omitted fields close in reverse declaration order.
                for (i, &v) in fields.iter().enumerate() {
                    if let Some(b) = bindings.get(i).and_then(|b| b.as_ref()) {
                        self.bind_payload(Some(b), v)?;
                    }
                }
                for (i, v) in fields.into_iter().enumerate().rev() {
                    if bindings.get(i).is_none_or(|b| b.is_none()) {
                        self.bind_payload(None, v)?;
                    }
                }
            }
            TyKind::Opt(_) => {
                let v = self.b.opt_unbox(cur);
                self.bind_payload(bindings.first().and_then(|b| b.as_ref()), v)?;
            }
            _ => return Err(Error::new("payloads taken from a value without cases")),
        }
        Ok(())
    }

    /// Binds the owned payload `v` to `b`, closing it at the end of its scope when it is a
    /// resource nothing takes on; an unnamed payload closes and drops now.
    pub(crate) fn bind_payload(
        &mut self,
        b: Option<&ms_check::api::types::BindingRef>,
        v: Value,
    ) -> Result<(), Error> {
        let x = Val { v, own: true };
        let Some(b) = b else {
            let ty = self.ty_of(v);
            if self.holds(ty) {
                let mut v = v;
                if let Some(kind) = self.part_closer_mir(ty)? {
                    v = self.close_discarded_kind(&kind, v);
                }
                self.drop_value(v);
            }
            return Ok(());
        };
        if self
            .cx
            .ownership
            .binding_facts
            .has(b.uid, ms_check::api::ownership::BindingFact::ImplicitClose)
        {
            let cty = ms_check::api::types::sub(&b.ty, &self.subst);
            if let Some(kind) = self.part_closer(&cty)? {
                return self.bind_closing_kind(b, x, kind);
            }
        }
        self.bind_local(b, x);
        Ok(())
    }

    /// Branches to the first arm whose concrete type the interface value holds.
    fn type_tests(
        &mut self,
        s: Value,
        arms: &[Arm],
        blocks: &[Block],
        fallback: Block,
    ) -> Result<(), Error> {
        let TyKind::Iface(iface) = self.b.m.types.kind(self.ty_of(s)).clone() else {
            return Err(Error::new("type patterns need an interface value"));
        };
        for (arm, blk) in arms.iter().zip(blocks) {
            let Some(concrete) = self.hir.arm(arm).contract else {
                self.b.br(*blk, &[]);
                return Ok(());
            };
            let concrete = ms_check::api::types::sub(&concrete, &self.subst);
            let vt = self
                .cx
                .vtable_id(self.b.m, &concrete, iface, self.evidence())?;
            let hit = self
                .b
                .emit(
                    Op::IfaceIs,
                    &[s],
                    ms_mir::ir::Imm::Vtable(vt),
                    Some(MTy::BOOL),
                )
                .expect("test");
            let next = self.b.new_block();
            self.b.br_if(hit, *blk, &[], next, &[]);
            self.b.seal_block(next);
            self.b.switch_to(next);
        }
        self.b.br(fallback, &[]);
        Ok(())
    }

    /// The uid of the plain local `operand` names when this function owns it outright (no
    /// closer, flag, or other scope bookkeeping): its value can be moved out on a path that
    /// returns.
    fn exiting_owned_local(&self, operand: &Expr, hidden: bool) -> Option<usize> {
        let (ExprKind::Name(_), Resolution::Local(b)) =
            (&operand.kind, self.hir.resolution(operand))
        else {
            return None;
        };
        let uid = b.uid;
        let plain = !hidden
            && self.locals.contains_key(&uid)
            && (self.raw_owned.contains(&uid) || self.scopes.iter().any(|s| s.contains(&uid)))
            && !self.slotted.contains(&uid)
            && !self.aliases.contains_key(&uid)
            && !self.must_move.contains(&uid)
            && !self.held.contains_key(&uid);
        plain.then_some(uid)
    }

    /// `try x`: the `ok` payload, or an early return of the `error` payload.
    pub fn try_expr(&mut self, e: &Expr, operand: &Expr) -> Result<Val, Error> {
        let Some((rv, hidden)) = self.hold(operand)? else {
            return Ok(self.dummy(MTy::UNIT));
        };
        // `try r` at the last use of a closing binding hands its payload on: the binding no
        // longer closes it.
        if let (ExprKind::Name(_), Resolution::Local(b)) =
            (&operand.kind, self.hir.resolution(operand))
        {
            self.moved_closer(b.uid, operand);
        }
        let r = self.b.use_var(rv);
        let rty = self.ty_of(r);
        let TyKind::Alt(a) = self.b.m.types.kind(rty).clone() else {
            return Err(Error::new("try on a non-Result"));
        };
        let case_of = |m: &ms_mir::ir::Module, alt: ms_mir::types::AltId, name: &str| {
            m.alts[alt.index()]
                .cases
                .iter()
                .position(|c| c.name == name)
        };
        let ok = case_of(self.b.m, a, "ok").ok_or_else(|| Error::new("try on a non-Result"))?;
        let err = case_of(self.b.m, a, "error").ok_or_else(|| Error::new("try on a non-Result"))?;
        let TyKind::Alt(ra) = self.b.m.types.kind(self.result_ty()).clone() else {
            return Err(Error::new(
                "try in a function that does not return a Result",
            ));
        };
        let ret_err = case_of(self.b.m, ra, "error")
            .ok_or_else(|| Error::new("try in a function that does not return a Result"))?;
        let tag = self.b.alt_tag(r);
        let k = self.b.iconst(err as i64);
        let is_err = self.b.icmp(Cc::Eq, tag, k);
        let (errb, okb) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(is_err, errb, &[], okb, &[]);
        self.b.seal_block(errb);
        self.b.seal_block(okb);

        // The operand lends its error (`try g(v)` of a function with a borrowing result): the
        // error is not ours to take.
        let borrowed_err = self.b.m.alts[a.index()].borrows(err);
        let ra_borrows_err = self.b.m.alts[ra.index()].borrows(ret_err);
        self.enter(errb);
        let cur = self.b.use_var(rv);
        let payload = self.b.alt_get(a, err as u32, 0, cur);
        let want = self.b.m.alts[ra.index()].cases[ret_err].fields[0].1;
        let x = Val {
            v: payload,
            own: false,
        };
        if !hidden
            && !x.own
            && (self.b.func_mut().ret_borrowed || self.ret_borrowing())
            && self.cx.fact(
                self.hir.data.file,
                e.id,
                ms_check::api::ownership::Fact::ViewWrap,
            )
        {
            // The operand returns a borrow of its error from this function's arguments: hand the reference on.
            let out = self.b.alt_view(ra, ret_err as u32, &[x.v]);
            // In a borrowing variant the borrowed error is part of an owned result.
            let own = self.ret_borrowing();
            self.emit_return(Some(Val { v: out, own }));
        } else if borrowed_err && ra_borrows_err && self.ty_of(payload) == want {
            // The operand's error is a borrow of the arguments and this function's result
            // borrows its error the same way: hand the reference on. The operand owns nothing
            // else on this path.
            let out = self.b.alt_view(ra, ret_err as u32, &[x.v]);
            if hidden {
                self.drop_value(cur);
            }
            self.emit_return(Some(Val { v: out, own: true }));
        } else if hidden && !x.own && !borrowed_err && self.ty_of(payload) == want {
            // The operand is ours: its error moves into the result and the rest is released.
            let po = self.b.alt_take(a, err as u32, 0, cur);
            self.b.alt_release(a, err as u32, 1, cur);
            let out = self.b.alt_new(ra, ret_err as u32, &[po]);
            self.emit_return(Some(Val { v: out, own: true }));
        } else if let Some(uid) = self.exiting_owned_local(operand, hidden)
            && !borrowed_err
            && self.ty_of(payload) == want
        {
            // A named local the function owns: this path leaves the function, so the local is
            // never read again here. Its error moves into the result, the rest is released and
            // the return skips the local's drop.
            let po = self.b.alt_take(a, err as u32, 0, cur);
            self.b.alt_release(a, err as u32, 1, cur);
            let out = self.b.alt_new(ra, ret_err as u32, &[po]);
            let before = self.closed_on_path.clone();
            self.closed_on_path.insert(uid);
            self.emit_return(Some(Val { v: out, own: true }));
            self.closed_on_path = before;
        } else {
            let po = self.owned_boundary(x);
            let out = self.b.alt_new(ra, ret_err as u32, &[po]);
            if hidden {
                self.drop_value(cur);
            }
            self.emit_return(Some(Val { v: out, own: true }));
        }

        self.enter(okb);
        let cur = self.b.use_var(rv);
        let payload = self.b.alt_get(a, ok as u32, 0, cur);
        if hidden && self.b.m.alts[a.index()].borrows(ok) {
            // The operand's `ok` payload is a borrow of the arguments it was called with: it
            // stays where it is, and the operand (which owns nothing else here) is dropped with
            // the statement.
            self.pend_temp(cur);
            return Ok(Val {
                v: payload,
                own: false,
            });
        }
        if !hidden {
            // A part of a place: a consumer that keeps it takes its own copy, a reader reads
            // it in place, so a resource payload is never duplicated.
            return Ok(Val {
                v: payload,
                own: false,
            });
        }
        // The result is ours: its payload moves out and the rest is released.
        let po = self.b.alt_take(a, ok as u32, 0, cur);
        self.b.alt_release(a, ok as u32, 1, cur);
        Ok(self.val(po, true))
    }
}
