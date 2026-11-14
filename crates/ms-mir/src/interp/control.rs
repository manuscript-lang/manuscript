//! Interpreter rules for closures, interface views, ownership, raw memory, calls and runtime services.
//!
//! Each function handles one op family; `Interp::step` routes to it.

use super::*;

impl Interp<'_> {
    /// Closures and interface views.
    pub(super) fn closures_and_interfaces(
        &mut self,
        f: &Func,
        regs: &mut [Val],
        inst: &Inst,
    ) -> R<Flow> {
        let mut ops = Operands { regs, inst };
        let m = self.m;
        match inst.op {
            Op::ClosureNew => {
                let Imm::Func(g) = inst.imm else {
                    return Err(Raw::internal("closure.new without function"));
                };
                {
                    let v = Val::Closure(g, Rc::new(self.take_args(f, ops.regs, &inst.args)));
                    ops.set(v)
                };
            }
            Op::ClosureCap => {
                let Imm::Idx(i) = inst.imm else {
                    return Err(Raw::internal("closure.cap without index"));
                };
                let Val::Closure(_, c) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("closure.cap on &inst.args non-closure"));
                };
                ops.set(c[i as usize].clone());
            }
            Op::ClosureCapAddr => {
                return Err(Raw::internal("closure.cap_addr is native only"));
            }
            Op::IfaceNew => {
                let Imm::Vtable(v) = inst.imm else {
                    return Err(Raw::internal("iface.new without vtable"));
                };
                {
                    let v = Val::Iface(v, Rc::new(arg(f, ops.regs, inst.args[0], true, m)));
                    ops.set(v)
                };
            }
            Op::IfaceBorrow => {
                let Imm::Vtable(v) = inst.imm else {
                    return Err(Raw::internal("iface.borrow without vtable"));
                };
                {
                    let v = Val::Iface(v, Rc::new(arg(f, ops.regs, inst.args[0], false, m)));
                    ops.set(v)
                };
            }
            Op::IfaceView => ops.set(ops.regs[inst.args[0].index()].clone()),
            Op::IfaceIs => {
                let (Imm::Vtable(want), Val::Iface(have, _)) =
                    (inst.imm, &ops.regs[inst.args[0].index()])
                else {
                    return Err(Raw::internal("iface.is on &inst.args non-interface"));
                };
                ops.set(Val::Bool(*have == want));
            }
            Op::IfaceData => {
                let Val::Iface(_, d) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("iface.data on &inst.args non-interface"));
                };
                ops.set((**d).clone());
            }

            _ => unreachable!("closures_and_interfaces is only called for its own ops"),
        }
        Ok(Flow::Next)
    }

    /// Ownership and raw memory.
    pub(super) fn ownership_and_memory(
        &mut self,
        f: &Func,
        regs: &mut [Val],
        inst: &Inst,
    ) -> R<Flow> {
        let mut ops = Operands { regs, inst };
        let m = self.m;
        match inst.op {
            Op::Clone | Op::MoveOut => ops.set(ops.regs[inst.args[0].index()].clone()),
            Op::Drop => {
                self.drops += 1;
                arg(f, ops.regs, inst.args[0], true, m);
            }
            Op::DropIf => {
                if ops.boolean(0)? {
                    self.drops += 1;
                    arg(f, ops.regs, inst.args[1], true, m);
                }
            }
            Op::Slot => {
                let Imm::Ty(t) = inst.imm else {
                    return Err(Raw::internal("slot without type"));
                };
                self.mem.push(self.default_val(t));
                ops.set(Val::Ptr(self.mem.len() as u64));
            }
            Op::PtrIsNull => {
                let Val::Ptr(p) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("ptr.is_null of &inst.args non-pointer"));
                };
                ops.set(Val::Bool(*p == 0));
            }
            Op::ListAddr
            | Op::ListAddrU
            | Op::PtrField
            | Op::PtrAdd
            | Op::PtrNull
            | Op::PtrLoadU => {
                return Err(Raw::internal(
                    "interior pointers are not supported by the interpreter",
                ));
            }
            Op::Load | Op::Take => {
                let Val::Ptr(p) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("load through &inst.args non-pointer"));
                };
                let cell = self
                    .mem
                    .get((*p as usize).wrapping_sub(1))
                    .ok_or_else(|| Raw::internal("load from an invalid address"))?;
                ops.set(cell.clone());
            }
            Op::Store | Op::Put => {
                let Val::Ptr(p) = &ops.regs[inst.args[0].index()] else {
                    return Err(Raw::internal("store through &inst.args non-pointer"));
                };
                let k = (*p as usize).wrapping_sub(1);
                let v = ops.regs[inst.args[1].index()].clone();
                *self
                    .mem
                    .get_mut(k)
                    .ok_or_else(|| Raw::internal("store to an invalid address"))? = v;
            }

            _ => unreachable!("ownership_and_memory is only called for its own ops"),
        }
        Ok(Flow::Next)
    }

    /// Calls and runtime services.
    pub(super) fn calls_and_runtime(&mut self, f: &Func, regs: &mut [Val], inst: &Inst) -> R<Flow> {
        let mut ops = Operands { regs, inst };
        let m = self.m;
        match inst.op {
            Op::Call => {
                let Imm::Func(g) = inst.imm else {
                    return Err(Raw::internal("call without callee"));
                };
                let params = &m.funcs[g.index()].params;
                let args = inst
                    .args
                    .iter()
                    .zip(params)
                    .map(|(v, p)| arg(f, ops.regs, *v, p.mode != Mode::Borrow, m))
                    .collect();
                return Ok(Flow::Call { callee: g, args });
            }
            Op::CallInd => {
                let Val::Closure(g, _) = ops.regs[inst.args[0].index()].clone() else {
                    return Err(Raw::internal("call.ind on &inst.args non-closure"));
                };
                let mut args = vec![ops.regs[inst.args[0].index()].clone()];
                args.extend(
                    inst.args[1..]
                        .iter()
                        .map(|v| arg(f, ops.regs, *v, false, m)),
                );
                return Ok(Flow::Call { callee: g, args });
            }
            Op::CallMethod => {
                let Imm::Method(_, k) = inst.imm else {
                    return Err(Raw::internal("call.method without method"));
                };
                let Val::Iface(vt, data) = ops.regs[inst.args[0].index()].clone() else {
                    return Err(Raw::internal("call.method on &inst.args non-interface"));
                };
                let g = m.vtables[vt.index()].methods[k as usize];
                let mut args = vec![(*data).clone()];
                args.extend(
                    inst.args[1..]
                        .iter()
                        .map(|v| arg(f, ops.regs, *v, false, m)),
                );
                return Ok(Flow::Call { callee: g, args });
            }
            Op::CallRt => {
                let Imm::Ext(e) = inst.imm else {
                    return Err(Raw::internal("call.rt without extern"));
                };
                let ext = &m.externs[e.index()];
                let args: Vec<Val> = inst
                    .args
                    .iter()
                    .zip(&ext.params)
                    .map(|(v, p)| arg(f, ops.regs, *v, p.mode != Mode::Borrow, m))
                    .collect();
                let host = self.hosts.get(&ext.name).cloned().ok_or_else(|| {
                    Raw::internal(format!("unregistered runtime function {}", ext.name))
                })?;
                let r = host(&mut self.stdout, &args)
                    .map_err(|msg| Raw::new(FaultKind::Unreachable, msg))?;
                ops.set(r);
            }
            Op::FuncAddr => {
                let Imm::Func(g) = inst.imm else {
                    return Err(Raw::internal("func.addr without function"));
                };
                ops.set(Val::Ptr(g.0 as u64));
            }
            Op::TypeDesc => {
                let Imm::Ty(t) = inst.imm else {
                    return Err(Raw::internal("typedesc without type"));
                };
                ops.set(Val::Ptr(t.0 as u64));
            }
            Op::Poll => {
                if self.cancel.load(Ordering::Relaxed) {
                    return Err(Raw::new(FaultKind::Cancelled, "cancelled"));
                }
            }
            Op::DepthEnter => {
                self.depth += 1;
                if self.depth > MAX_CALL_DEPTH {
                    return Err(Raw::new(FaultKind::CallDepth, depth_msg()));
                }
            }
            Op::DepthLeave => self.depth -= 1,
            Op::CleanupPush => {
                let Imm::Func(g) = inst.imm else {
                    return Err(Raw::internal("cleanup.push without closer"));
                };
                self.cleanup
                    .push((g, ops.regs[inst.args[0].index()].clone()));
                ops.set(Val::Int(self.cleanup.len() as i64));
            }
            Op::CleanupRun => {
                let Val::Int(h) = ops.regs[inst.args[0].index()].clone() else {
                    return Err(Raw::internal("cleanup.run needs &inst.args handle"));
                };
                while self.cleanup.len() as i64 >= h && h > 0 {
                    let Some((closer, v)) = self.cleanup.pop() else {
                        break;
                    };
                    self.exec(closer, vec![v])
                        .map_err(|e| Raw::new(e.kind, e.message))?;
                }
            }
            Op::GlobalGet => {
                let Imm::Global(g) = inst.imm else {
                    return Err(Raw::internal("global.get without global"));
                };
                ops.set(self.globals[g.index()].clone());
            }
            Op::GlobalSet => {
                let Imm::Global(g) = inst.imm else {
                    return Err(Raw::internal("global.set without global"));
                };
                self.globals[g.index()] = arg(f, ops.regs, inst.args[0], true, m);
            }
            _ => unreachable!("calls_and_runtime is only called for its own ops"),
        }
        Ok(Flow::Next)
    }
}
