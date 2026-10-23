//! `@std/random.ms` operations over an `Entropy`: `secure_int`, `uuid_v4`, `float`, `shuffle`
//! and `choice`.
//!
//! The runtime owns the algorithms as a `Draw` (`ms-std-random`). The loop asks it how many bytes
//! to fetch, calls the source's own `bytes` (a runtime handle or a user-defined implementation),
//! and feeds the answer back until the draw is complete. A failing source is the result.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::native::NArg;
use crate::streamloop::{case, method};
use ms_check::hir::CallView;
use ms_mir::ir::{Cc, Mode, Value};
use ms_mir::types::{Ty as MTy, TyKind};

/// Which `msstd_random_draw_new` kind a native function starts.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Op {
    Int,
    Uuid,
    Float,
    Shuffle,
    Choice,
}

impl FnLower<'_> {
    /// `random.<native>` applied to a source of entropy.
    pub(crate) fn random_native(
        &mut self,
        e: &ms_syntax::ast::Expr,
        view: &CallView<'_>,
        native: &str,
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let result = self.emty(e)?;
        self.at(e.pos);
        self.random_with(native, &args, result)
    }

    /// `random.<native>` on evaluated arguments.
    pub(crate) fn random_with(
        &mut self,
        native: &str,
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let op = match native {
            "random/secure_int" => Op::Int,
            "random/uuid_v4" => Op::Uuid,
            "random/float" => Op::Float,
            "random/shuffle" => Op::Shuffle,
            _ => Op::Choice,
        };
        let find = |name: &str| args.iter().find(|a| a.name.as_str() == name).copied();
        let need = |name: &str| find(name).ok_or_else(|| Error::new(format!("missing {name}")));
        let entropy = need("entropy")?;
        let entropy = self.borrow(entropy.val);
        let list = match op {
            Op::Shuffle | Op::Choice => Some(self.borrow(need("values")?.val)),
            _ => None,
        };
        let (a, has, b) = match op {
            Op::Int => {
                let min = self.borrow(need("min")?.val);
                let (has, max) = self.optional_int(find("max_exclusive"))?;
                (min, has, max)
            }
            Op::Shuffle | Op::Choice => {
                let len = self.b.list_len(list.expect("a list operation"));
                (len, self.b.bconst(false), self.b.iconst(0))
            }
            Op::Uuid | Op::Float => (self.b.iconst(0), self.b.bconst(false), self.b.iconst(0)),
        };
        self.random_draw(op, entropy, list, [a, has, b], result)
    }

    fn random_draw(
        &mut self,
        op: Op,
        entropy: Value,
        list: Option<Value>,
        [a, has, b]: [Value; 3],
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::Alt(ra) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("a random operation returns a Result"));
        };
        let (ok, err) = (case(self, ra, "ok")?, case(self, ra, "error")?);
        let (iface, bytes) = method(self, entropy, "bytes")?;
        let kind = self.b.iconst(match op {
            Op::Int => 0,
            Op::Uuid => 1,
            Op::Float => 2,
            Op::Shuffle => 3,
            Op::Choice => 4,
        });
        let draw = self.call_runtime("msstd_random_draw_new", &[kind, a, has, b], MTy::PTR)?;
        // The operands live in variables of their own: the loop re-reads them each round.
        let hold = |s: &mut Self, v: Value| {
            let t = s.ty_of(v);
            let var = s.b.declare_var(t, Mode::Borrow);
            s.b.def_var(var, v);
            var
        };
        let entropy_var = hold(self, entropy);
        let draw_var = hold(self, draw);
        // A shuffle works on a copy of the list.
        let shuffled = match (op, list) {
            (Op::Shuffle, Some(l)) => {
                let t = self.ty_of(l);
                let copy = self.owned(Val { v: l, own: false });
                let var = self.b.declare_var(t, Mode::Own);
                self.b.def_var(var, copy);
                Some(var)
            }
            _ => None,
        };
        let res = self.b.declare_var(result, Mode::Own);
        let [header, body, got, exit, join] = std::array::from_fn(|_| self.b.new_block());
        self.b.br(header, &[]);

        // header: the draw says how many bytes it needs next.
        self.enter(header);
        self.b.poll();
        let draw = self.b.use_var(draw_var);
        let want = self.call_runtime("msstd_random_draw_want", &[draw], MTy::INT)?;
        let zero = self.b.iconst(0);
        let more = self.b.icmp(Cc::Ne, want, zero);
        self.b.br_if(more, body, &[], exit, &[]);
        self.b.seal_block(body);

        // body: fetch from the source; a failing source is the result.
        self.enter(body);
        let src = self.b.use_var(entropy_var);
        let r = self.b.call_method(iface, bytes, src, &[want]);
        let sa = self.alt_of(r)?;
        let (sok, serr) = (case(self, sa, "ok")?, case(self, sa, "error")?);
        let fail = self.b.new_block();
        let tag = self.b.alt_tag(r);
        let kerr = self.b.iconst(serr as i64);
        let is_err = self.b.icmp(Cc::Eq, tag, kerr);
        self.b.br_if(is_err, fail, &[], got, &[]);
        self.b.seal_block(fail);
        self.b.seal_block(got);
        self.enter(fail);
        let draw = self.b.use_var(draw_var);
        self.call_runtime("msstd_random_draw_free", &[draw], MTy::UNIT)?;
        if let Some(var) = shuffled {
            let l = self.b.use_var(var);
            self.drop_value(l);
        }
        self.fail_with(r, sa, serr, ra, err, res, join)?;

        // got: the draw consumes the bytes; a shuffle swaps when one of its positions is chosen.
        self.enter(got);
        let data = self.b.alt_get(sa, sok as u32, 0, r);
        let draw = self.b.use_var(draw_var);
        let swap = self.call_runtime("msstd_random_draw_push", &[draw, data], MTy::BOOL)?;
        self.drop_value(r);
        if let Some(var) = shuffled {
            let (do_swap, next) = (self.b.new_block(), self.b.new_block());
            self.b.br_if(swap, do_swap, &[], next, &[]);
            self.b.seal_block(do_swap);
            self.b.seal_block(next);
            self.enter(do_swap);
            let draw = self.b.use_var(draw_var);
            let (zero, one) = (self.b.iconst(0), self.b.iconst(1));
            let i = self.call_runtime("msstd_random_draw_swap", &[draw, zero], MTy::INT)?;
            let j = self.call_runtime("msstd_random_draw_swap", &[draw, one], MTy::INT)?;
            let cur = self.b.use_var(var);
            let at_i = self.b.list_get(cur, i);
            let at_j = self.b.list_get(cur, j);
            let copy_i = self.owned(Val {
                v: at_i,
                own: false,
            });
            let copy_j = self.owned(Val {
                v: at_j,
                own: false,
            });
            let l1 = self.b.list_set(cur, i, copy_j);
            let l2 = self.b.list_set(l1, j, copy_i);
            self.b.def_var(var, l2);
            self.b.br(next, &[]);
            self.enter(next);
        }
        self.b.br(header, &[]);
        self.b.seal_block(header);

        // exit: the draw's outcome.
        self.b.seal_block(exit);
        self.enter(exit);
        let draw = self.b.use_var(draw_var);
        let code = self.status_code("msstd_random_draw_status", &[draw])?;
        let zero = self.b.iconst(0);
        let good = self.b.icmp(Cc::Eq, code, zero);
        let value_ty = self.b.m.alts[ra.index()].cases[ok].fields[0].1;
        let out = self.two_ways(
            good,
            result,
            &mut |s| {
                let draw = s.b.use_var(draw_var);
                let v = match op {
                    Op::Int => s.call_runtime("msstd_random_draw_int", &[draw], MTy::INT)?,
                    Op::Float => s.call_runtime("msstd_random_draw_float", &[draw], MTy::FLOAT)?,
                    Op::Uuid => s.call_runtime("msstd_random_draw_text", &[draw], MTy::STR)?,
                    Op::Shuffle => s.b.use_var(shuffled.expect("a shuffle copy")),
                    Op::Choice => {
                        let l = list.expect("a choice list");
                        s.random_choice(draw, l, value_ty)?
                    }
                };
                Ok(Some(s.b.alt_new(ra, ok as u32, &[v])))
            },
            &mut |s| {
                if let Some(var) = shuffled {
                    let l = s.b.use_var(var);
                    s.drop_value(l);
                }
                let et = s.b.m.alts[ra.index()].cases[err].fields[0].1;
                let TyKind::Alt(ea) = s.b.m.types.kind(et).clone() else {
                    return Err(Error::new("a runtime status needs an error alternative"));
                };
                let cases = s.status_cases(ea);
                let e = s.status_error(ea, code, &cases, Some("msstd_random_failure_message"))?;
                Ok(Some(s.b.alt_new(ra, err as u32, &[e])))
            },
        )?;
        let draw = self.b.use_var(draw_var);
        self.call_runtime("msstd_random_draw_free", &[draw], MTy::UNIT)?;
        self.b.def_var(res, out.v);
        self.b.br(join, &[]);

        self.b.seal_block(join);
        self.enter(join);
        let v = self.b.use_var(res);
        Ok(Val { v, own: true })
    }

    /// The `Optional` item `choice` picked: the chosen index, or none for an empty list.
    fn random_choice(&mut self, draw: Value, list: Value, optional: MTy) -> Result<Value, Error> {
        let idx = self.call_runtime("msstd_random_draw_int", &[draw], MTy::INT)?;
        let zero = self.b.iconst(0);
        let present = self.b.icmp(Cc::Ge, idx, zero);
        let picked = self.two_ways(
            present,
            optional,
            &mut |s| {
                let item = s.b.list_get(list, idx);
                let item = s.owned(Val {
                    v: item,
                    own: false,
                });
                Ok(Some(s.b.opt_some(item)))
            },
            &mut |s| Ok(Some(s.b.opt_none(optional))),
        )?;
        Ok(picked.v)
    }
}
