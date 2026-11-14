//! Interpreter rules for type, alternative, list, optional and string instructions.
//!
//! Each function handles one op family; `Interp::step` routes to it.

use super::*;

impl Interp<'_> {
    /// Types and alternatives.
    pub(super) fn types_and_alternatives(
        &mut self,
        f: &Func,
        regs: &mut [Val],
        inst: &Inst,
    ) -> R<Flow> {
        let mut ops = Operands { regs, inst };
        let m = self.m;
        match inst.op {
            Op::TypeNew => {
                let v = Val::Type(Rc::new(self.take_args(f, ops.regs, &inst.args)));
                ops.set(v)
            }
            Op::TypeGet => {
                let Imm::Field(_, i) = inst.imm else {
                    return Err(Raw::internal("type.get without field"));
                };
                let Val::Type(r) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("type.get on &inst.args non-type"));
                };
                ops.set(r[i as usize].clone());
            }
            Op::TypeSet | Op::TypeFill => {
                let Imm::Field(_, i) = inst.imm else {
                    return Err(Raw::internal("type.set without field"));
                };
                let v = arg(f, ops.regs, inst.args[1], true, m);
                let Val::Type(mut r) = arg(f, ops.regs, inst.args[0], true, m) else {
                    return Err(Raw::internal("type.set on &inst.args non-type"));
                };
                Rc::make_mut(&mut r)[i as usize] = v;
                ops.set(Val::Type(r));
            }
            Op::AltNew => {
                let Imm::Case(_, c) = inst.imm else {
                    return Err(Raw::internal("alt.new without case"));
                };
                {
                    let v = Val::Alt(c, Rc::new(self.take_args(f, ops.regs, &inst.args)));
                    ops.set(v)
                };
            }
            Op::AltView => {
                let Imm::Case(_, c) = inst.imm else {
                    return Err(Raw::internal("alt.view without case"));
                };
                let fields: Vec<Val> = inst
                    .args
                    .iter()
                    .map(|x| arg(f, ops.regs, *x, false, m))
                    .collect();
                ops.set(Val::Alt(c, Rc::new(fields)));
            }
            Op::AltOwn => {
                let v = ops.regs[inst.args[0].index()].clone();
                ops.set(v);
            }
            Op::AltPlain => {
                let v = ops.regs[inst.args[0].index()].clone();
                ops.set(v);
            }
            Op::AltTag => {
                let Val::Alt(t, _) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("alt.tag on &inst.args non-alternative"));
                };
                ops.set(Val::Int(*t as i64));
            }
            Op::AltGet => {
                let Imm::AltField(_, c, i) = inst.imm else {
                    return Err(Raw::internal("alt.get without field"));
                };
                let Val::Alt(t, p) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("alt.get on &inst.args non-alternative"));
                };
                if *t != c {
                    return Err(Raw::internal(format!("alt.get of case {c} on case {t}")));
                }
                ops.set(p[i as usize].clone());
            }
            Op::AltTake => {
                let Imm::AltField(_, c, i) = inst.imm else {
                    return Err(Raw::internal("alt.take without field"));
                };
                let Val::Alt(t, p) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("alt.take on &inst.args non-alternative"));
                };
                if *t != c {
                    return Err(Raw::internal(format!("alt.take of case {c} on case {t}")));
                }
                ops.set(p[i as usize].clone());
            }
            Op::TypeRelease => {
                arg(f, ops.regs, inst.args[0], true, m);
            }
            Op::AltRelease => {
                arg(f, ops.regs, inst.args[0], true, m);
            }
            Op::AltUnbox => {
                let Imm::AltField(_, c, i) = inst.imm else {
                    return Err(Raw::internal("alt.unbox without field"));
                };
                let Val::Alt(t, p) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("alt.unbox on &inst.args non-alternative"));
                };
                if *t != c {
                    return Err(Raw::internal(format!("alt.unbox of case {c} on case {t}")));
                }
                let field = p[i as usize].clone();
                arg(f, ops.regs, inst.args[0], true, m);
                ops.set(field);
            }

            _ => unreachable!("types_and_alternatives is only called for its own ops"),
        }
        Ok(Flow::Next)
    }

    /// Lists.
    pub(super) fn lists(&mut self, f: &Func, regs: &mut [Val], inst: &Inst) -> R<Flow> {
        let mut ops = Operands { regs, inst };
        let m = self.m;
        match inst.op {
            Op::ListNew => {
                let cap = ops.int(0)?.clamp(0, 1 << 16) as usize;
                ops.set(Val::List(Rc::new(Vec::with_capacity(cap))));
            }
            Op::ListLit => {
                let v = Val::List(Rc::new(self.take_args(f, ops.regs, &inst.args)));
                ops.set(v)
            }
            Op::ListConst => {
                let elem = inst.res.and_then(|r| self.m.list_elem(f.ty(r)));
                let kind = elem.map(|e| self.m.types.kind(e).clone());
                let items = self.m.list_consts[imm_int(inst.imm) as usize]
                    .iter()
                    .map(|&r| match kind {
                        Some(TyKind::Float | TyKind::Float32) => {
                            Val::Float(f64::from_bits(r as u64))
                        }
                        Some(TyKind::Bool) => Val::Bool(r != 0),
                        _ => Val::Int(r),
                    })
                    .collect();
                ops.set(Val::List(Rc::new(items)))
            }
            Op::ListLen => {
                let Val::List(l) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("list.len on &inst.args non-list"));
                };
                ops.set(Val::Int(l.len() as i64));
            }
            Op::ListGet | Op::ListGetNn | Op::ListGetU | Op::ListTake => {
                let i = ops.int(1)?;
                let Val::List(l) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("list.get on &inst.args non-list"));
                };
                let k = list_index(l.len(), i, inst.op == Op::ListGet)?;
                ops.set(l[k].clone());
            }
            Op::ListRelease => {
                // The elements before the index were taken out; the rest go with the list.
                let _ = ops.int(1)?;
                arg(f, ops.regs, inst.args[0], true, m);
            }
            Op::ListSet | Op::ListSetNn | Op::ListSetU | Op::ListFill => {
                let i = ops.int(1)?;
                let v = arg(f, ops.regs, inst.args[2], true, m);
                let Val::List(mut l) = arg(f, ops.regs, inst.args[0], true, m) else {
                    return Err(Raw::internal("list.set on &inst.args non-list"));
                };
                let k = list_index(l.len(), i, matches!(inst.op, Op::ListSet | Op::ListFill))?;
                Rc::make_mut(&mut l)[k] = v;
                ops.set(Val::List(l));
            }
            Op::ListPush => {
                let v = arg(f, ops.regs, inst.args[1], true, m);
                let Val::List(mut l) = arg(f, ops.regs, inst.args[0], true, m) else {
                    return Err(Raw::internal("list.push on &inst.args non-list"));
                };
                Rc::make_mut(&mut l).push(v);
                ops.set(Val::List(l));
            }
            Op::ListDropLast => {
                let Val::List(mut l) = arg(f, ops.regs, inst.args[0], true, m) else {
                    return Err(Raw::internal("list.droplast on &inst.args non-list"));
                };
                Rc::make_mut(&mut l).pop();
                ops.set(Val::List(l));
            }

            _ => unreachable!("lists is only called for its own ops"),
        }
        Ok(Flow::Next)
    }

    /// Optionals and strings.
    pub(super) fn optionals_and_strings(
        &mut self,
        f: &Func,
        regs: &mut [Val],
        inst: &Inst,
    ) -> R<Flow> {
        let mut ops = Operands { regs, inst };
        let m = self.m;
        match inst.op {
            Op::OptSome => {
                let v = Val::Opt(Some(Rc::new(arg(f, ops.regs, inst.args[0], true, m))));
                ops.set(v)
            }
            Op::OptView => {
                let v = Val::Opt(Some(Rc::new(arg(f, ops.regs, inst.args[0], false, m))));
                ops.set(v)
            }
            Op::OptNone => ops.set(Val::Opt(None)),
            Op::OptIsSome => {
                let Val::Opt(o) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("opt.is_some on &inst.args non-optional"));
                };
                ops.set(Val::Bool(o.is_some()));
            }
            Op::OptGet | Op::OptUnwrap => {
                let Val::Opt(o) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("opt.get on &inst.args non-optional"));
                };
                match o {
                    Some(v) => ops.set((**v).clone()),
                    None if inst.op == Op::OptUnwrap => {
                        return Err(Raw::new(FaultKind::NoneUnwrap, "unwrap of none"));
                    }
                    None => return Err(Raw::internal("opt.get on none")),
                }
            }
            Op::OptAddr => {
                return Err(Raw::internal(
                    "interior pointers are not supported by the interpreter",
                ));
            }
            Op::OptUnbox => {
                let Val::Opt(Some(v)) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("opt.unbox of none"));
                };
                let payload = (**v).clone();
                arg(f, ops.regs, inst.args[0], true, m);
                ops.set(payload);
            }
            Op::StrLen => {
                let Val::Str(s) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("str.len on &inst.args non-string"));
                };
                ops.set(Val::Int(s.chars().count() as i64));
            }
            Op::StrByte => {
                let (Val::Str(s), Val::Int(i)) = (
                    &ops.regs[inst.args[0].index()],
                    &ops.regs[inst.args[1].index()],
                ) else {
                    return Err(Raw::internal("str.byte on &inst.args non-string"));
                };
                ops.set(Val::Int(i64::from(s.as_bytes()[*i as usize])));
            }
            Op::StrAsciiAt => {
                let (Val::Str(s), Val::Int(i)) = (
                    &ops.regs[inst.args[0].index()],
                    &ops.regs[inst.args[1].index()],
                ) else {
                    return Err(Raw::internal("str.ascii_at on non-string"));
                };
                let byte = s
                    .as_bytes()
                    .get(*i as usize)
                    .filter(|_| s.is_ascii() && *i >= 0);
                ops.set(Val::Int(byte.map_or(-1, |b| i64::from(*b))));
            }
            Op::StrAsciiLen => {
                let Val::Str(s) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("str.ascii_len on non-string"));
                };
                ops.set(Val::Int(if s.is_ascii() { s.len() as i64 } else { -1 }));
            }
            Op::StrEqLit => {
                let (Val::Str(a), Imm::Str(id)) = (&ops.regs[inst.args[0].index()], inst.imm)
                else {
                    return Err(Raw::internal("str.eq_lit on non-string"));
                };
                ops.set(Val::Bool(**a == *m.strings[id.0 as usize]));
            }
            Op::StrAscii => {
                let Val::Int(b) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("str.ascii on &inst.args non-int"));
                };
                ops.set(Val::Str(((*b as u8) as char).to_string().into()));
            }

            _ => unreachable!("optionals_and_strings is only called for its own ops"),
        }
        Ok(Flow::Next)
    }
}
