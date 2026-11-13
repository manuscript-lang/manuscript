//! Standard-library interfaces implemented by runtime handles: `stdin()`, `files()`, ...
//!
//! The interface value's data is an owned runtime handle (or nothing). Each interface
//! operation becomes a generated forwarder that calls the runtime symbol named by [`METHODS`]
//! through the same marshalling as any native method, so statuses become `Result` values.

use crate::Error;
use crate::cx::VtableKey;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use crate::native::NArg;
use crate::text::runtime_fn;
use ms_check::api::hir::ModuleHir;
use ms_check::api::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncId, FuncKind, Imm, Linkage, Mode, Module, Op, Param, VtableId};
use ms_mir::types::{IfaceId, Ty as MTy, TyKind};
use std::rc::Rc;

/// Interfaces whose values carry no data.
const UNIT_DATA: &[(&str, &str)] = &[("io", "Files"), ("fs", "FileSystem")];

/// Interfaces whose handles belong to one runtime module whichever symbol returns them: streams are
/// `@std/io` handles, and a WebSocket is the same handle from a client dial and a server upgrade.
const HANDLE_MODULE: &[(&str, &str)] = &[
    ("ReadStream", "io"),
    ("WriteStream", "io"),
    ("WebSocket", "websocket"),
];

/// How an operation's runtime call is built, beyond calling its symbol with the operation's
/// own arguments.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Shape {
    /// One call of the runtime symbol.
    Plain,
    /// A type result read through the getters of `<symbol>_status` and `<symbol>_<field>`;
    /// the row names the group without the status suffix.
    Type,
    /// A list of types read through the getters of the group named by the row's symbol.
    Types,
    /// A directory walk with a predicate closure: `glob_entries` (a path and an exclude
    /// predicate) or, with `copy`, a copy (a source, a destination and the copy options).
    Walk { copy: bool },
    /// A Manuscript function of the same module named by the row's symbol: it takes the handle
    /// viewed as the interface its first parameter names, then the operation's own arguments,
    /// and returns the operation's result (`HttpExchange.upgrade` builds its `WebSocket`).
    Ms,
}

/// One row of `METHODS`: module, interface, operation, runtime symbol, call shape.
type MethodRow = (
    &'static str,
    &'static str,
    &'static str,
    &'static str,
    Shape,
);

const METHODS: &[MethodRow] = &[
    (
        "http",
        "HttpExchange",
        "close",
        "msstd_http_exchange_close",
        Shape::Plain,
    ),
    (
        "http",
        "HttpExchange",
        "headers",
        "msstd_http_exchange_headers",
        Shape::Plain,
    ),
    (
        "http",
        "HttpExchange",
        "method",
        "msstd_http_exchange_method",
        Shape::Plain,
    ),
    (
        "http",
        "HttpExchange",
        "path",
        "msstd_http_exchange_path",
        Shape::Plain,
    ),
    (
        "http",
        "HttpExchange",
        "protocol",
        "msstd_http_exchange_protocol",
        Shape::Plain,
    ),
    (
        "http",
        "HttpExchange",
        "query",
        "msstd_http_exchange_query",
        Shape::Plain,
    ),
    (
        "http",
        "HttpExchange",
        "read",
        "msstd_http_exchange_read",
        Shape::Plain,
    ),
    (
        "http",
        "HttpExchange",
        "send",
        "msstd_http_exchange_send",
        Shape::Plain,
    ),
    (
        "http",
        "HttpExchange",
        "send_headers",
        "msstd_http_exchange_send_headers",
        Shape::Plain,
    ),
    (
        "http",
        "HttpExchange",
        "write",
        "msstd_http_exchange_write",
        Shape::Plain,
    ),
    (
        "http",
        "HttpExchange",
        "write_bytes",
        "msstd_http_exchange_write_bytes",
        Shape::Plain,
    ),
    (
        "http",
        "HttpExchange",
        "upgrade",
        "exchange_upgrade",
        Shape::Ms,
    ),
    (
        "http",
        "RawExchange",
        "upgrade",
        "msstd_http_exchange_upgrade",
        Shape::Plain,
    ),
    (
        "fs",
        "FileSystem",
        "glob",
        "msstd_fs_glob_entries",
        Shape::Walk { copy: false },
    ),
    (
        "fs",
        "FileSystem",
        "copy",
        "msstd_fs_copy",
        Shape::Walk { copy: true },
    ),
];

/// The MIR type of a runtime handle object.
pub(crate) fn handle_ty(m: &mut Module) -> MTy {
    m.types.obj("Handle", Vec::new())
}

/// A generated forwarder of one interface operation.
pub(crate) struct MethodJob {
    hir: Rc<ModuleHir>,
    name: String,
    /// The runtime symbol, or none when the operation is not implemented yet.
    sym: Option<String>,
    /// How the call is built beyond calling `sym`.
    shape: Shape,
    decl: Vec<ct::Param>,
    /// Constant `Bool` arguments after the operation's own.
    params: Vec<MTy>,
    ret: MTy,
    data_ty: MTy,
    /// The runtime module the interface's handles belong to.
    module: String,
}

impl Cx {
    /// The table for `iface` as returned by the runtime symbol `sym` (named `msstd_<module>_...`).
    pub(crate) fn handle_vtable_of(
        &mut self,
        m: &mut Module,
        hir: &Rc<ModuleHir>,
        sym: &str,
        iface: IfaceId,
    ) -> Result<VtableId, Error> {
        let mut module = sym
            .strip_prefix("msstd_")
            .or_else(|| sym.strip_prefix("msrt_"))
            .and_then(|r| r.split('_').next())
            .ok_or_else(|| Error::new(format!("{sym} returns an interface")))?;
        let ity = self
            .contracts
            .get(&iface)
            .cloned()
            .ok_or_else(|| Error::new("unknown interface"))?;
        if let Some((_, owner)) = HANDLE_MODULE
            .iter()
            .find(|(name, _)| *name == self.syms.str(ity.name))
        {
            module = owner;
        }
        self.handle_vtable(m, hir, module, &ity, iface)
    }

    /// The table of `iface` over runtime handles of `module`, one forwarder per operation.
    pub(crate) fn handle_vtable(
        &mut self,
        m: &mut Module,
        hir: &Rc<ModuleHir>,
        module: &str,
        ity: &ct::Ty,
        iface: IfaceId,
    ) -> Result<VtableId, Error> {
        let key = VtableKey::Handle {
            module: self.syms.intern(module),
            iface: iface.0,
        };
        if let Some(v) = self.vtables.get(&key) {
            return Ok(*v);
        }
        let iface_name = self.syms.str(ity.name).to_string();
        let data_ty = if UNIT_DATA.contains(&(module, iface_name.as_str())) {
            MTy::UNIT
        } else {
            handle_ty(m)
        };
        let sigs = m.ifaces[iface.index()].methods.clone();
        let subst = ct::substitution(ity);
        let ops = ity
            .def
            .as_ref()
            .map(|d| d.operations.borrow().clone())
            .unwrap_or_default();
        let mut methods = Vec::new();
        for s in &sigs {
            let decl = ops
                .iter()
                .find(|op| self.syms.str(op.name) == s.name)
                .map(|op| ct::sub(&op.ty, &subst).params.clone())
                .unwrap_or_default();
            let row = METHODS
                .iter()
                .find(|(md, i, op, ..)| *md == module && *i == iface_name && *op == s.name);
            let (sym, shape) = (
                row.map(|r| r.3.to_string()),
                row.map_or(Shape::Plain, |r| r.4),
            );
            let mut ps = vec![Param {
                ty: MTy::PTR,
                mode: Mode::Borrow,
            }];
            ps.extend(s.params.iter().map(|t| Param {
                ty: *t,
                mode: Mode::Borrow,
            }));
            let mut f = ms_mir::ir::Func::new(&format!("{iface_name}.{}", s.name), ps, s.ret);
            f.kind = FuncKind::Method;
            f.linkage = Linkage::Internal;
            let id = m.add_func(f);
            self.queue.push(Job {
                func: id,
                kind: JobKind::HandleMethod(Rc::new(MethodJob {
                    hir: hir.clone(),
                    name: format!("{iface_name}.{}", s.name),
                    sym,
                    shape,
                    decl,
                    params: s.params.clone(),
                    ret: s.ret,
                    data_ty,
                    module: module.to_string(),
                })),
            });
            methods.push(id);
        }
        Ok(self.intern_vtable(m, key, iface, methods, data_ty))
    }
}

/// Builds the body of a forwarder reserved by [`Cx::handle_vtable`].
pub(crate) fn build_method(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &MethodJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    let file = 0;
    let mut fl = FnLower::new(cx, b, job.hir.clone(), Default::default(), file, job.ret);
    fl.b.func_mut().kind = FuncKind::Method;
    fl.b.func_mut().linkage = Linkage::Internal;
    let args = fl.b.params();
    let result = forward(&mut fl, job, &args);
    let mut out = fl.b.into_func();
    result?;
    out.compact_blocks();
    m.funcs[func.index()] = out;
    Ok(())
}

fn forward(fl: &mut FnLower<'_>, job: &MethodJob, args: &[ms_mir::ir::Value]) -> Result<(), Error> {
    let Some(sym) = &job.sym else {
        let msg =
            fl.b.str_lit(&format!("{} is not available in this build yet", job.name));
        let ext = runtime_fn(fl.b.m, "msrt_fault_string", &[MTy::STR], MTy::UNIT);
        fl.b.call_rt(ext, &[msg]);
        fl.b.unreachable();
        return Ok(());
    };
    if job.shape == Shape::Ms {
        return forward_ms(fl, job, sym, args);
    }
    // The getters of a type result take the handle too when the status call does.
    if job.shape == Shape::Type {
        let lead: Vec<_> = takes_handle(&format!("{sym}_status"))
            .then(|| load_handle(fl, job, args))
            .into_iter()
            .collect();
        let r = fl.type_getters(sym, job.ret, &lead)?;
        fl.emit_return(Some(r));
        return Ok(());
    }
    if job.shape == Shape::Types {
        let r = fl.type_list_getters(sym, job.ret)?;
        fl.emit_return(Some(r));
        return Ok(());
    }
    let recv = takes_handle(sym).then(|| Val {
        v: load_handle(fl, job, args),
        own: false,
    });
    let nargs: Vec<NArg> = job
        .decl
        .iter()
        .zip(&args[1..])
        .map(|(p, v)| NArg {
            name: p.name,
            val: Val { v: *v, own: false },
            wrapped: false,
            reader: false,
        })
        .collect();
    debug_assert_eq!(job.params.len(), nargs.len());
    let decl = job.decl.clone();
    if let Shape::Walk { copy } = job.shape {
        let r = fl.fs_walk(sym, copy, &decl, &nargs, job.ret)?;
        fl.emit_return(Some(r));
        return Ok(());
    }
    let r = match recv {
        Some(recv) => fl.rt_method(sym, recv, &decl, &nargs, job.ret)?,
        None => fl.rt_function(sym, &decl, &nargs, job.ret)?,
    };
    let r = fit_result(fl, r, job.ret)?;
    fl.emit_return(Some(r));
    Ok(())
}

/// `Shape::Ms`: calls the Manuscript function `name` of the interface's module with the handle
/// viewed as the interface of its first parameter, then the operation's own arguments.
fn forward_ms(
    fl: &mut FnLower<'_>,
    job: &MethodJob,
    name: &str,
    args: &[ms_mir::ir::Value],
) -> Result<(), Error> {
    let file = fl.syms.intern(&format!("@std/net/{}.ms", job.module));
    let callable = fl
        .cx
        .callables
        .iter()
        .find(|((f, _), c)| *f == file && fl.syms.str(c.name) == name)
        .map(|(_, c)| c.clone())
        .ok_or_else(|| Error::new(format!("{name} is not declared in the standard library")))?;
    let fid = fl.instance(&callable, &Default::default())?;
    let raw = callable
        .parameters
        .first()
        .ok_or_else(|| Error::new(format!("{name} takes no exchange")))?
        .ty
        .clone();
    let raw_ty = fl.cx.lower_ty(fl.b.m, &raw)?;
    let TyKind::Iface(iface) = fl.b.m.types.kind(raw_ty).clone() else {
        return Err(Error::new(format!(
            "{name}: first parameter is not an interface"
        )));
    };
    let hir = fl.hir.clone();
    let vt = fl
        .cx
        .handle_vtable(fl.b.m, &hir, &job.module, &raw, iface)?;
    let handle = load_handle(fl, job, args);
    let view = fl.b.iface_borrow(vt, handle, raw_ty);
    let slot =
        fl.b.emit(Op::Slot, &[], Imm::Ty(raw_ty), Some(MTy::PTR))
            .expect("slot");
    fl.move_into(slot, view);
    let mut call_args = vec![slot];
    call_args.extend_from_slice(&args[1..]);
    let r = fl.b.call(fid, &call_args);
    let back = fl.move_out(slot, raw_ty);
    fl.drop_value(back);
    fl.emit_return(Some(Val { v: r, own: true }));
    Ok(())
}

/// Adapts a runtime call that cannot fail, or whose status is of no interest, to the declared
/// return: a plain value becomes `ok(value)`, and any result of a `Unit` operation is dropped.
fn fit_result(fl: &mut FnLower<'_>, r: Val, ret: MTy) -> Result<Val, Error> {
    let got = fl.ty_of(r.v);
    if got == ret {
        return Ok(r);
    }
    if ret == MTy::UNIT {
        if r.own {
            fl.drop_value(r.v);
        }
        let v = fl.b.unit();
        return Ok(Val { v, own: false });
    }
    let TyKind::Alt(a) = fl.b.m.types.kind(ret).clone() else {
        return Ok(r);
    };
    let ok = fl.b.m.alts[a.index()]
        .ok_case()
        .ok_or_else(|| Error::new("result without an ok case"))?;
    let payload = fl.owned(r);
    let v = fl.b.alt_new(a, ok as u32, &[payload]);
    Ok(Val { v, own: true })
}

/// Whether the runtime function `sym` takes the receiver's handle first.
fn takes_handle(sym: &str) -> bool {
    crate::rtcall::rt_sig(sym)
        .and_then(|s| s.params.first().map(crate::rtcall::RtParam::is_handle))
        .unwrap_or(false)
}

/// The runtime handle inside the receiver interface value `args[0]`.
fn load_handle(
    fl: &mut FnLower<'_>,
    job: &MethodJob,
    args: &[ms_mir::ir::Value],
) -> ms_mir::ir::Value {
    fl.b.emit(
        Op::Load,
        &[args[0]],
        Imm::Ty(job.data_ty),
        Some(job.data_ty),
    )
    .expect("load")
}

impl FnLower<'_> {
    /// `stdin()`: an interface value over a runtime handle made by `make(constant)`.
    pub(crate) fn handle_interface(
        &mut self,
        ity: &ct::Ty,
        want: MTy,
        module: &str,
        make: &str,
        constant: i64,
    ) -> Result<Val, Error> {
        let TyKind::Iface(iface) = self.b.m.types.kind(want).clone() else {
            return Err(Error::new("a handle function must return an interface"));
        };
        let hir = self.hir.clone();
        let vt = self.cx.handle_vtable(self.b.m, &hir, module, ity, iface)?;
        let h = if make.is_empty() {
            self.b.unit()
        } else {
            let ht = handle_ty(self.b.m);
            // A constructor that takes no argument ignores the constant.
            let takes_constant = crate::rtcall::rt_sig(make).is_some_and(|s| !s.params.is_empty());
            let k = takes_constant.then(|| self.b.iconst(constant));
            self.call_runtime(make, k.as_slice(), ht)?
        };
        let v = self
            .b
            .emit(Op::IfaceNew, &[h], Imm::Vtable(vt), Some(want))
            .expect("iface");
        Ok(Val { v, own: true })
    }
}

impl FnLower<'_> {}

impl FnLower<'_> {
    /// A type (or `Result` of one) built from one runtime getter per field, `<base>_<name>`.
    /// An optional `<base>_status` call runs first: a nonzero status is the error case. `lead`
    /// are the leading arguments of every call (the handle of a handle method).
    pub(crate) fn type_getters(
        &mut self,
        base: &str,
        result: MTy,
        lead: &[ms_mir::ir::Value],
    ) -> Result<Val, Error> {
        let (alt, type_ty) = match self.b.m.types.kind(result).clone() {
            TyKind::Alt(a) => {
                let ok = self.ok_case_index(a)?;
                (
                    Some((a, ok)),
                    self.b.m.alts[a.index()].cases[ok].fields[0].1,
                )
            }
            _ => (None, result),
        };
        let TyKind::Type(rid) = self.b.m.types.kind(type_ty).clone() else {
            return Err(Error::new(format!("{base}: not a type result")));
        };
        let build = |s: &mut Self| -> Result<ms_mir::ir::Value, Error> {
            let tval = s.type_from_getters(base, rid, lead)?;
            Ok(match alt {
                Some((a, ok)) => s.b.alt_new(a, ok as u32, &[tval]),
                None => tval,
            })
        };
        let status = format!("{base}_status");
        if alt.is_none() || crate::rtcall::rt_sig(&status).is_none() {
            let v = build(self)?;
            return Ok(Val { v, own: true });
        }
        let code = self.status_code(&status, lead)?;
        let zero = self.b.iconst(0);
        let good = self.b.icmp(ms_mir::ir::Cc::Eq, code, zero);
        self.two_ways(good, result, &mut |s| build(s).map(Some), &mut |s| {
            s.status_failure(result, code, &status).map(Some)
        })
    }

    /// A `Result` of a list of types read from a runtime snapshot: `<base>_status` takes it,
    /// `<base>_count` sizes it and each field comes from `<base>_<name>(index)`.
    pub(crate) fn type_list_getters(&mut self, base: &str, result: MTy) -> Result<Val, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new(format!("{base}: not a Result")));
        };
        let ok = self.ok_case_index(a)?;
        let list_ty = self.b.m.alts[a.index()].cases[ok].fields[0].1;
        let TyKind::List(type_ty) = self.b.m.types.kind(list_ty).clone() else {
            return Err(Error::new(format!("{base}: not a list result")));
        };
        let TyKind::Type(rid) = self.b.m.types.kind(type_ty).clone() else {
            return Err(Error::new(format!("{base}: not a list of types")));
        };
        let status = format!("{base}_status");
        let code = self.status_code(&status, &[])?;
        let zero = self.b.iconst(0);
        let good = self.b.icmp(ms_mir::ir::Cc::Eq, code, zero);
        self.two_ways(
            good,
            result,
            &mut |s| {
                let n = s.call_runtime(&format!("{base}_count"), &[], MTy::INT)?;
                let empty = s.b.list_new(type_ty, n);
                let acc = s.b.declare_var(list_ty, Mode::Move);
                s.b.def_var(acc, empty);
                let idx = s.b.declare_var(MTy::INT, Mode::Borrow);
                let start = s.b.iconst(0);
                s.b.def_var(idx, start);
                let (header, body, exit) = (s.b.new_block(), s.b.new_block(), s.b.new_block());
                s.b.br(header, &[]);
                s.b.switch_to(header);
                let i = s.b.use_var(idx);
                let more = s.b.icmp(ms_mir::ir::Cc::Lt, i, n);
                s.b.br_if(more, body, &[], exit, &[]);
                s.b.seal_block(body);
                s.b.switch_to(body);
                let i = s.b.use_var(idx);
                let tval = s.type_from_getters(base, rid, &[i])?;
                let cur = s.b.use_var(acc);
                let next = s.b.list_push(cur, tval);
                s.b.def_var(acc, next);
                let one = s.b.iconst(1);
                let i = s.b.use_var(idx);
                let after = s.b.binop(Op::IAdd, i, one);
                s.b.def_var(idx, after);
                s.b.br(header, &[]);
                s.b.seal_block(header);
                s.b.seal_block(exit);
                s.b.switch_to(exit);
                let list = s.b.use_var(acc);
                Ok(Some(s.b.alt_new(a, ok as u32, &[list])))
            },
            &mut |s| s.status_failure(result, code, &status).map(Some),
        )
    }

    /// The type `rid` with each field read by the getter `<base>_<field>`, called with `lead`
    /// (the item index of a list, or the handle).
    fn type_from_getters(
        &mut self,
        base: &str,
        rid: ms_mir::types::TypeId,
        lead: &[ms_mir::ir::Value],
    ) -> Result<ms_mir::ir::Value, Error> {
        let fields = self.b.m.type_defs[rid.index()].fields.clone();
        let mut values = Vec::new();
        for (name, ty) in &fields {
            let sym = format!("{base}_{name}");
            let v = self.getter_field(&sym, *ty, lead)?;
            values.push(self.owned(v));
        }
        Ok(self.b.type_new(rid, &values))
    }

    /// One type field: scalars and strings come straight from the getter, a payload-free enum
    /// from its case index, and a `List[Float]` (the three load averages) from `sym(window)`.
    fn getter_field(
        &mut self,
        sym: &str,
        ty: MTy,
        lead: &[ms_mir::ir::Value],
    ) -> Result<Val, Error> {
        match self.b.m.types.kind(ty).clone() {
            TyKind::Alt(a) => {
                let code = self.getter_call(sym, MTy::INT, lead)?;
                let v = self.enum_from_index(a, code, 0)?;
                Ok(Val { v, own: true })
            }
            TyKind::List(e) if e == MTy::FLOAT => {
                let three = self.b.iconst(3);
                let mut list = self.b.list_new(e, three);
                for window in 0..3 {
                    let w = self.b.iconst(window);
                    let x = self.call_runtime(sym, &[w], MTy::FLOAT)?;
                    list = self.b.list_push(list, x);
                }
                Ok(Val { v: list, own: true })
            }
            TyKind::Type(rid)
                if crate::nativetype::native_type(self.b.m, ty)
                    == Some(ms_mir::types::NativeType::Duration) =>
            {
                let nanos = self.getter_call(sym, MTy::INT, lead)?;
                Ok(Val {
                    v: self.b.type_new(rid, &[nanos]),
                    own: true,
                })
            }
            _ => {
                let v = self.getter_call(sym, ty, lead)?;
                Ok(Val { v, own: true })
            }
        }
    }

    /// Calls the getter `sym` with `lead`. A `Bool` crosses as a `u8` of which only the low byte
    /// is defined.
    fn getter_call(
        &mut self,
        sym: &str,
        ty: MTy,
        lead: &[ms_mir::ir::Value],
    ) -> Result<ms_mir::ir::Value, Error> {
        if lead.is_empty() {
            return Ok(self.rt_function(sym, &[], &[], ty)?.v);
        }
        if ty != MTy::BOOL {
            return self.call_runtime(sym, lead, ty);
        }
        let raw = self.call_runtime(sym, lead, MTy::INT)?;
        let mask = self.b.iconst(0xff);
        let low = self.b.binop(Op::And, raw, mask);
        let zero = self.b.iconst(0);
        Ok(self.b.icmp(ms_mir::ir::Cc::Ne, low, zero))
    }
}

#[cfg(test)]
mod tests {
    use super::{METHODS, UNIT_DATA};
    use std::collections::BTreeSet;

    /// The `(interface, method)` pairs each standard module declares, read from its source.
    fn declared(source: &str) -> Vec<(String, String)> {
        let mut found = Vec::new();
        let mut current: Option<String> = None;
        for line in source.lines() {
            if let Some(rest) = line.strip_prefix("export interface ") {
                current = rest.split([':', '[']).next().map(|n| n.trim().to_string());
            } else if !line.starts_with(' ') && !line.is_empty() && !line.starts_with("//") {
                current = None;
            } else if let (Some(iface), Some(rest)) = (&current, line.strip_prefix("    def ")) {
                let name: String = rest
                    .chars()
                    .take_while(|c| c.is_alphanumeric() || *c == '_')
                    .collect();
                found.push((iface.clone(), name));
            }
        }
        found
    }

    /// An interface the runtime implements has a binding for every operation it declares, so an
    /// operation added to `stdlib/*.ms` cannot compile into a forwarder that only faults.
    #[test]
    fn every_native_interface_method_is_bound() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../stdlib");
        let native: BTreeSet<(&str, &str)> = METHODS
            .iter()
            .map(|(module, iface, ..)| (*module, *iface))
            .chain(UNIT_DATA.iter().copied())
            .collect();
        let bound: BTreeSet<(&str, &str, &str)> = METHODS
            .iter()
            .map(|(module, iface, op, ..)| (*module, *iface, *op))
            .collect();
        // Module names are not file names (`system` is declared in `process.ms`), so every
        // standard source is read and an interface is found by its name.
        let mut declarations = Vec::new();
        for entry in std::fs::read_dir(&dir).expect("read stdlib") {
            let path = entry.expect("stdlib entry").path();
            if path.extension().is_some_and(|e| e == "ms") {
                let source = std::fs::read_to_string(&path).expect("read stdlib source");
                declarations.extend(declared(&source));
            }
        }
        let mut missing = Vec::new();
        for (module, iface) in &native {
            for (name, op) in &declarations {
                if name == iface && !bound.contains(&(*module, *iface, op.as_str())) {
                    missing.push(format!("{module}.{iface}.{op}"));
                }
            }
        }
        missing.sort();
        missing.dedup();
        assert!(
            missing.is_empty(),
            "native interface methods without a METHODS row: {missing:?}"
        );
    }
}
