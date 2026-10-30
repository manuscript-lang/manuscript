//! `FileSystem.glob_entries` and `FileSystem.copy`: options records flattened for the runtime and
//! caller predicates wrapped in closures the runtime calls with plain arguments.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::native::NArg;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncKind, Imm, Mode, Op, Param, Value};
use ms_mir::types::{RecId, Ty as MTy, TyKind};

/// `CopyOptions` booleans and the bit of the runtime's `flags` word each sets.
const COPY_FLAGS: [(&str, i64); 6] = [
    ("recursive", 1),
    ("replace", 2),
    ("error_on_exists", 4),
    ("dereference", 8),
    ("preserve_timestamps", 16),
    ("verbatim_symlinks", 32),
];

impl FnLower<'_> {
    /// Calls `msstd_fs_glob_entries` or `msstd_fs_copy` for the forwarder's arguments.
    pub(crate) fn fs_walk(
        &mut self,
        sym: &str,
        decl: &[ct::Param],
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let sig = crate::rtcall::rt_sig(sym)
            .ok_or_else(|| Error::new(format!("no runtime symbol {sym}")))?;
        let arg = |name: &str| -> Result<Val, Error> {
            decl.iter()
                .zip(args)
                .find(|(p, _)| p.name.as_str() == name)
                .map(|(_, a)| a.val)
                .ok_or_else(|| Error::new(format!("{sym}: missing argument {name}")))
        };
        let copy = sym == "msstd_fs_copy";
        let options = arg("options")?;
        let options = self.borrow(options);
        let TyKind::Rec(rid) = self.b.m.types.kind(self.ty_of(options)).clone() else {
            return Err(Error::new(format!("{sym}: options is not a record")));
        };
        let mut vals = Vec::new();
        let field = |s: &mut Self, name: &str| -> Result<Value, Error> {
            let at = s.b.m.records[rid.index()]
                .fields
                .iter()
                .position(|(n, _)| n == name)
                .ok_or_else(|| Error::new(format!("{sym}: options has no {name}")))?;
            Ok(s.b.rec_get(rid, at as u32, options))
        };
        let (first, second, filter_name) = if copy {
            ("source", "destination", "filter")
        } else {
            ("path", "", "exclude")
        };
        for name in [first, second].into_iter().filter(|n| !n.is_empty()) {
            let v = arg(name)?;
            vals.push(self.borrow(v));
        }
        if copy {
            let mut flags = self.b.iconst(0);
            for (name, bit) in COPY_FLAGS {
                let b = field(self, name)?;
                let n = self
                    .b
                    .emit(Op::B2I, &[b], Imm::None, Some(MTy::INT))
                    .expect("b2i");
                let k = self.b.iconst(bit.trailing_zeros() as i64);
                let shifted = self.b.binop(Op::Shl, n, k);
                flags = self.b.binop(Op::Or, flags, shifted);
            }
            vals.push(flags);
            vals.push(field(self, "clone")?);
            for name in ["max_entries", "max_bytes"] {
                let v = field(self, name)?;
                let (has, n) = self.present(v);
                vals.push(has);
                vals.push(n);
            }
        } else {
            vals.push(field(self, "patterns")?);
            vals.push(field(self, "exclude")?);
            vals.push(field(self, "follow_links")?);
            for name in ["max_entries", "max_results"] {
                let v = field(self, name)?;
                let (has, n) = self.present(v);
                vals.push(has);
                vals.push(n);
            }
        }
        let user = arg(filter_name)?;
        let user = self.borrow(user);
        let wrapped = self.predicate_closure(user, copy)?;
        vals.push(wrapped);
        let has_out = sig.params.last().is_some_and(|p| p.name == "out");
        let r = self.finish_rt_call(sym, &sig, has_out, vals, result)?;
        self.b.emit(Op::Drop, &[wrapped], Imm::None, None);
        Ok(r)
    }

    /// `(present, value)` of a borrowed `Int?`.
    fn present(&mut self, v: Value) -> (Value, Value) {
        (self.b.opt_is_some(v), self.b.opt_get(v))
    }

    /// An owned `Optional` closure the runtime can call as `code(closure, args...)`: the
    /// runtime-argument form of the borrowed optional predicate `user`, or none.
    fn predicate_closure(&mut self, user: Value, copy: bool) -> Result<Value, Error> {
        let user_ty = self.ty_of(user);
        let TyKind::Opt(fn_ty) = self.b.m.types.kind(user_ty).clone() else {
            return Err(Error::new("a predicate is not optional"));
        };
        let params: Vec<MTy> = if copy {
            vec![MTy::STR, MTy::STR]
        } else {
            vec![MTy::STR, MTy::STR, MTy::BOOL, MTy::BOOL]
        };
        let fty = self.b.m.types.func(params.clone(), MTy::BOOL);
        let opt_ty = self.b.m.types.opt(fty);
        let thunk = self.predicate_thunk(fn_ty, &params, copy)?;
        let present = self.b.opt_is_some(user);
        let made = self.two_ways(
            present,
            opt_ty,
            &mut |s| {
                let f = s.b.opt_get(user);
                let held = s.owned(Val { v: f, own: false });
                let c =
                    s.b.emit(Op::ClosureNew, &[held], Imm::Func(thunk), Some(fty))
                        .expect("closure");
                Ok(Some(s.b.opt_some(c)))
            },
            &mut |s| Ok(Some(s.none_owned(opt_ty))),
        )?;
        Ok(made.v)
    }

    /// The function the runtime reaches through the closure: it rebuilds the caller's argument
    /// (a `(source, destination)` pair, or a `PathEntry`) and calls the captured predicate.
    fn predicate_thunk(
        &mut self,
        user_ty: MTy,
        runtime_params: &[MTy],
        copy: bool,
    ) -> Result<ms_mir::ir::FuncId, Error> {
        let key = format!("walk-thunk:{}:{copy}", user_ty.0);
        if let Some(t) = self.cx.helpers.get(&key) {
            return Ok(*t);
        }
        let mut ps = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        ps.extend(runtime_params.iter().map(|t| Param {
            ty: *t,
            mode: Mode::Borrow,
        }));
        // The caller's parameter types, read before the builder borrows the module.
        let TyKind::Fn(user_params, _) = self.b.m.types.kind(user_ty).clone() else {
            return Err(Error::new("a predicate is not a function"));
        };
        let entry = (!copy)
            .then(|| self.path_entry_records(user_params[0]))
            .transpose()?;
        let mut b = FuncBuilder::new(self.b.m, "walk.predicate", ps, MTy::BOOL);
        b.func_mut().kind = FuncKind::Closure {
            captures: vec![user_ty],
        };
        let p = b.params();
        let f = b
            .emit(Op::ClosureCap, &[p[0]], Imm::Idx(0), Some(user_ty))
            .expect("capture");
        let text = |b: &mut FuncBuilder<'_>, v: Value| {
            b.emit(Op::Copy, &[v], Imm::None, Some(MTy::STR))
                .expect("copy")
        };
        let r = match entry {
            None => b.call_ind(f, &[p[1], p[2]]),
            Some((pe, de)) => {
                let (path, name) = (text(&mut b, p[1]), text(&mut b, p[2]));
                let dir = b.rec_new(de, &[name, p[3], p[4]]);
                let record = b.rec_new(pe, &[path, dir]);
                let r = b.call_ind(f, &[record]);
                b.emit(Op::Drop, &[record], Imm::None, None);
                r
            }
        };
        b.ret(Some(r));
        let func = b.into_func();
        let id = self.b.m.add_func(func);
        self.cx.helpers.insert(key, id);
        Ok(id)
    }

    /// The `PathEntry` record type and the `DirectoryEntry` nested in it.
    fn path_entry_records(&self, ty: MTy) -> Result<(RecId, RecId), Error> {
        let TyKind::Rec(pe) = self.b.m.types.kind(ty).clone() else {
            return Err(Error::new("a glob predicate takes no PathEntry"));
        };
        let inner = self.b.m.records[pe.index()]
            .fields
            .iter()
            .find(|(n, _)| n == "entry")
            .map(|(_, t)| *t)
            .ok_or_else(|| Error::new("PathEntry has no entry"))?;
        match self.b.m.types.kind(inner) {
            TyKind::Rec(de) => Ok((pe, *de)),
            _ => Err(Error::new("PathEntry.entry is not a record")),
        }
    }
}
