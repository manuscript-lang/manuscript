//! Interfaces whose values are runtime handles: `Network`, `Connection`, `Listener` and the
//! other network resources. The value is an `Obj` handle; its vtable methods call the
//! runtime symbols `msrt_<module>_<type>_<method>` (`ms-std-net/ABI.md`).

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use crate::native::NArg;
use ms_check::hir::ModuleHir;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Func, FuncId, FuncKind, Imm, Linkage, Mode, Module, Op, Param, VtableDef};
use ms_mir::types::{IfaceId, Ty as MTy, TyKind};
use std::rc::Rc;

/// Interfaces backed by runtime handles and the symbol prefix of their methods.
const HANDLE_IFACES: &[(&str, &str)] = &[
    ("Network", "msrt_net_network"),
    ("Connection", "msrt_net_connection"),
    ("Listener", "msrt_net_listener"),
    ("DatagramSocket", "msrt_net_datagram"),
    ("HttpClient", "msrt_http_client"),
    ("HttpServer", "msrt_http_server"),
    ("HttpExchange", "msrt_http_exchange"),
    ("ResponseBody", "msrt_http_body"),
    ("WebSocket", "msrt_websocket"),
];

/// A method of a handle-backed interface waiting to be lowered.
pub struct NativeIfaceJob {
    /// The interface type, for the declared parameter names.
    pub iface: ct::Ty,
    /// The method.
    pub method: String,
    /// Prefix of the runtime symbol.
    pub prefix: &'static str,
    /// The handle type the data slot holds.
    pub data_ty: MTy,
    /// Module the use is written in.
    pub hir: Rc<ModuleHir>,
}

/// The symbol prefix of a handle-backed interface.
fn handle_prefix(t: &ct::Ty) -> Option<&'static str> {
    HANDLE_IFACES
        .iter()
        .find(|(name, _)| t.is_std(name))
        .map(|(_, prefix)| *prefix)
}

impl Cx {
    /// Whether `iface` is backed by a runtime handle.
    pub(crate) fn is_handle_iface(&self, iface: IfaceId) -> bool {
        self.contracts
            .get(&iface)
            .is_some_and(|t| handle_prefix(t).is_some())
    }

    /// The handle type behind `iface`.
    pub(crate) fn handle_ty(&self, m: &mut Module, iface: IfaceId) -> MTy {
        let name = m.ifaces[iface.index()].name.clone();
        m.types.obj(&name, Vec::new())
    }

    /// The implementation table of a handle-backed interface; method bodies are queued.
    fn net_handle_vtable(
        &mut self,
        m: &mut Module,
        hir: &Rc<ModuleHir>,
        iface: IfaceId,
    ) -> Result<ms_mir::ir::VtableId, Error> {
        let key = format!("handle-vtable:{}", iface.0);
        if let Some(v) = self.vtables.get(&key) {
            return Ok(*v);
        }
        let ct_iface = self.contracts[&iface].clone();
        let prefix =
            handle_prefix(&ct_iface).ok_or_else(|| Error::new("not a handle-backed interface"))?;
        let data_ty = self.handle_ty(m, iface);
        let sigs = m.ifaces[iface.index()].methods.clone();
        let mut methods = Vec::new();
        for s in &sigs {
            let mut ps = vec![Param {
                ty: MTy::PTR,
                mode: Mode::Borrow,
            }];
            ps.extend(s.params.iter().map(|t| Param {
                ty: *t,
                mode: Mode::Borrow,
            }));
            let mut f = Func::new(&format!("vt.{}", s.name), ps, s.ret);
            f.kind = FuncKind::Method;
            f.linkage = Linkage::Internal;
            let id = m.add_func(f);
            self.queue.push(Job {
                func: id,
                kind: JobKind::NativeIface(Rc::new(NativeIfaceJob {
                    iface: ct_iface.clone(),
                    method: s.name.clone(),
                    prefix,
                    data_ty,
                    hir: hir.clone(),
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
        let id = ms_mir::ir::VtableId(m.vtables.len() as u32 - 1);
        self.vtables.insert(key, id);
        Ok(id)
    }
}

impl FnLower<'_> {
    /// The interface value over an owned runtime `handle`.
    pub(crate) fn wrap_handle(&mut self, handle: Value, iface_ty: MTy) -> Result<Val, Error> {
        let TyKind::Iface(iface) = self.b.m.types.kind(iface_ty).clone() else {
            return Err(Error::new("a handle needs an interface type"));
        };
        let vt = self.cx.net_handle_vtable(self.b.m, &self.hir.clone(), iface)?;
        let v = self
            .b
            .emit(Op::IfaceNew, &[handle], Imm::Vtable(vt), Some(iface_ty))
            .expect("iface");
        Ok(Val { v, own: true })
    }
}

use ms_mir::ir::Value;

/// Lowers the body of a queued handle-interface method.
pub(crate) fn build_native_iface(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &NativeIfaceJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let file = m.add_file(job.hir.data.file.as_str());
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    b.func_mut().linkage = proto.linkage;
    let mut fl = FnLower::new(cx, b, job.hir.clone(), ct::Subst::new(), file, proto.ret);
    let result = lower_native_iface_method(&mut fl, job);
    let mut f = fl.b.into_func();
    if let Err(e) = result {
        // A method the program may never call must not stop the program from building:
        // calling it faults with the reason.
        let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
        b.func_mut().kind = proto.kind.clone();
        b.func_mut().linkage = proto.linkage;
        let text = format!("{}.{} is not supported yet: {}", job.iface, job.method, e);
        let msg = b.str_lit(&text);
        let ext = b.m.add_extern(ms_mir::ir::ExternDef {
            name: "msrt_fault_string".to_string(),
            params: vec![Param {
                ty: MTy::STR,
                mode: Mode::Borrow,
            }],
            ret: MTy::UNIT,
            noreturn: true,
            pure_: false,
        });
        b.call_rt(ext, &[msg]);
        b.unreachable();
        f = b.into_func();
    }
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

fn lower_native_iface_method(fl: &mut FnLower<'_>, job: &NativeIfaceJob) -> Result<(), Error> {
    let params = fl.b.params();
    let data =
        fl.b.emit(
            Op::Load,
            &[params[0]],
            Imm::Ty(job.data_ty),
            Some(job.data_ty),
        )
        .expect("load");
    let subst = ct::substitution(&job.iface);
    let def = job
        .iface
        .def
        .as_ref()
        .ok_or_else(|| Error::new("interface without definition"))?;
    let ops = def.operations.borrow().clone();
    let op = ops
        .iter()
        .find(|o| o.name.as_str() == job.method)
        .ok_or_else(|| Error::new(format!("no method {}", job.method)))?;
    let sig = ct::sub(&op.ty, &subst);
    let mut args: Vec<NArg> = sig
        .params
        .iter()
        .zip(params.iter().skip(1))
        .map(|(p, v)| NArg {
            name: p.name,
            val: Val { v: *v, own: false },
            wrapped: false,
        })
        .collect();
    // A handler crosses as a closure the runtime can call.
    if matches!(job.method.as_str(), "serve" | "serve_stream") {
        for a in &mut args {
            if a.name.as_str() == "handler" {
                a.val = fl.http_adapter(a.val, job.method == "serve_stream")?;
            }
        }
    }
    let sym = format!("{}_{}", job.prefix, job.method);
    let ret = fl.ret_ty;
    let recv = Val {
        v: data,
        own: false,
    };
    let out = fl.rt_method(&sym, recv, &sig.params, &args, ret)?;
    fl.emit_return(Some(out));
    Ok(())
}
