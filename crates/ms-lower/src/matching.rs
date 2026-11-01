//! `match` over alternatives and `Optional`.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::hir::Resolution;
use ms_mir::ir::{Block, Cc, Mode, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::*;

/// The case an arm names: `None` for the wildcard.
fn arm_case(path: &Expr) -> Option<String> {
    match &path.kind {
        ExprKind::Name(n) if n.as_str() == "_" => None,
        ExprKind::Name(n) => Some(n.to_string()),
        ExprKind::Member { name, .. } => Some(name.to_string()),
        ExprKind::Apply { left, .. } => arm_case(left),
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
            && self.locals.get(&b.uid).is_none_or(|l| l.slot.is_none())
        {
            return Ok(Some((self.local(&b)?.var, false)));
        }
        let x = self.expr(e)?;
        if self.dead {
            return Ok(None);
        }
        let t = self.ty_of(x.v);
        if !x.own && self.ownership_checked() {
            // A borrowed part: the checker keeps its origin unchanged while payloads borrow it,
            // so it is read in place and a lending function can hand back those payloads.
            let var = self.b.declare_var(t, Mode::Borrow);
            self.b.def_var(var, x.v);
            return Ok(Some((var, false)));
        }
        let owned = self.needs_drop(t);
        let var = self
            .b
            .declare_var(t, if owned { Mode::Own } else { Mode::Borrow });
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
        if hidden {
            let ty = self.b.var_ty(sv);
            let uid = self.adopt_hidden(sv, ty);
            // An owned temporary scrutinee (`match make():`) is the match's own: its payloads
            // are borrowed by the arms, so it closes when the match is left, `return` included.
            let sty = ms_check::types::sub(&self.hir.ty(scrutinee), &self.subst);
            let moved = arms.iter().any(|arm| {
                self.hir
                    .arm(arm)
                    .bindings
                    .iter()
                    .flatten()
                    .any(|b| self.cx.moved_payloads.contains(&b.uid))
            });
            if !moved && let Some(kind) = self.part_closer(&sty)? {
                self.hidden_closers.insert(uid, kind);
            }
        }
        let rty = self.emty(e)?;
        // A reference on every arm is joined as one: the checker holds its origins.
        let lent = self.cx.lent_matches.contains(&(self.hir.data.file, e.id));
        let owned = self.needs_drop(rty) && !lent;
        let res = self
            .b
            .declare_var(rty, if owned { Mode::Own } else { Mode::Borrow });
        let s = self.b.use_var(sv);
        let sty = self.ty_of(s);
        let kind = self.b.m.types.kind(sty).clone();
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
        for arm in arms {
            let blk = self.b.new_block();
            if literal && is_literal(&arm.path) {
                tests.push((blk, arm));
                arm_cases.push(None);
                blocks.push(blk);
                continue;
            }
            let case = match arm_case(&arm.path) {
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
                        TyKind::Alt(a) => self.b.m.alts[a.index()]
                            .cases
                            .iter()
                            .position(|c| c.name == name),
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
        for ((arm, blk), case) in arms.iter().zip(&blocks).zip(&arm_cases) {
            self.enter(*blk);
            self.push_scope();
            let facts = self.hir.arm(arm);
            for (i, b) in facts.bindings.iter().enumerate() {
                let Some(b) = b else { continue };
                if arm.chain && self.cx.exclusive(b.uid) {
                    // `c?.f()` changing the payload: `?N` names the payload of `c` itself.
                    let mut alias = self.alias_chain(scrutinee)?;
                    alias.steps.push(crate::alias::AStep::Some);
                    self.aliases.insert(b.uid, alias);
                    continue;
                }
                let cur = self.b.use_var(sv);
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
                self.bind_local(
                    b,
                    Val {
                        v: payload,
                        own: false,
                    },
                );
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
                        Some(x) if lent => x.v,
                        Some(x) => self.owned(x),
                        None => self.b.unit(),
                    };
                    self.b.def_var(res, v);
                }
            }
            self.flush_temps(mark);
            self.pop_scope();
            if !self.dead {
                self.b.br(join, &[]);
                live = true;
            }
        }
        self.b.seal_block(join);
        self.enter(join);
        self.dead = !live;
        self.pop_scope();
        if !live {
            return Ok(self.dummy(rty));
        }
        let v = self.b.use_var(res);
        Ok(Val { v, own: owned })
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
            let concrete = ms_check::types::sub(&concrete, &self.subst);
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

        self.enter(errb);
        let cur = self.b.use_var(rv);
        let payload = self.b.alt_get(a, err as u32, 0, cur);
        let want = self.b.m.alts[ra.index()].cases[ret_err].fields[0].1;
        let mut x = Val {
            v: payload,
            own: false,
        };
        if self.ty_of(payload) != want {
            let failure = self
                .hir
                .info(e)
                .propagated_error
                .ok_or_else(|| Error::new("try without a propagated error"))?;
            x = self.fit_ty(x, &ms_check::types::sub(&failure, &self.subst), want)?;
        }
        if !hidden
            && !x.own
            && self.b.func_mut().ret_borrowed
            && self.cx.view_wraps.contains(&(self.hir.data.file, e.id))
        {
            // The operand lends its error from this function's arguments: hand the reference on.
            let out = self.b.alt_view(ra, ret_err as u32, &[x.v]);
            self.emit_return(Some(Val { v: out, own: false }));
        } else if hidden && !x.own && self.ty_of(payload) == want {
            // The operand is ours: its error moves into the result and the rest is released.
            let po = self.b.alt_take(a, err as u32, 0, cur);
            self.b.alt_release(a, err as u32, 1, cur);
            let out = self.b.alt_new(ra, ret_err as u32, &[po]);
            self.emit_return(Some(Val { v: out, own: true }));
        } else {
            let po = self.owned(x);
            let out = self.b.alt_new(ra, ret_err as u32, &[po]);
            if hidden {
                self.drop_value(cur);
            }
            self.emit_return(Some(Val { v: out, own: true }));
        }

        self.enter(okb);
        let cur = self.b.use_var(rv);
        let payload = self.b.alt_get(a, ok as u32, 0, cur);
        if !hidden {
            // A part of a place: a consumer that keeps it takes its own copy, a reader reads
            // it in place, so a resource payload is never duplicated.
            return Ok(Val {
                v: payload,
                own: false,
            });
        }
        let po = self.owned(Val {
            v: payload,
            own: false,
        });
        self.drop_value(cur);
        Ok(self.val(po, true))
    }
}
