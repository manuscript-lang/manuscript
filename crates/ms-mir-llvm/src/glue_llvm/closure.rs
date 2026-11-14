//! Closure glue as LLVM IR: the clone entry, the drop entries and the unwind tail of a closure
//! object, `%ms.env.<code>` = `{ header, captures.. }` (see `mir_llvm/closures.rs`). The runtime
//! and the closure header call them through a pointer, so they keep the leaf signature
//! (`fn(obj)`, `fn(obj) -> obj`) and have no native twin.

use super::{E, P, Sig, call_func, load_leaves, mem_layout, store_leaves};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Types, Val};
use crate::mir_llvm::Emitted;
use crate::state::Gen;
use crate::{CLOSURE_CAPTURES, CLOSURE_CODE, Glue};
use ms_mir::ir::FuncKind;
use ms_mir::layout::Leaf;
use ms_mir::types::Ty;
use ms_rt_abi::symbols::{ISOLATE_HDR_GUARDED, STACK_REGION};

/// Whether `kind` is one of the closure entries.
pub fn is_closure(kind: Glue) -> bool {
    matches!(
        kind,
        Glue::ClosureClone(_)
            | Glue::ClosureDrop(_)
            | Glue::ClosureDropFramed(_)
            | Glue::ClosureDropFrom(..)
    )
}

/// The capture types of closure function `f` with the offset and leaves each has in the object.
fn captures(g: &Gen, f: u32) -> (Vec<(Ty, u64, Vec<Leaf>)>, u64) {
    let FuncKind::Closure { captures } = &g.m.funcs[f as usize].kind else {
        return (Vec::new(), u64::from(CLOSURE_CAPTURES));
    };
    let mut off = u64::from(CLOSURE_CAPTURES);
    let mut out = Vec::new();
    for c in captures {
        let leaves = g.lay.leaves(*c);
        let lay = mem_layout(&leaves);
        let align = u64::from(lay.align);
        off = off.div_ceil(align) * align;
        out.push((*c, off, leaves));
        off += u64::from(lay.size);
    }
    (out, off)
}

impl E<'_, '_, '_> {
    /// The address `off` bytes into the object `obj` (a `ptr`).
    fn at(&mut self, obj: &Val, off: u64) -> Val {
        self.b.byte_ptr(obj, off)
    }

    /// Drops capture `c`, stored at `off` in `obj`.
    fn drop_capture(&mut self, obj: &Val, c: &(Ty, u64, Vec<Leaf>)) {
        if self.g.m.needs_drop(c.0) {
            let p = self.at(obj, c.1);
            let vs = load_leaves(&mut self.b, &p, &c.2, None);
            self.drop_value(c.0, &vs);
        }
    }

    /// The running task's header block (see `ms_rt_abi::symbols::ISOLATE_HDR`): the last 16 bytes
    /// of the stack's region point at it.
    fn task_hdr(&mut self) -> Val {
        let frame = self
            .b
            .call(
                &LTy::Ptr,
                "",
                "llvm.frameaddress.p0",
                &[(Val::new("0", LTy::I32), "")],
            )
            .expect("a pointer");
        let sp = self.b.ptr_to_int(&frame);
        let base = self.b.bin(Bin::And, &sp, &Val::int(!(STACK_REGION - 1)));
        let cell = self.b.bin(Bin::Add, &base, &Val::int(STACK_REGION - 16));
        let cell = self.b.int_to_ptr(&cell);
        self.b.load(&LTy::I64, &cell, 8)
    }

    /// Registers the release of the object from capture `k` on while a guarded task unwinds;
    /// returns the cleanup handle, 0 when no guard is open (its discard is a no-op).
    fn register_tail(&mut self, f: u32, k: u32, obj: &Val) -> Val {
        let tail = self.g.glue_symbol(Glue::ClosureDropFrom(f, k), Ty::UNIT);
        self.decls
            .push((tail.clone(), format!("declare void @\"{tail}\"(i64)")));
        let hdr = self.task_hdr();
        let hdr = self.b.int_to_ptr(&hdr);
        let flag = self.b.byte_ptr(&hdr, ISOLATE_HDR_GUARDED as u64);
        let guarded = self.b.load(&LTy::I8, &flag, 1);
        let guarded = self.test(&guarded);
        let (push, join) = (self.fresh("p"), self.fresh("j"));
        let pre = self.cur.clone();
        self.b.cond_br(&guarded, &push, &join);
        self.label(&push);
        let code = self
            .b
            .ptr_to_int(&Val::new(format!("@\"{tail}\""), LTy::Ptr));
        let addr = self.b.ptr_to_int(obj);
        let h = self
            .rt("msrt_cleanup_push", &[&code, &addr], true)
            .expect("handle");
        self.br(&join);
        let end = self.cur.clone();
        self.label(&join);
        let out = self.b.reserve(LTy::I64);
        self.b.phi(&out, &[(Val::int(0), pre), (h, end)]);
        out
    }

    /// Drops the captures of closure `f` and frees the object unless `framed`.
    fn closure_drop(&mut self, f: u32, obj: &Val, framed: bool) {
        let (caps, _) = captures(self.g, f);
        let closers = self.g.m.funcs[f as usize].capture_closers.clone();
        for (k, cap) in caps.iter().enumerate() {
            if let Some((_, close)) = closers.iter().find(|(i, _)| *i as usize == k) {
                // A resource the environment owns is closed in place before it is released: the
                // closer takes the capture's address. A close that faults leaves by a jump; while
                // a guarded task unwinds, the rest of the object is released from here.
                let at = self.at(obj, cap.1);
                let at = self.b.ptr_to_int(&at);
                let handle = self.register_tail(f, k as u32, obj);
                call_func(self, close.index(), &[at]);
                self.rt("msrt_cleanup_discard", &[&handle], false);
            }
            self.drop_capture(obj, cap);
        }
        if !framed {
            let addr = self.b.ptr_to_int(obj);
            self.free(&addr);
        }
    }

    /// The unwind tail: when a guarded task unwinds, drops the captures from `from` on and frees
    /// the object.
    fn closure_drop_from(&mut self, f: u32, from: u32, obj: &Val) {
        self.declare("msrt_unwind_drops", "i8", "");
        let on = self
            .b
            .call(&LTy::I8, "", "msrt_unwind_drops", &[])
            .expect("flag");
        let on = self.test(&on);
        let (caps, _) = captures(self.g, f);
        self.if_then(&on, |s| {
            for cap in caps.iter().skip(from as usize) {
                s.drop_capture(obj, cap);
            }
            let addr = s.b.ptr_to_int(obj);
            s.free(&addr);
        });
    }

    /// A new closure object with the same header and code over copies of the captures.
    fn closure_clone(&mut self, f: u32, src: &Val) -> Val {
        let (caps, size) = captures(self.g, f);
        let mut copies = Vec::new();
        for cap in &caps {
            let p = self.at(src, cap.1);
            let vs = load_leaves(&mut self.b, &p, &cap.2, None);
            copies.push(self.clone_value(cap.0, &vs));
        }
        let obj = self.alloc(&Val::int((size.div_ceil(8) * 8) as i64));
        // The drop entry is the heap one even when `src` lives in a frame.
        for at in [0, CLOSURE_CODE as u64] {
            let from = self.at(src, at);
            let word = self.b.load(&LTy::I64, &from, 8);
            let to = self.at(&obj, at);
            self.b.store(&word, &to, 8);
        }
        let drop = self.g.glue_symbol(Glue::ClosureDrop(f), Ty::UNIT);
        self.decls
            .push((drop.clone(), format!("declare void @\"{drop}\"(i64)")));
        let slot = self.at(&obj, 8);
        self.b
            .store(&Val::new(format!("@\"{drop}\""), LTy::Ptr), &slot, 8);
        for (cap, vs) in caps.iter().zip(&copies) {
            let p = self.at(&obj, cap.1);
            store_leaves(&mut self.b, &p, &cap.2, vs);
        }
        obj
    }
}

/// Emits the closure glue `kind` (`is_closure`) under the leaf signature.
pub fn emit(g: &mut Gen, kind: Glue, types: &Types, loc: usize) -> Emitted {
    let clone = matches!(kind, Glue::ClosureClone(_));
    let sig = Sig {
        params: vec![P {
            ty: LTy::I64,
            attrs: String::new(),
        }],
        ret: if clone { LTy::I64 } else { LTy::Void },
        ret_attr: "",
    };
    let mut e = E {
        g,
        b: FnBuilder::new(types, Some(loc)),
        cur: String::new(),
        n: 0,
        decls: Vec::new(),
        data: Vec::new(),
    };
    e.label("entry");
    let word = Val::new("%a0", LTy::I64);
    let obj = e.b.int_to_ptr(&word);
    match kind {
        Glue::ClosureClone(f) => {
            let new = e.closure_clone(f, &obj);
            let new = e.b.ptr_to_int(&new);
            e.b.ret(Some(&new));
        }
        Glue::ClosureDrop(f) | Glue::ClosureDropFramed(f) => {
            e.closure_drop(f, &obj, !matches!(kind, Glue::ClosureDrop(_)));
            e.b.ret(None);
        }
        Glue::ClosureDropFrom(f, from) => {
            e.closure_drop_from(f, from, &obj);
            e.b.ret(None);
        }
        _ => unreachable!("is_closure accepts only closure glue"),
    }
    let (decls, data, body) = (e.decls, e.data, e.b.finish());
    Emitted {
        ret: sig.ret_text(),
        params: sig.formals(true),
        attrs: " nounwind".into(),
        decls,
        data,
        consts: Vec::new(),
        body,
    }
}
