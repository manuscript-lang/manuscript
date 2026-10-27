//! `@std/test.ms` expectations, lowered inline.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::text::runtime_fn;
use ms_check::hir::CallView;
use ms_mir::ir::{Cc, Imm, Op, Value};
use ms_mir::types::{AltId, Ty as MTy, TyKind};
use ms_syntax::ast::Expr;

impl FnLower<'_> {
    /// The `ok` and `error` case indexes of a Result alternative.
    fn result_cases(&self, rty: MTy) -> Result<(AltId, u32, u32), Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(rty).clone() else {
            return Err(Error::new("not a Result"));
        };
        let find = |n: &str| {
            self.b.m.alts[a.index()]
                .cases
                .iter()
                .position(|c| c.name == n)
                .map(|i| i as u32)
        };
        match (find("ok"), find("error")) {
            (Some(ok), Some(err)) => Ok((a, ok, err)),
            _ => Err(Error::new("not a Result")),
        }
    }

    /// `ok(payload)` of the Result type (payload owned).
    pub(crate) fn testing_ok(&mut self, rty: MTy, payload: Value) -> Result<Value, Error> {
        let (a, ok, _) = self.result_cases(rty)?;
        Ok(self.b.alt_new(a, ok, &[payload]))
    }

    /// Remembers the source position that built a failure so the test report can name it.
    fn record_failure_site(&mut self, message: Value) {
        let loc = self.b.loc();
        let Some(file) = self.b.m.files.get(loc.file as usize) else {
            return;
        };
        let site = format!("{file}:{}:{}", loc.line, loc.col);
        let site = self.b.str_lit(&site);
        let ext = runtime_fn(self.b.m, "msrt_test_site", &[MTy::STR, MTy::STR], MTy::UNIT);
        self.b.call_rt(ext, &[message, site]);
    }

    /// `error(Error)` carrying `message` (owned).
    fn testing_fail(&mut self, rty: MTy, message: Value) -> Result<Value, Error> {
        let (a, _, err) = self.result_cases(rty)?;
        let it = self.b.m.alts[a.index()].cases[err as usize].fields[0].1;
        let TyKind::Iface(iface) = self.b.m.types.kind(it).clone() else {
            return Err(Error::new("testing failures need an Error interface"));
        };
        let vt = self.cx.message_vtable(self.b.m, iface);
        self.record_failure_site(message);
        let v = self
            .b
            .emit(Op::IfaceNew, &[message], Imm::Vtable(vt), Some(it))
            .expect("iface");
        Ok(self.b.alt_new(a, err, &[v]))
    }

    /// Concatenates text pieces into one owned string, releasing owned pieces.
    fn cat(&mut self, parts: &[Val]) -> Result<Val, Error> {
        let mut acc: Option<Val> = None;
        for p in parts {
            acc = Some(match acc {
                None => {
                    if p.own {
                        *p
                    } else {
                        let v = self
                            .b
                            .emit(Op::Copy, &[p.v], Imm::None, Some(MTy::STR))
                            .expect("copy");
                        Val { v, own: true }
                    }
                }
                Some(a) => {
                    let r = self.call_runtime("msrt_string_concat", &[a.v, p.v], MTy::STR)?;
                    self.drop_value(a.v);
                    if p.own {
                        self.drop_value(p.v);
                    }
                    Val { v: r, own: true }
                }
            });
        }
        acc.ok_or_else(|| Error::new("empty message"))
    }

    pub(crate) fn lit(&mut self, text: &str) -> Val {
        let v = self.b.str_lit(text);
        Val { v, own: false }
    }

    /// `Result[Unit, Error]`: `ok(unit)` when `cond`, else `error(message())`.
    fn expectation(
        &mut self,
        cond: Value,
        rty: MTy,
        message: &mut dyn FnMut(&mut Self) -> Result<Val, Error>,
    ) -> Result<Val, Error> {
        self.two_ways(
            cond,
            rty,
            &mut |s| {
                let u = s.b.unit();
                Ok(Some(s.testing_ok(rty, u)?))
            },
            &mut |s| {
                let m = message(s)?;
                Ok(Some(s.testing_fail(rty, m.v)?))
            },
        )
    }

    /// An expectation of `@std/test.ms`.
    pub fn testing_native(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        name: &str,
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let rty = self.emty(e)?;
        self.at(e.pos);
        let name = name.replacen("assert_", "expect_", 1);
        if name == "skip" {
            // A fault whose message names the skip; the report recovers the reason.
            let marker = self.lit(crate::SKIP_MARKER);
            let msg = self.cat(&[marker, args[0].val])?;
            let ext = self.b.m.add_extern(ms_mir::ir::ExternDef {
                name: "msrt_fault_string".to_string(),
                params: vec![ms_mir::ir::Param {
                    ty: MTy::STR,
                    mode: ms_mir::ir::Mode::Borrow,
                }],
                ret: MTy::UNIT,
                noreturn: true,
                pure_: false,
                fresh: false,
            });
            self.b.call_rt(ext, &[msg.v]);
            return Ok(self.dummy(MTy::UNIT));
        }
        if name == "fail" {
            // The message is consumed, not borrowed.
            let m = self.cat(&[args[0].val])?;
            let v = self.testing_fail(rty, m.v)?;
            return Ok(Val { v, own: true });
        }
        let vals: Vec<Value> = args.iter().map(|a| self.borrow(a.val)).collect();
        match name.as_str() {
            "expect_true" | "expect_false" => {
                let want = name == "expect_true";
                let cond = if want {
                    vals[0]
                } else {
                    self.b.unop(Op::Not, vals[0])
                };
                let text = if want {
                    "expected true, got false"
                } else {
                    "expected false, got true"
                };
                self.expectation(cond, rty, &mut |s| {
                    let l = s.lit(text);
                    s.cat(&[l])
                })
            }
            "expect_equal" | "expect_not_equal" => {
                let t = self.ty_of(vals[0]);
                let scope = self.glue_scope(t);
                let eq = crate::eq::element_eq(self.cx, &mut self.b, scope, t, vals[0], vals[1])?;
                let eq = if name == "expect_equal" {
                    eq
                } else {
                    self.b.unop(Op::Not, eq)
                };
                let (actual, expected) = (vals[0], vals[1]);
                let equal = name == "expect_equal";
                self.expectation(eq, rty, &mut |s| {
                    if equal {
                        let (head, mid) = (s.lit("expected "), s.lit(", got "));
                        let (ex, ac) = (s.repr_text(expected), s.repr_text(actual));
                        s.cat(&[head, ex, mid, ac])
                    } else {
                        let head = s.lit("expected different values, got ");
                        let ac = s.repr_text(actual);
                        s.cat(&[head, ac])
                    }
                })
            }
            "expect_contains" => {
                let c = self.call_runtime("msrt_string_contains", &vals[..2], MTy::BOOL)?;
                let (actual, expected) = (vals[0], vals[1]);
                self.expectation(c, rty, &mut |s| {
                    let (head, mid) = (s.lit("expected "), s.lit(" to contain "));
                    let (a, x) = (s.repr_text(actual), s.repr_text(expected));
                    s.cat(&[head, a, mid, x])
                })
            }
            "expect_close" => self.expect_close(rty, &vals),
            "expect_none" => {
                let none = self.b.opt_is_some(vals[0]);
                let none = self.b.unop(Op::Not, none);
                let actual = vals[0];
                self.expectation(none, rty, &mut |s| {
                    let head = s.lit("expected none, got ");
                    let a = s.repr_text(actual);
                    s.cat(&[head, a])
                })
            }
            "expect_some" => {
                let some = self.b.opt_is_some(vals[0]);
                let actual = vals[0];
                self.two_ways(
                    some,
                    rty,
                    &mut |s| {
                        let p = s.b.opt_get(actual);
                        let o = s.owned(Val { v: p, own: false });
                        Ok(Some(s.testing_ok(rty, o)?))
                    },
                    &mut |s| {
                        let m = s.lit("expected some, got none");
                        let m = s.cat(&[m])?;
                        Ok(Some(s.testing_fail(rty, m.v)?))
                    },
                )
            }
            "expect_ok" | "expect_error" => {
                let want_ok = name == "expect_ok";
                let actual = vals[0];
                let (a, ok, err) = self.result_cases(self.ty_of(actual))?;
                let tag = self.b.alt_tag(actual);
                let k = self.b.iconst(if want_ok { ok } else { err } as i64);
                let good = self.b.icmp(Cc::Eq, tag, k);
                let case = if want_ok { ok } else { err };
                self.two_ways(
                    good,
                    rty,
                    &mut |s| {
                        let p = s.b.alt_get(a, case, 0, actual);
                        let o = s.owned(Val { v: p, own: false });
                        Ok(Some(s.testing_ok(rty, o)?))
                    },
                    &mut |s| {
                        let head = s.lit(if want_ok {
                            "expected ok, got "
                        } else {
                            "expected error, got "
                        });
                        let r = s.repr_text(actual);
                        let m = s.cat(&[head, r])?;
                        Ok(Some(s.testing_fail(rty, m.v)?))
                    },
                )
            }
            "expect_fault" => self.expect_fault(rty, vals[0]),
            other => Err(Error::new(format!("unsupported testing function {other}"))),
        }
    }

    /// Runs `operation` in a forked child and reports the fault message it ends with.
    fn expect_fault(&mut self, rty: MTy, operation: Value) -> Result<Val, Error> {
        let parent_side = self.call_runtime("msrt_trap_begin", &[], MTy::BOOL)?;
        let (child, parent) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(parent_side, parent, &[], child, &[]);
        self.b.seal_block(child);
        self.b.seal_block(parent);
        self.enter(child);
        self.b.call_ind(operation, &[]);
        self.call_runtime("msrt_trap_end", &[], MTy::UNIT)?;
        self.b.unreachable();
        self.enter(parent);
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(MTy::STR), Some(MTy::PTR))
            .expect("slot");
        let faulted = self.call_runtime("msrt_trap_wait", &[slot], MTy::BOOL)?;
        self.two_ways(
            faulted,
            rty,
            &mut |s| {
                let m =
                    s.b.emit(Op::Take, &[slot], Imm::Ty(MTy::STR), Some(MTy::STR))
                        .expect("take");
                Ok(Some(s.testing_ok(rty, m)?))
            },
            &mut |s| {
                let m = s.lit("expected a programming fault, operation returned normally");
                let m = s.cat(&[m])?;
                Ok(Some(s.testing_fail(rty, m.v)?))
            },
        )
    }

    fn expect_close(&mut self, rty: MTy, vals: &[Value]) -> Result<Val, Error> {
        let (actual, expected, tol) = (vals[0], vals[1], vals[2]);
        let zero = self.b.fconst(0.0);
        let valid_lo = self.b.fcmp(Cc::Ge, tol, zero);
        let spread = self.b.binop(Op::FSub, tol, tol);
        let valid_hi = self.b.fcmp(Cc::Eq, spread, zero);
        let no = self.b.bconst(false);
        let valid = self.b.select(valid_lo, valid_hi, no);
        let diff = self.b.binop(Op::FSub, actual, expected);
        let neg = self.b.fcmp(Cc::Lt, diff, zero);
        let flipped = self.b.binop(Op::FSub, zero, diff);
        let ad = self.b.select(neg, flipped, diff);
        let near = self.b.fcmp(Cc::Le, ad, tol);
        let same = self.b.fcmp(Cc::Eq, actual, expected);
        let yes = self.b.bconst(true);
        let close = self.b.select(same, yes, near);
        self.two_ways(
            valid,
            rty,
            &mut |s| {
                let r = s.expectation(close, rty, &mut |s| {
                    let parts = [
                        s.lit("expected "),
                        s.repr_text(expected),
                        s.lit(" within "),
                        s.repr_text(tol),
                        s.lit(", got "),
                        s.repr_text(actual),
                    ];
                    s.cat(&parts)
                })?;
                Ok(Some(r.v))
            },
            &mut |s| {
                let m = s.lit("expect_close: tolerance must be finite and nonnegative");
                let m = s.cat(&[m])?;
                Ok(Some(s.testing_fail(rty, m.v)?))
            },
        )
    }
}
