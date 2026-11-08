//! Native default arguments and small list helpers.

use super::*;

impl<'a> FnLower<'a> {
    /// Appends the declared default of every omitted parameter that has one (`none` aside),
    /// evaluated in the declaring module.
    pub(crate) fn fill_native_defaults(
        &mut self,
        module: ct::Name,
        func: Option<&ms_check::api::ast::Func>,
        params: &[ct::Param],
        args: &mut Vec<NArg>,
    ) -> Result<(), Error> {
        let Some(f) = func else {
            return Ok(());
        };
        for (i, p) in params.iter().enumerate() {
            if args.iter().any(|a| a.name == p.name) {
                continue;
            }
            let Some(d) = f.params.get(i).and_then(|q| q.default.as_ref()) else {
                continue;
            };
            if matches!(&d.kind, ExprKind::Name(n) if self.syms.str(n) == "none") {
                continue;
            }
            // Bundled declarations carry no checked facts: literal defaults are built directly,
            // anything else through the declaring module when it was checked.
            let r = match &d.kind {
                ExprKind::Bool(b) => Ok(Val {
                    v: self.b.bconst(*b),
                    own: false,
                }),
                ExprKind::Number(t) if self.syms.str(p.ty.id) == "Int" => {
                    match ms_check::api::number::canonical(self.syms.str(t)).parse::<i64>() {
                        Ok(n) => Ok(Val {
                            v: self.b.iconst(n),
                            own: false,
                        }),
                        Err(_) => continue,
                    }
                }
                ExprKind::Text(parts) if parts.iter().all(|t| matches!(t, TextPart::Lit(_))) => {
                    let text: String = parts
                        .iter()
                        .map(|t| match t {
                            TextPart::Lit(s) => s.as_ref(),
                            TextPart::Interp(_) => "",
                        })
                        .collect();
                    Ok(self.lit(&text))
                }
                ExprKind::Call { .. } | ExprKind::Member { .. }
                    if self.cx.module(module).is_err() =>
                {
                    match self.literal_default(d, &p.ty)? {
                        Some(v) => Ok(v),
                        None => continue,
                    }
                }
                _ => {
                    let Ok(hir) = self.cx.module(module) else {
                        continue;
                    };
                    let saved_hir = std::mem::replace(&mut self.hir, hir);
                    let saved_file = self.file;
                    self.file = self.b.m.add_file(self.syms.str(module));
                    // A default reports its own position, not the caller statement\'s.
                    let saved_stmt = self.stmt_pos.take();
                    let r = self.expr(d);
                    self.stmt_pos = saved_stmt;
                    self.hir = saved_hir;
                    self.file = saved_file;
                    r
                }
            };
            let mut val = r?;
            if self.dead {
                return Ok(());
            }
            if p.ty.is(Builtin::Optional) {
                let o = self.owned(val);
                val = Val {
                    v: self.b.opt_some(o),
                    own: true,
                };
            }
            args.push(NArg {
                name: p.name,
                val,
                wrapped: false,
                reader: false,
            });
        }
        Ok(())
    }

    /// The written arguments of a native call in order; `wrapped` marks values meant for an `Optional` parameter.
    pub(crate) fn native_args(&mut self, view: &CallView<'_>) -> Result<Vec<NArg>, Error> {
        self.native_args_protected(view, false)
    }

    pub(super) fn native_args_protected(
        &mut self,
        view: &CallView<'_>,
        protect_list_elements: bool,
    ) -> Result<Vec<NArg>, Error> {
        let mut out = Vec::new();
        let mut read_at = Vec::new();
        let mut held = Vec::new();
        for (n, a) in view.arguments.iter().enumerate() {
            let at = self.b.current();
            // A native takes a reading function for a `var` function parameter as written.
            let reader = matches!(&view.target, Resolution::Method(m) if !self.syms.str(m.native).is_empty())
                && self.hir.info(a.expr).function_source.is_some();
            let val = if reader {
                self.expr_unfit(a.expr)?
            } else {
                self.expr(a.expr)?
            };
            if self.dead {
                break;
            }
            let mut val = val;
            let mut wrapped = a.wrap_optional.is_some();
            if protect_list_elements && val.own {
                let ty = a.wrap_optional.clone().unwrap_or_else(|| self.ety(a.expr));
                let ty = ct::sub(&ty, &self.subst);
                if let Some(kind) = self.part_closer(&ty)? {
                    if wrapped {
                        val.v = self.b.opt_some(val.v);
                        wrapped = false;
                    }
                    let key = self.hold_resource_temp_with(val.v, kind);
                    val = Val { v: key, own: false };
                }
            }
            read_at.push((a.expr, at));
            let later_try = view.arguments[n + 1..]
                .iter()
                .any(|l| crate::mutation::has_try(l.expr));
            let owned = val.own;
            let val = if later_try { self.hold_temp(val) } else { val };
            // Only a `hold_temp` registration is released below once the later `try` succeeded.
            held.push(later_try && owned);
            out.push(NArg {
                name: a.slot.name,
                val,
                wrapped,
                reader,
            });
        }
        if !self.dead {
            for ((arg, (expr, at)), held) in out.iter_mut().zip(read_at).zip(held) {
                // A later `try` needed this owned argument registered only until it succeeded.
                // Transfer the captured value, not a copy of its temporary borrow or a fresh
                // read of the source place (which may already have been moved).
                if held {
                    self.unhold_temp(arg.val.v);
                    arg.val.own = true;
                }
                if self.resource_temp_slot(arg.val.v).is_none() {
                    arg.val = self.refresh(expr, arg.val, at)?;
                }
            }
        }
        // Written order decides evaluation; callers index by declared parameter position, so
        // `set(value: 8, 0)` must hand them the index before the value.
        let declared: Vec<ct::Name> = match &view.target {
            Resolution::Method(m) => m.ty.params.iter().map(|p| p.name).collect(),
            Resolution::Function(sym) => sym
                .ty
                .borrow()
                .as_ref()
                .map(|t| t.params.iter().map(|p| p.name).collect())
                .unwrap_or_default(),
            _ => Vec::new(),
        };
        out.sort_by_key(|a| {
            declared
                .iter()
                .position(|n| *n == a.name)
                .unwrap_or(usize::MAX)
        });
        Ok(out)
    }

    /// `(present, value)` operands of an optional `Int` argument for runtime calls.
    pub(crate) fn optional_int(&mut self, arg: Option<NArg>) -> Result<(Value, Value), Error> {
        match arg {
            None => Ok((self.b.bconst(false), self.b.iconst(0))),
            Some(a) if a.wrapped => Ok((self.b.bconst(true), self.borrow(a.val))),
            Some(a) => {
                let v = self.borrow(a.val);
                let has = self.b.opt_is_some(v);
                let value = self.b.opt_get(v);
                Ok((has, value))
            }
        }
    }

    /// The runtime descriptor of a type.
    pub fn type_desc(&mut self, t: MTy) -> Value {
        let scope = self.glue_scope(t);
        self.cx.ensure_glue(self.b.m, t, scope);
        self.b
            .emit(
                ms_mir::ir::Op::TypeDesc,
                &[],
                ms_mir::ir::Imm::Ty(t.scoped(scope)),
                Some(MTy::PTR),
            )
            .expect("typedesc")
    }

    /// `xs.get(i, default:)`: negative indexes count from the end.
    pub(super) fn list_get_or(
        &mut self,
        recv: Val,
        elem: MTy,
        index: NArg,
        default: Option<NArg>,
    ) -> Result<Val, Error> {
        let l = self.borrow(recv);
        let idx = self.borrow(index.val);
        let Some(default) = default else {
            let x = self.b.list_get(l, idx);
            return Ok(Val { v: x, own: false });
        };
        let n = self.b.list_len(l);
        let zero = self.b.iconst(0);
        let neg = self.b.icmp(ms_mir::ir::Cc::Lt, idx, zero);
        let shifted = self.b.binop(ms_mir::ir::Op::IAdd, idx, n);
        let i = self.b.select(neg, shifted, idx);
        let lo = self.b.icmp(ms_mir::ir::Cc::Ge, i, zero);
        let hi = self.b.icmp(ms_mir::ir::Cc::Lt, i, n);
        let ok = self.b.binop(ms_mir::ir::Op::And, lo, hi);
        let owned = self.needs_drop(elem);
        let out = self
            .b
            .declare_var(elem, if owned { Mode::Move } else { Mode::Borrow });
        let (hit, miss, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br_if(ok, hit, &[], miss, &[]);
        self.b.seal_block(hit);
        self.b.seal_block(miss);
        self.b.switch_to(hit);
        let x = self.b.list_get(l, i);
        let xo = self.clone_value(x);
        // The eager default is unused on this path.
        self.finish(default.val);
        self.b.def_var(out, xo);
        self.b.br(join, &[]);
        self.b.switch_to(miss);
        if default.wrapped {
            let d = self.owned_boundary(default.val);
            self.b.def_var(out, d);
            self.b.br(join, &[]);
        } else {
            // An omitted `Optional` default faults like a plain read.
            let has = self.b.opt_is_some(default.val.v);
            let (give, fault) = (self.b.new_block(), self.b.new_block());
            self.b.br_if(has, give, &[], fault, &[]);
            self.b.seal_block(give);
            self.b.seal_block(fault);
            self.b.switch_to(give);
            let inner = self.b.opt_get(default.val.v);
            let d = self.owned_boundary(Val {
                v: inner,
                own: false,
            });
            self.finish(default.val);
            self.b.def_var(out, d);
            self.b.br(join, &[]);
            self.b.switch_to(fault);
            let x = self.b.list_get(l, idx);
            let xo = self.owned_boundary(Val { v: x, own: false });
            self.finish(default.val);
            self.b.def_var(out, xo);
            self.b.br(join, &[]);
        }
        self.b.seal_block(join);
        self.b.switch_to(join);
        let r = self.b.use_var(out);
        Ok(Val { v: r, own: owned })
    }

    /// `xs.reversed()`: a fresh list read back to front.
    pub(super) fn list_reversed(
        &mut self,
        lv: ms_mir::builder::Var,
        elem: MTy,
    ) -> Result<Val, Error> {
        let l = self.b.use_var(lv);
        let n = self.b.list_len(l);
        let out = self.b.list_new(elem, n);
        let acc = self.b.declare_var(self.ty_of(out), Mode::Move);
        self.b.def_var(acc, out);
        let idx = self.b.declare_var(MTy::INT, Mode::Borrow);
        self.b.def_var(idx, n);
        let (header, body, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(header, &[]);
        self.b.switch_to(header);
        let i = self.b.use_var(idx);
        let zero = self.b.iconst(0);
        let c = self.b.icmp(ms_mir::ir::Cc::Gt, i, zero);
        self.b.br_if(c, body, &[], exit, &[]);
        self.b.seal_block(body);
        self.b.switch_to(body);
        let i = self.b.use_var(idx);
        let one = self.b.iconst(1);
        let j = self.b.binop(ms_mir::ir::Op::ISub, i, one);
        self.b.def_var(idx, j);
        let l = self.b.use_var(lv);
        let x = self.b.list_get(l, j);
        let xo = self.clone_value(x);
        let cur = self.b.use_var(acc);
        let next = self.b.list_push(cur, xo);
        self.b.def_var(acc, next);
        self.b.br(header, &[]);
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        let r = self.b.use_var(acc);
        Ok(Val { v: r, own: true })
    }
}
