//! Standard-library interfaces implemented by runtime handles: `stdin()`, `files()`, ...
//!
//! The interface value's data is a refcounted runtime handle (or nothing). Each interface
//! operation becomes a generated forwarder that calls the runtime symbol named by [`METHODS`]
//! through the same marshalling as any native method, so statuses become `Result` values.

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use crate::native::NArg;
use crate::text::runtime_fn;
use ms_check::hir::ModuleHir;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncId, FuncKind, Imm, Linkage, Mode, Module, Op, Param, VtableDef, VtableId};
use ms_mir::types::{IfaceId, Ty as MTy, TyKind};
use std::rc::Rc;

/// Native functions that return an interface over a runtime handle: the function, the
/// interface module, and the runtime call that makes the handle with its constant argument.
pub(crate) const HANDLE_FUNCTIONS: &[(&str, &str, &str, i64)] = &[
    ("io/stdin", "io", "msstd_io_standard", 0),
    // No handle: the interface value carries nothing and its operations open handles.
    ("io/files", "io", "", 0),
];

/// Interfaces whose values carry no data.
const UNIT_DATA: &[(&str, &str)] = &[("io", "Files")];

/// Runtime symbol of an operation of a handle-backed interface (`module`, `interface`, `operation`).
const METHODS: &[(&str, &str, &str, &str)] = &[
    ("io", "Files", "open", "msstd_io_open"),
    ("io", "File", "read", "msstd_io_read"),
    ("io", "File", "close", "msstd_io_close"),
    ("io", "ReadStream", "read", "msstd_io_read"),
    ("io", "ReadStream", "close", "msstd_io_close"),
    ("io", "WriteStream", "write", "msstd_io_write"),
    ("io", "WriteStream", "write_bytes", "msstd_io_write_bytes"),
    ("io", "WriteStream", "flush", "msstd_io_flush"),
    ("io", "WriteStream", "close", "msstd_io_close"),
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
    decl: Vec<ct::Param>,
    params: Vec<MTy>,
    ret: MTy,
    data_ty: MTy,
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
        let module = sym
            .strip_prefix("msstd_")
            .and_then(|r| r.split('_').next())
            .ok_or_else(|| Error::new(format!("{sym} returns an interface")))?;
        let ity = self
            .contracts
            .get(&iface)
            .cloned()
            .ok_or_else(|| Error::new("unknown interface"))?;
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
        let key = format!("handle:{}:{}", module, iface.0);
        if let Some(v) = self.vtables.get(&key) {
            return Ok(*v);
        }
        let iface_name = ity.name.to_string();
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
                .find(|op| op.name.as_str() == s.name)
                .map(|op| ct::sub(&op.ty, &subst).params.clone())
                .unwrap_or_default();
            let sym = METHODS
                .iter()
                .find(|(md, i, op, _)| *md == module && *i == iface_name && *op == s.name)
                .map(|(_, _, _, sym)| (*sym).to_string());
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
                    decl,
                    params: s.params.clone(),
                    ret: s.ret,
                    data_ty,
                })),
            });
            methods.push(id);
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
    let takes_handle = crate::rtcall::rt_sig(sym)
        .and_then(|s| s.params.first().map(|p| p.name == "h"))
        .unwrap_or(false);
    let recv = takes_handle.then(|| {
        let handle =
            fl.b.emit(
                Op::Load,
                &[args[0]],
                Imm::Ty(job.data_ty),
                Some(job.data_ty),
            )
            .expect("load");
        Val {
            v: handle,
            own: false,
        }
    });
    let nargs: Vec<NArg> = job
        .decl
        .iter()
        .zip(&args[1..])
        .map(|(p, v)| NArg {
            name: p.name,
            val: Val { v: *v, own: false },
            wrapped: false,
        })
        .collect();
    debug_assert_eq!(job.params.len(), nargs.len());
    let r = match recv {
        Some(recv) => fl.rt_method(sym, recv, &job.decl, &nargs, job.ret)?,
        None => fl.rt_function(sym, &job.decl, &nargs, job.ret)?,
    };
    fl.emit_return(Some(r));
    Ok(())
}

impl FnLower<'_> {
    /// `stdin()`: an interface value over a runtime handle made by `make(constant)`.
    pub(crate) fn handle_interface(
        &mut self,
        e: &ms_syntax::ast::Expr,
        module: &str,
        make: &str,
        constant: i64,
    ) -> Result<Val, Error> {
        let ity = self.ety(e);
        let want = self.emty(e)?;
        let TyKind::Iface(iface) = self.b.m.types.kind(want).clone() else {
            return Err(Error::new("a handle function must return an interface"));
        };
        let hir = self.hir.clone();
        let vt = self.cx.handle_vtable(self.b.m, &hir, module, &ity, iface)?;
        let h = if make.is_empty() {
            self.b.unit()
        } else {
            let ht = handle_ty(self.b.m);
            let k = self.b.iconst(constant);
            self.call_runtime(make, &[k], ht)?
        };
        let v = self
            .b
            .emit(Op::IfaceNew, &[h], Imm::Vtable(vt), Some(want))
            .expect("iface");
        Ok(Val { v, own: true })
    }
}

impl FnLower<'_> {
    /// `io.read_line(input, max_bytes)`: a runtime call over the handle behind a native
    /// `ReadStream`; other implementations are not supported yet and fault when called.
    pub(crate) fn read_line_native(
        &mut self,
        e: &ms_syntax::ast::Expr,
        view: &ms_check::hir::CallView<'_>,
        params: &[ct::Param],
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let result = self.emty(e)?;
        let stream = params
            .iter()
            .find(|p| p.name.as_str() == "input")
            .ok_or_else(|| Error::new("read_line without an input"))?;
        let input = args
            .iter()
            .find(|a| a.name.as_str() == "input")
            .ok_or_else(|| Error::new("read_line without an input"))?;
        let TyKind::Iface(iface) = self.mty_kind(&stream.ty)? else {
            return Err(Error::new("read_line input is not an interface"));
        };
        let hir = self.hir.clone();
        let vt = self
            .cx
            .handle_vtable(self.b.m, &hir, "io", &stream.ty, iface)?;
        let stream_v = self.borrow(input.val);
        let is_handle = self
            .b
            .emit(Op::IfaceIs, &[stream_v], Imm::Vtable(vt), Some(MTy::BOOL));
        let is_handle = is_handle.expect("iface.is");
        let max: Vec<NArg> = args
            .iter()
            .filter(|a| a.name.as_str() == "max_bytes")
            .copied()
            .collect();
        let decl: Vec<ct::Param> = params
            .iter()
            .filter(|p| p.name.as_str() == "max_bytes")
            .cloned()
            .collect();
        let ht = handle_ty(self.b.m);
        self.two_ways(
            is_handle,
            result,
            &mut |s| {
                let data = s
                    .b
                    .emit(Op::IfaceData, &[stream_v], Imm::None, Some(MTy::PTR))
                    .expect("iface.data");
                let h = s
                    .b
                    .emit(Op::Load, &[data], Imm::Ty(ht), Some(ht))
                    .expect("load");
                let recv = Val { v: h, own: false };
                s.rt_method("msstd_io_read_line", recv, &decl, &max, result)
                    .map(|r| Some(s.owned(r)))
            },
            &mut |s| {
                let msg = s.b.str_lit("io.read_line over a user-defined ReadStream is not available in this build yet");
                let ext = runtime_fn(s.b.m, "msrt_fault_string", &[MTy::STR], MTy::UNIT);
                s.b.call_rt(ext, &[msg]);
                s.b.unreachable();
                Ok(None)
            },
        )
    }

    fn mty_kind(&mut self, t: &ct::Ty) -> Result<TyKind, Error> {
        let m = self.mty(t)?;
        Ok(self.b.m.types.kind(m).clone())
    }
}
