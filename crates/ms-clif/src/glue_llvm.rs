//! Direct emission of glue functions as LLVM IR (`proposals/mir-to-llvm-direct.md`, stage 4).
//!
//! Glue (drop, clone, slot and block helpers) has no MIR: the Cranelift lowering builds it from
//! the type. This module writes the same bodies straight through the typed builder for the types
//! it covers (strings, lists, plain records, optionals); every other glue keeps the old path.

use crate::cg::{Gen, Glue};
use crate::layout::{Leaf, mem_layout};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Types, Val};
use crate::mir_llvm::Emitted;
use ms_mir::types::{Ty, TyKind};
use ms_rt_abi::STR_INLINE;

type Vs = Vec<Val>;

fn reg(l: Leaf) -> LTy {
    match l {
        Leaf::I64 | Leaf::N8 | Leaf::N16 | Leaf::N32 | Leaf::U8 | Leaf::U16 | Leaf::U32 => LTy::I64,
        Leaf::F64 => LTy::F64,
        Leaf::F32 => LTy::F32,
        Leaf::I8 => LTy::I8,
    }
}

fn mem(l: Leaf) -> LTy {
    match l {
        Leaf::N8 | Leaf::U8 | Leaf::I8 => LTy::I8,
        Leaf::N16 | Leaf::U16 => LTy::I16,
        Leaf::N32 | Leaf::U32 => LTy::I32,
        Leaf::I64 => LTy::I64,
        Leaf::F64 => LTy::F64,
        Leaf::F32 => LTy::F32,
    }
}

fn attr(l: Leaf) -> &'static str {
    if l == Leaf::I8 { " zeroext" } else { "" }
}

/// Whether the body of the glue `kind` for `ty` can be written here.
pub fn supports(g: &Gen, kind: Glue, ty: Ty) -> bool {
    let m = g.m;
    match kind {
        Glue::SlotDrop | Glue::SlotCopy | Glue::BlockDrop | Glue::BlockClone => true,
        Glue::CleanupThunk(_) => true,
        Glue::Drop => match m.types.kind(ty) {
            TyKind::Bytes | TyKind::List(_) => true,
            TyKind::Rec(r) => !m.records[r.index()].indirect,
            TyKind::Opt(inner) => {
                g.lay.opt_is_boxed(*inner)
                    || g.lay.is_str_like(ty)
                    || !g.lay.opt_is_nullable(*inner)
            }
            TyKind::Obj(..) | TyKind::Alt(_) | TyKind::Iface(_) => false,
            _ => true,
        },
        Glue::Clone => match m.types.kind(ty) {
            TyKind::Bytes | TyKind::List(_) => true,
            TyKind::Rec(r) => !m.records[r.index()].indirect,
            TyKind::Opt(_) => true,
            TyKind::Obj(..) | TyKind::Alt(_) | TyKind::Iface(_) => false,
            _ => true,
        },
        _ => false,
    }
}

struct E<'a, 'm, 't> {
    g: &'a mut Gen<'m>,
    b: FnBuilder<'t>,
    cur: String,
    n: u32,
    decls: Vec<(String, String)>,
}

impl E<'_, '_, '_> {
    fn label(&mut self, name: &str) {
        self.b.label(name);
        self.cur = name.to_string();
    }

    fn fresh(&mut self, what: &str) -> String {
        self.n += 1;
        format!("{what}{}", self.n)
    }

    fn br(&mut self, to: &str) {
        self.b.br(to);
    }

    fn test(&mut self, v: &Val) -> Val {
        self.b.icmp("ne", v, &Val::new("0", v.ty.clone()))
    }

    fn if_then(&mut self, cond: &Val, body: impl FnOnce(&mut Self)) {
        let (then, cont) = (self.fresh("t"), self.fresh("c"));
        self.b.cond_br(cond, &then, &cont);
        self.label(&then);
        body(self);
        self.br(&cont);
        self.label(&cont);
    }

    fn declare(&mut self, name: &str, ret: &str, params: &str) {
        self.decls.push((
            name.to_string(),
            format!("declare {ret} @\"{name}\"({params})"),
        ));
    }

    /// Calls the runtime function `name` (all arguments `i64`); the result is an `i64`.
    fn rt(&mut self, name: &str, args: &[&Val], ret: bool) -> Option<Val> {
        let params = vec!["i64"; args.len()].join(", ");
        self.declare(name, if ret { "i64" } else { "void" }, &params);
        let a: Vec<(Val, &str)> = args.iter().map(|v| ((*v).clone(), "")).collect();
        self.b
            .call(if ret { &LTy::I64 } else { &LTy::Void }, "", name, &a)
    }

    fn free(&mut self, p: &Val) {
        self.rt("msrt_free", &[p], false);
    }

    /// A fresh block of `size` bytes, as an address.
    fn alloc(&mut self, size: &Val) -> Val {
        self.declare("msrt_alloc", "noalias align 16 ptr", "i64");
        let p = self
            .b
            .call(
                &LTy::Ptr,
                "noalias align 16 ",
                "msrt_alloc",
                &[(size.clone(), "")],
            )
            .expect("result");
        self.b.ptrtoint(&p)
    }

    fn load_leaves(&mut self, base: &Val, off: u64, leaves: &[Leaf]) -> Vs {
        let lay = mem_layout(leaves);
        let p = self.b.inttoptr(base);
        leaves
            .iter()
            .enumerate()
            .map(|(k, l)| {
                let at = self.b.gep_bytes(&p, off + lay.offsets[k] as u64);
                let v = self.b.load(&mem(*l), &at, l.size() as u64);
                match l {
                    Leaf::N8 | Leaf::N16 | Leaf::N32 => self.b.sext(&v, LTy::I64),
                    Leaf::U8 | Leaf::U16 | Leaf::U32 => self.b.zext(&v, LTy::I64),
                    _ => v,
                }
            })
            .collect()
    }

    fn store_leaves(&mut self, base: &Val, off: u64, leaves: &[Leaf], vs: &[Val]) {
        let lay = mem_layout(leaves);
        let p = self.b.inttoptr(base);
        for (k, l) in leaves.iter().enumerate() {
            let at = self.b.gep_bytes(&p, off + lay.offsets[k] as u64);
            let v = match l {
                Leaf::N8 | Leaf::N16 | Leaf::N32 | Leaf::U8 | Leaf::U16 | Leaf::U32 => {
                    self.b.trunc(&vs[k], mem(*l))
                }
                _ => vs[k].clone(),
            };
            self.b.store(&v, &at, l.size() as u64);
        }
    }

    /// Calls the function `sym` taking `params` and returning `rets` leaves.
    fn call_leaves(&mut self, sym: &str, params: &[Leaf], rets: &[Leaf], args: &[Val]) -> Vs {
        let formals: Vec<String> = params
            .iter()
            .map(|l| format!("{}{}", self.types_text(&reg(*l)), attr(*l)))
            .collect();
        let rty: Vec<LTy> = rets.iter().map(|l| reg(*l)).collect();
        let (ret_text, ret_attr) = match rets {
            [] => ("void".to_string(), ""),
            [l] => (
                self.types_text(&reg(*l)),
                if attr(*l).is_empty() { "" } else { "zeroext " },
            ),
            _ => (self.b.agg(&rty), ""),
        };
        self.declare(sym, &format!("{ret_attr}{ret_text}"), &formals.join(", "));
        let a: Vec<(Val, &str)> = args
            .iter()
            .zip(params)
            .map(|(v, l)| (v.clone(), attr(*l)))
            .collect();
        match rets {
            [] => {
                self.b.call(&LTy::Void, "", sym, &a);
                vec![]
            }
            [_] => vec![self.b.call(&rty[0], ret_attr, sym, &a).expect("result")],
            _ => self.b.call_multi(&rty, sym, &a),
        }
    }

    fn types_text(&self, t: &LTy) -> String {
        Types::default().text(t)
    }

    fn glue_sym(&mut self, kind: Glue, ty: Ty) -> String {
        let id = self.g.glue(kind, ty);
        crate::cg::symbol_of(self.g, id)
    }

    fn is_obj_like(&self, ty: Ty) -> bool {
        match self.g.m.types.kind(ty) {
            TyKind::Fn(..) => true,
            TyKind::Obj(n, _) => !n.is_map_or_set(),
            TyKind::Opt(inner) => {
                self.g.lay.opt_is_nullable(*inner) && !self.g.lay.opt_is_boxed(*inner)
            }
            _ => false,
        }
    }

    fn drop_value(&mut self, ty: Ty, vs: &[Val]) {
        if !self.g.m.needs_drop(ty) {
            return;
        }
        if self.g.lay.is_str_like(ty) {
            // Only an owned string (tag `00`) frees anything.
            let owned = self.b.icmp("ult", &vs[1], &Val::int(STR_INLINE as i64));
            self.if_then(&owned, |s| {
                s.rt("msrt_str_free", &[&vs[0]], false);
            });
        } else if self.is_obj_like(ty) {
            self.rt("msrt_obj_drop", &[&vs[0]], false);
        } else {
            let sym = self.glue_sym(Glue::Drop, ty);
            let leaves = self.g.lay.leaves(ty);
            self.call_leaves(&sym, &leaves, &[], vs);
        }
    }

    fn clone_value(&mut self, ty: Ty, vs: &[Val]) -> Vs {
        if !self.g.m.needs_drop(ty) {
            return vs.to_vec();
        }
        if self.g.lay.is_str_like(ty) {
            // A static (`10`) or inline (`01`) string copies bitwise; an owned one or a view is
            // duplicated.
            let tag = self.b.bin(Bin::LShr, &vs[1], &Val::int(62));
            let tag = self.b.bin(Bin::Sub, &tag, &Val::int(1));
            let shared = self.b.icmp("ult", &tag, &Val::int(2));
            let (pre, dup, join) = (self.cur.clone(), self.fresh("d"), self.fresh("j"));
            self.b.cond_br(&shared, &join, &dup);
            self.label(&dup);
            let slot = self.b.alloca(&LTy::Array(Box::new(LTy::I64), 2));
            let out = self.b.ptrtoint(&slot);
            self.rt("msrt_str_copy", &[&vs[0], &vs[1], &out], false);
            let c0 = self.b.load(&LTy::I64, &slot, 8);
            let at = self.b.gep_bytes(&slot, 8);
            let c1 = self.b.load(&LTy::I64, &at, 8);
            self.br(&join);
            let dup_end = self.cur.clone();
            self.label(&join);
            return [(0, c0), (1, c1)]
                .into_iter()
                .map(|(i, c)| {
                    let p = self.b.reserve(LTy::I64);
                    self.b
                        .phi(&p, &[(vs[i].clone(), pre.clone()), (c, dup_end.clone())]);
                    p
                })
                .collect();
        }
        if self.is_obj_like(ty) {
            return vec![self.rt("msrt_obj_clone", &[&vs[0]], true).expect("result")];
        }
        let sym = self.glue_sym(Glue::Clone, ty);
        let leaves = self.g.lay.leaves(ty);
        self.call_leaves(&sym, &leaves, &leaves, vs)
    }

    /// The fields of a plain record: `(type, first leaf, width)`.
    fn fields_of(&self, ty: Ty) -> Vec<(Ty, usize, usize)> {
        let TyKind::Rec(r) = self.g.m.types.kind(ty) else {
            return Vec::new();
        };
        let mut at = 0;
        self.g.m.records[r.index()]
            .fields
            .iter()
            .map(|f| {
                let w = self.g.lay.width(f.1);
                at += w;
                (f.1, at - w, w)
            })
            .collect()
    }

    /// Runs `body(i)` for `i` in `0..len`.
    fn count(&mut self, len: &Val, body: impl FnOnce(&mut Self, &Val)) {
        let (head, bod, latch, done) = (
            self.fresh("h"),
            self.fresh("b"),
            self.fresh("l"),
            self.fresh("e"),
        );
        let pre = self.cur.clone();
        self.br(&head);
        self.label(&head);
        let i = self.b.reserve(LTy::I64);
        let next = self.b.reserve(LTy::I64);
        self.b
            .phi(&i, &[(Val::int(0), pre), (next.clone(), latch.clone())]);
        let more = self.b.icmp("slt", &i, len);
        self.b.cond_br(&more, &bod, &done);
        self.label(&bod);
        body(self, &i);
        // The back edge leaves from a block of its own, whatever blocks `body` made.
        self.br(&latch);
        self.label(&latch);
        self.b.name_next(&next);
        self.b.bin(Bin::Add, &i, &Val::int(1));
        self.br(&head);
        self.label(&done);
    }

    fn drop_list(&mut self, ty: Ty, ptr: &Val, len: &Val) {
        let m = self.g.m;
        if let Some(e) = m.list_elem(ty).filter(|e| m.needs_drop(*e)) {
            let leaves = self.g.lay.leaves(e);
            let size = mem_layout(&leaves).size as i64;
            self.count(len, |s, i| {
                let off = s.b.bin(Bin::Mul, i, &Val::int(size));
                let at = s.b.bin(Bin::Add, ptr, &off);
                let ev = s.load_leaves(&at, 0, &leaves);
                s.drop_value(e, &ev);
            });
        }
        let nn = self.test(ptr);
        self.if_then(&nn, |s| s.free(ptr));
    }

    fn glue_drop(&mut self, ty: Ty, vs: &[Val]) {
        let m = self.g.m;
        match m.types.kind(ty).clone() {
            TyKind::Bytes | TyKind::List(_) => {
                let owned = self.test(&vs[2]);
                self.if_then(&owned, |s| s.drop_list(ty, &vs[0], &vs[1]));
            }
            TyKind::Rec(_) => {
                for (fty, at, w) in self.fields_of(ty) {
                    if m.needs_drop(fty) {
                        self.drop_value(fty, &vs[at..at + w]);
                    }
                }
            }
            TyKind::Opt(inner) if self.g.lay.opt_is_boxed(inner) => {
                let leaves = self.g.lay.leaves(inner);
                let nn = self.test(&vs[0]);
                self.if_then(&nn, |s| {
                    if m.needs_drop(inner) {
                        let payload = s.load_leaves(&vs[0], 0, &leaves);
                        s.drop_value(inner, &payload);
                    }
                    s.free(&vs[0]);
                });
            }
            TyKind::Opt(_) if self.g.lay.is_str_like(ty) => self.drop_value(ty, vs),
            TyKind::Opt(inner) => {
                let present = self.test(&vs[0]);
                self.if_then(&present, |s| s.drop_value(inner, &vs[1..]));
            }
            _ => {}
        }
    }

    fn list_copy(&mut self, ty: Ty, vs: &[Val]) -> Vs {
        let m = self.g.m;
        let elem = m.list_elem(ty);
        let (ptr, len) = (&vs[0], &vs[1]);
        let leaves = elem.map(|e| self.g.lay.leaves(e));
        let (size, align) = leaves.as_ref().map_or((1, 1), |l| {
            let lay = mem_layout(l);
            (lay.size.max(1) as i64, lay.align as u64)
        });
        let (some, join) = (self.fresh("s"), self.fresh("j"));
        let pre = self.cur.clone();
        let nonempty = self.test(len);
        self.b.cond_br(&nonempty, &some, &join);
        self.label(&some);
        let bytes = self.b.bin(Bin::Mul, len, &Val::int(size));
        let np = self.alloc(&bytes);
        match elem.filter(|e| m.needs_drop(*e)) {
            None => {
                let (d, s) = (self.b.inttoptr(&np), self.b.inttoptr(ptr));
                self.b.memcpy((&d, align), (&s, align), &bytes);
            }
            Some(e) => {
                let leaves = leaves.expect("element");
                self.count(len, |s, i| {
                    let off = s.b.bin(Bin::Mul, i, &Val::int(size));
                    let src = s.b.bin(Bin::Add, ptr, &off);
                    let dst = s.b.bin(Bin::Add, &np, &off);
                    let ev = s.load_leaves(&src, 0, &leaves);
                    let cv = s.clone_value(e, &ev);
                    s.store_leaves(&dst, 0, &leaves, &cv);
                });
            }
        }
        self.br(&join);
        let end = self.cur.clone();
        self.label(&join);
        let p = self.b.reserve(LTy::I64);
        self.b.phi(&p, &[(Val::int(0), pre), (np, end)]);
        vec![p, len.clone(), len.clone()]
    }

    fn glue_copy(&mut self, ty: Ty, vs: &[Val]) -> Vs {
        let m = self.g.m;
        match m.types.kind(ty).clone() {
            TyKind::Bytes | TyKind::List(_) => self.list_copy(ty, vs),
            TyKind::Rec(_) => {
                let mut out = Vec::new();
                for (fty, at, w) in self.fields_of(ty) {
                    out.extend(self.clone_value(fty, &vs[at..at + w]));
                }
                out
            }
            TyKind::Opt(inner) if self.g.lay.opt_is_boxed(inner) => {
                let leaves = self.g.lay.leaves(inner);
                let size = mem_layout(&leaves).size as i64;
                let (yes, join) = (self.fresh("y"), self.fresh("j"));
                let pre = self.cur.clone();
                let nn = self.test(&vs[0]);
                self.b.cond_br(&nn, &yes, &join);
                self.label(&yes);
                let payload = self.load_leaves(&vs[0], 0, &leaves);
                let c = self.clone_value(inner, &payload);
                let q = self.alloc(&Val::int(size.max(1)));
                self.store_leaves(&q, 0, &leaves, &c);
                self.br(&join);
                let end = self.cur.clone();
                self.label(&join);
                let p = self.b.reserve(LTy::I64);
                self.b.phi(&p, &[(vs[0].clone(), pre), (q, end)]);
                vec![p]
            }
            TyKind::Opt(_) if self.g.lay.is_str_like(ty) => self.clone_value(ty, vs),
            TyKind::Opt(inner) if self.g.lay.opt_is_nullable(inner) => {
                vec![self.rt("msrt_obj_clone", &[&vs[0]], true).expect("result")]
            }
            TyKind::Opt(inner) => {
                let payload = vs[1..].to_vec();
                let (yes, join) = (self.fresh("y"), self.fresh("j"));
                let pre = self.cur.clone();
                let present = self.test(&vs[0]);
                self.b.cond_br(&present, &yes, &join);
                self.label(&yes);
                let c = self.clone_value(inner, &payload);
                self.br(&join);
                let end = self.cur.clone();
                self.label(&join);
                let mut out = vec![vs[0].clone()];
                for (k, p) in payload.iter().enumerate() {
                    let r = self.b.reserve(p.ty.clone());
                    self.b
                        .phi(&r, &[(p.clone(), pre.clone()), (c[k].clone(), end.clone())]);
                    out.push(r);
                }
                out
            }
            _ => vs.to_vec(),
        }
    }

    fn ret(&mut self, vs: &[Val]) {
        match vs {
            [] => self.b.ret(None),
            [v] => self.b.ret(Some(v)),
            _ => self.b.ret_multi(vs),
        }
    }
}

/// Emits the glue `kind` for `ty`, which `supports` accepted. `loc` is the function's
/// `DILocation` node.
pub fn emit(g: &mut Gen, kind: Glue, ty: Ty, loc: usize) -> Emitted {
    let types = Types::default();
    let leaves = g.lay.leaves(ty);
    let (params, rets): (Vec<Leaf>, Vec<Leaf>) = match kind {
        Glue::Drop => (leaves.clone(), vec![]),
        Glue::Clone => (leaves.clone(), leaves.clone()),
        Glue::BlockClone => (vec![Leaf::I64], vec![Leaf::I64]),
        Glue::SlotCopy => (vec![Leaf::I64; 2], vec![]),
        _ => (vec![Leaf::I64], vec![]),
    };
    let mut e = E {
        g,
        b: FnBuilder::new(&types, Some(loc)),
        cur: String::new(),
        n: 0,
        decls: Vec::new(),
    };
    e.label("entry");
    let args: Vs = params
        .iter()
        .enumerate()
        .map(|(i, l)| Val::new(format!("%a{i}"), reg(*l)))
        .collect();
    match kind {
        Glue::Drop => e.glue_drop(ty, &args),
        Glue::Clone => {
            let out = e.glue_copy(ty, &args);
            e.ret(&out);
            return finish(e, &types, &params, &rets);
        }
        Glue::BlockDrop => {
            if e.g.m.needs_drop(ty) {
                let vs = e.load_leaves(&args[0], 0, &leaves);
                e.drop_value(ty, &vs);
            }
            e.free(&args[0]);
        }
        Glue::BlockClone => {
            let vs = e.load_leaves(&args[0], 0, &leaves);
            let c = e.clone_value(ty, &vs);
            let blk = e.alloc(&Val::int(mem_layout(&leaves).size.max(1) as i64));
            e.store_leaves(&blk, 0, &leaves, &c);
            e.ret(&[blk]);
            return finish(e, &types, &params, &rets);
        }
        Glue::SlotDrop => {
            if e.g.m.needs_drop(ty) {
                let vs = e.load_leaves(&args[0], 0, &leaves);
                e.drop_value(ty, &vs);
            }
        }
        Glue::SlotCopy => {
            let vs = e.load_leaves(&args[0], 0, &leaves);
            let out = e.clone_value(ty, &vs);
            e.store_leaves(&args[1], 0, &leaves, &out);
        }
        Glue::CleanupThunk(f) => {
            let fid = e.g.funcs[f as usize];
            let callee = &e.g.m.funcs[f as usize];
            let pty = callee.params[0].ty;
            let (cp, cr) = (e.g.param_leaves(callee), e.g.lay.leaves(callee.ret));
            let pl = e.g.lay.leaves(pty);
            let vs = e.load_leaves(&args[0], 0, &pl);
            let sym = crate::cg::symbol_of(e.g, fid);
            e.call_leaves(&sym, &cp, &cr, &vs);
        }
        _ => unreachable!("supports rejects other glue"),
    }
    e.ret(&[]);
    finish(e, &types, &params, &rets)
}

fn finish(e: E, types: &Types, params: &[Leaf], rets: &[Leaf]) -> Emitted {
    let ret = match rets {
        [] => "void".to_string(),
        [l] => format!(
            "{}{}",
            if attr(*l).is_empty() { "" } else { "zeroext " },
            types.text(&reg(*l))
        ),
        _ => e.b.agg(&rets.iter().map(|l| reg(*l)).collect::<Vec<_>>()),
    };
    let params = params
        .iter()
        .enumerate()
        .map(|(i, l)| format!("{}{} %a{i}", types.text(&reg(*l)), attr(*l)))
        .collect::<Vec<_>>()
        .join(", ");
    Emitted {
        ret,
        params,
        attrs: String::new(),
        decls: e.decls,
        body: e.b.finish(),
    }
}
