//! Calls to user `extern fn` declarations: the native symbol is the function's own name and the
//! call follows `ms_abi.h` (the signature table in
//! `documentation/core-language/functions/native-functions.md`):
//!
//! - sized numbers and `Bool` cross directly as their C types (the code generator narrows and
//!   extends them, see `ms_mir::ir::Module::c_externs`);
//! - `String` and `Bytes` are borrowed by pointer, a `List[T]` as an `ms_list` naming its element
//!   type, an `extern type` as its object, a function as an `ms_fn` (see `function_argument`);
//! - a result that is not a number comes back through a trailing `out`, followed by `code_out`
//!   and `message_out` when the error type has those fields. Every output is filled with an
//!   empty value before the call and dropped after it, so a shim that writes the wrong output,
//!   or none, leaves nothing undefined.

use crate::Error;
use crate::cx::HelperKey;
use crate::func::{FnLower, Val};
use ms_check::api::ast::Expr;
use ms_check::api::hir::CallView;
use ms_check::api::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FaultKind, FuncId, FuncKind, Imm, Mode, Op, Param, Value};
use ms_mir::types::{AltId, Ty as MTy, TyKind};
use ms_rt_abi::{
    CALL_MAX_PARAMS, ELEM_BOOL, ELEM_BYTES, ELEM_FLOAT32, ELEM_FLOAT64, ELEM_INT8, ELEM_INT16,
    ELEM_INT32, ELEM_INT64, ELEM_OBJECT, ELEM_STRING, ELEM_UINT8, ELEM_UINT16, ELEM_UINT32,
    ELEM_UINT64,
};

/// The trailing outputs of one call.
struct Outputs {
    /// The value's slot and type, unless the value is `Unit`.
    out: Option<(Value, MTy)>,
    /// The `int64_t *code_out` slot.
    code: Option<Value>,
    /// The `ms_str *message_out` slot.
    message: Option<Value>,
}

impl FnLower<'_> {
    /// A user `extern fn` applied to its arguments.
    pub(crate) fn extern_call(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        symbol: &str,
        _sym: &ct::SymRef,
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let result = self.emty(e)?;
        self.b.m.c_externs.insert(symbol.to_string());
        let mut vals: Vec<Value> = Vec::new();
        let mut fns: Vec<Value> = Vec::new();
        for a in &args {
            let v = self.borrow(a.val);
            self.extern_argument(v, &mut vals, &mut fns)?;
        }
        self.at(e.pos);
        if let TyKind::Alt(a) = self.b.m.types.kind(result).clone() {
            return self.extern_result(symbol, a, result, &mut vals, &fns);
        }
        if result == MTy::UNIT {
            self.call_shim(symbol, &vals, MTy::UNIT, &fns)?;
            return Ok(Val {
                v: self.b.unit(),
                own: false,
            });
        }
        if self.is_c_scalar(result) {
            let v = self.call_shim(symbol, &vals, result, &fns)?;
            return Ok(Val { v, own: false });
        }
        if matches!(self.b.m.types.kind(result), TyKind::Obj(..)) {
            // An object comes back as a pointer the shim must not leave NULL.
            let p = self.call_shim(symbol, &vals, MTy::PTR, &fns)?;
            let slot = self.empty_slot(result);
            self.b.emit(Op::Store, &[slot, p], Imm::None, None);
            let v = self.checked_object(symbol, slot, result);
            return Ok(Val { v, own: true });
        }
        let slot = self.empty_slot(result);
        self.push_output(slot, result, &mut vals);
        self.call_shim(symbol, &vals, MTy::UNIT, &fns)?;
        let v = self.move_out(slot, result);
        Ok(Val { v, own: true })
    }

    /// Calls the shim, then releases the `ms_fn` handles made for its function arguments (a
    /// shim that keeps one holds its own reference).
    fn call_shim(
        &mut self,
        symbol: &str,
        vals: &[Value],
        ret: MTy,
        fns: &[Value],
    ) -> Result<Value, Error> {
        let r = self.call_runtime(symbol, vals, ret)?;
        for f in fns {
            self.call_runtime("msrt_obj_drop", &[*f], MTy::UNIT)?;
        }
        Ok(r)
    }

    /// Whether `t` is a number or `Bool`, which crosses in a register.
    fn is_c_scalar(&self, t: MTy) -> bool {
        matches!(
            self.b.m.types.kind(t),
            TyKind::Bool
                | TyKind::Int
                | TyKind::Float
                | TyKind::Int8
                | TyKind::Int16
                | TyKind::Int32
                | TyKind::Float32
                | TyKind::UInt8
                | TyKind::UInt16
                | TyKind::UInt32
                | TyKind::UInt64
        )
    }

    /// The `ELEM_*` code of a list element type.
    fn elem_code(&self, t: MTy) -> Result<u64, Error> {
        Ok(match self.b.m.types.kind(t) {
            TyKind::Int8 => ELEM_INT8,
            TyKind::Int16 => ELEM_INT16,
            TyKind::Int32 => ELEM_INT32,
            TyKind::Int => ELEM_INT64,
            TyKind::UInt8 => ELEM_UINT8,
            TyKind::UInt16 => ELEM_UINT16,
            TyKind::UInt32 => ELEM_UINT32,
            TyKind::UInt64 => ELEM_UINT64,
            TyKind::Float32 => ELEM_FLOAT32,
            TyKind::Float => ELEM_FLOAT64,
            TyKind::Bool => ELEM_BOOL,
            TyKind::Str => ELEM_STRING,
            TyKind::Bytes => ELEM_BYTES,
            TyKind::Obj(..) => ELEM_OBJECT,
            _ => {
                return Err(Error::new(
                    "a list element that cannot cross to a native shim",
                ));
            }
        })
    }

    /// An `ms_list` on the stack around the list at `slot`: `{ VecVal *vec; uint64_t elem; }`.
    fn list_ref(&mut self, slot: Value, list: MTy) -> Result<Value, Error> {
        let TyKind::List(elem) = self.b.m.types.kind(list).clone() else {
            return Err(Error::new("an ms_list needs a list"));
        };
        let code = self.elem_code(elem)?;
        let (tval, rt) = self.b.m.add_type(
            "ms_list",
            vec![("vec".into(), MTy::INT), ("elem".into(), MTy::INT)],
        );
        let r = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(rt), Some(MTy::PTR))
            .expect("slot");
        let vec = self
            .b
            .emit(Op::PtrField, &[r], Imm::Field(tval, 0), Some(MTy::PTR))
            .expect("field");
        self.b.emit(Op::Store, &[vec, slot], Imm::None, None);
        let at = self
            .b
            .emit(Op::PtrField, &[r], Imm::Field(tval, 1), Some(MTy::PTR))
            .expect("field");
        let k = self.b.iconst(code as i64);
        self.b.emit(Op::Store, &[at, k], Imm::None, None);
        Ok(r)
    }

    /// Appends the native form of one borrowed argument; an `ms_fn` made for a function
    /// argument is also added to `fns`.
    fn extern_argument(
        &mut self,
        v: Value,
        vals: &mut Vec<Value>,
        fns: &mut Vec<Value>,
    ) -> Result<(), Error> {
        let t = self.ty_of(v);
        if matches!(self.b.m.types.kind(t), TyKind::Fn(..)) {
            let f = self.function_argument(v, t)?;
            vals.push(f);
            fns.push(f);
            return Ok(());
        }
        if self.is_c_scalar(t) || t == MTy::STR || matches!(self.b.m.types.kind(t), TyKind::Obj(..))
        {
            // Numbers in registers; a string as its value (lowered to a pointer); an object as itself.
            vals.push(v);
            return Ok(());
        }
        // Bytes and lists are borrowed by pointer to the value.
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
            .expect("slot");
        self.b.emit(Op::Store, &[slot, v], Imm::None, None);
        if matches!(self.b.m.types.kind(t), TyKind::List(_)) {
            let r = self.list_ref(slot, t)?;
            vals.push(r);
        } else {
            vals.push(slot);
        }
        Ok(())
    }

    /// A slot holding the empty value of `t`: `""`, an empty list or bytes, or zero bits
    /// (0, 0.0, false, a NULL object).
    fn empty_slot(&mut self, t: MTy) -> Value {
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
            .expect("slot");
        let empty = match self.b.m.types.kind(t) {
            TyKind::Str => {
                let text = self.lit("");
                Some(self.owned(text))
            }
            TyKind::Bytes | TyKind::List(_) => self.call_runtime("msrt_list_new", &[], t).ok(),
            _ => None,
        };
        match empty {
            Some(v) => self.move_into(slot, v),
            None => {
                let zero = self.b.iconst(0);
                self.b.emit(Op::Store, &[slot, zero], Imm::None, None);
            }
        }
        slot
    }

    /// Appends the trailing output for the value slot of type `t`.
    fn push_output(&mut self, slot: Value, t: MTy, vals: &mut Vec<Value>) {
        if matches!(self.b.m.types.kind(t), TyKind::List(_)) {
            let r = self.list_ref(slot, t).expect("list output");
            vals.push(r);
        } else {
            vals.push(slot);
        }
    }

    /// The object in `slot`, faulting when the shim left it NULL.
    fn checked_object(&mut self, symbol: &str, slot: Value, t: MTy) -> Value {
        let p = self
            .b
            .emit(Op::Load, &[slot], Imm::Ty(MTy::PTR), Some(MTy::PTR))
            .expect("load");
        let missing = self
            .b
            .emit(Op::PtrIsNull, &[p], Imm::None, Some(MTy::BOOL))
            .expect("is_null");
        let (bad, good) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(missing, bad, &[], good, &[]);
        self.b.seal_block(bad);
        self.b.switch_to(bad);
        let msg = self.b.m.add_string(&format!(
            "extern fn {symbol} returned a NULL object; return the result of ms_object_new"
        ));
        self.b.fault(FaultKind::Message(msg));
        self.b.seal_block(good);
        self.b.switch_to(good);
        self.move_out(slot, t)
    }

    /// `Result[T, E]`: a `u8` status (0 is ok, `n` the `n`th case of `E`), `T` through `out`,
    /// then `code_out` and `message_out` when a case of `E` has those fields.
    fn extern_result(
        &mut self,
        symbol: &str,
        a: AltId,
        result: MTy,
        vals: &mut Vec<Value>,
        fns: &[Value],
    ) -> Result<Val, Error> {
        let ok = self.ok_case_index(a)?;
        let err = 1 - ok;
        let payload = self.b.m.alts[a.index()].cases[ok].fields[0].1;
        let et = self.b.m.alts[a.index()].cases[err].fields[0].1;
        let TyKind::Alt(ea) = self.b.m.types.kind(et).clone() else {
            return Err(Error::new("an extern error type must be an alternative"));
        };
        let has = |name: &str, s: &Self| {
            s.b.m.alts[ea.index()]
                .cases
                .iter()
                .any(|c| c.fields.iter().any(|(f, _)| f == name))
        };
        let (with_code, with_message) = (
            has(ct::EXTERN_ERROR_CODE, self),
            has(ct::EXTERN_ERROR_MESSAGE, self),
        );
        let out = (payload != MTy::UNIT).then(|| {
            let slot = self.empty_slot(payload);
            self.push_output(slot, payload, vals);
            (slot, payload)
        });
        let code = with_code.then(|| {
            let slot = self.empty_slot(MTy::INT);
            vals.push(slot);
            slot
        });
        let message = with_message.then(|| {
            let slot = self.empty_slot(MTy::STR);
            vals.push(slot);
            slot
        });
        let outputs = Outputs { out, code, message };
        let raw = self.call_shim(symbol, vals, MTy::INT, fns)?;
        let mask = self.b.iconst(0xff);
        let status = self.b.binop(Op::And, raw, mask);
        let zero = self.b.iconst(0);
        let good = self.b.icmp(ms_mir::ir::Cc::Eq, status, zero);
        let mut r = self.two_ways(
            good,
            result,
            &mut |s| {
                s.drop_message(&outputs);
                let v = match outputs.out {
                    Some((slot, t)) if matches!(s.b.m.types.kind(t), TyKind::Obj(..)) => {
                        s.checked_object(symbol, slot, t)
                    }
                    Some((slot, t)) => s.move_out(slot, t),
                    None => s.b.unit(),
                };
                Ok(Some(s.b.alt_new(a, ok as u32, &[v])))
            },
            &mut |s| {
                s.drop_value_slot(outputs.out)?;
                let e = s.extern_error(symbol, ea, status, &outputs, 0)?;
                Ok(Some(s.b.alt_new(a, err as u32, &[e])))
            },
        )?;
        r.v = self.stamped(r.v)?;
        Ok(r)
    }

    /// Drops the value a failed call left in its `out` (the empty value, or what the shim wrote).
    fn drop_value_slot(&mut self, out: Option<(Value, MTy)>) -> Result<(), Error> {
        let Some((slot, t)) = out else {
            return Ok(());
        };
        if matches!(self.b.m.types.kind(t), TyKind::Obj(..)) {
            // Usually still NULL, which the runtime's drop ignores.
            let p = self
                .b
                .emit(Op::Load, &[slot], Imm::Ty(MTy::PTR), Some(MTy::PTR))
                .expect("load");
            self.call_runtime("msrt_obj_drop", &[p], MTy::UNIT)?;
        } else if self.needs_drop(t) {
            let v = self.move_out(slot, t);
            self.drop_value(v);
        }
        Ok(())
    }

    /// Drops the message output of a case that does not read it.
    fn drop_message(&mut self, outputs: &Outputs) {
        if let Some(slot) = outputs.message {
            let v = self.move_out(slot, MTy::STR);
            self.drop_value(v);
        }
    }

    /// The case of `ea` that `status` names, trying cases from `from` (status `from + 1`). A
    /// status that names no case faults.
    fn extern_error(
        &mut self,
        symbol: &str,
        ea: AltId,
        status: Value,
        outputs: &Outputs,
        from: usize,
    ) -> Result<Value, Error> {
        let cases = self.b.m.alts[ea.index()].cases.clone();
        let ty = self.b.m.types.alt(ea);
        let k = self.b.iconst(from as i64 + 1);
        let hit = self.b.icmp(ms_mir::ir::Cc::Eq, status, k);
        let r = self.two_ways(
            hit,
            ty,
            &mut |s| {
                let mut fields = Vec::new();
                let mut kept = false;
                for (name, _) in &cases[from].fields {
                    if name == ct::EXTERN_ERROR_CODE {
                        let slot = outputs.code.expect("a code field has a code output");
                        fields.push(s.move_out(slot, MTy::INT));
                    } else {
                        let slot = outputs.message.expect("a message field has a message output");
                        fields.push(s.move_out(slot, MTy::STR));
                        kept = true;
                    }
                }
                if !kept {
                    s.drop_message(outputs);
                }
                Ok(Some(s.b.alt_new(ea, from as u32, &fields)))
            },
            &mut |s| {
                if from + 1 < cases.len() {
                    return s.extern_error(symbol, ea, status, outputs, from + 1).map(Some);
                }
                let name = s.b.m.alts[ea.index()].name.clone();
                let msg = s.b.m.add_string(&format!(
                    "extern fn {symbol} returned a status that names no case of {name}; return 1 for its first case, 2 for the second, and so on"
                ));
                s.b.fault(FaultKind::Message(msg));
                Ok(None)
            },
        )?;
        Ok(r.v)
    }

    /// The `ms_fn` for a borrowed function argument: a runtime object holding a closure that
    /// calls `f` with arguments the runtime has converted from `ms_value`s, and the signature
    /// `ms_call` checks them against (see `ms_rt::cabi::ms_call_v1`).
    fn function_argument(&mut self, f: Value, fty: MTy) -> Result<Value, Error> {
        let TyKind::Fn(ps, ret) = self.b.m.types.kind(fty).clone() else {
            return Err(Error::new("an ms_fn needs a function"));
        };
        if ps.len() > CALL_MAX_PARAMS {
            return Err(Error::new(
                "a function an extern takes has too many parameters",
            ));
        }
        let code = |s: &Self, t: MTy| -> Result<u64, Error> {
            if t == MTy::UNIT {
                return Ok(0);
            }
            let elem = s.elem_code(t)?;
            Ok((elem & 0xff) | ((elem >> 8) & 0xf) << 4)
        };
        let mut sig = ps.len() as u64;
        for (i, p) in ps.iter().enumerate() {
            sig |= code(self, *p)? << (8 * (i + 1));
        }
        sig |= code(self, ret)? << 56;
        let thunk = self.invoke_thunk(fty, &ps, ret);
        let held = self.clone_value(f);
        let wty = self.b.m.types.func(vec![MTy::PTR], MTy::UNIT);
        let wrapper = self
            .b
            .emit(Op::ClosureNew, &[held], Imm::Func(thunk), Some(wty))
            .expect("closure");
        let sig = self.b.iconst(sig as i64);
        // The `ms_fn` owns the wrapper closure, which holds its own copy of `f`.
        self.call_runtime("msrt_fn_new", &[wrapper, sig], MTy::PTR)
    }

    /// The closure body behind an `ms_fn` of type `fty`: takes its arguments out of the
    /// runtime's 24-byte cells, calls the captured function, and puts the result in the cell
    /// after the last argument slot.
    fn invoke_thunk(&mut self, fty: MTy, ps: &[MTy], ret: MTy) -> FuncId {
        let key = HelperKey::MsFn(fty);
        if let Some(t) = self.cx.helpers.get(&key) {
            return *t;
        }
        // The runtime fills the cells with string and bytes copies the thunk owns, and with
        // objects the shim keeps: a borrowed object is loaded and never dropped.
        let drops: Vec<bool> = ps
            .iter()
            .map(|p| self.needs_drop(*p) && !matches!(self.b.m.types.kind(*p), TyKind::Obj(..)))
            .collect();
        let ret_drops = self.needs_drop(ret);
        let (_, cell) = self.b.m.add_type(
            "ms_fn_cell",
            vec![
                ("a".into(), MTy::INT),
                ("b".into(), MTy::INT),
                ("c".into(), MTy::INT),
            ],
        );
        let (frame, _) = self.b.m.add_type(
            "ms_fn_frame",
            (0..=CALL_MAX_PARAMS)
                .map(|i| (format!("c{i}"), cell))
                .collect(),
        );
        let params = vec![
            Param {
                ty: MTy::PTR,
                mode: Mode::Borrow,
            },
            Param {
                ty: MTy::PTR,
                mode: Mode::Borrow,
            },
        ];
        let mut b = FuncBuilder::new(self.b.m, "ms_fn_invoke", params, MTy::UNIT);
        b.func_mut().kind = FuncKind::Closure {
            captures: vec![fty],
        };
        let me = b.params();
        let target = b
            .emit(Op::ClosureCap, &[me[0]], Imm::Idx(0), Some(fty))
            .expect("capture");
        let mut args = Vec::new();
        for (i, p) in ps.iter().enumerate() {
            let at = b
                .emit(
                    Op::PtrField,
                    &[me[1]],
                    Imm::Field(frame, i as u32),
                    Some(MTy::PTR),
                )
                .expect("cell");
            let op = if drops[i] { Op::Take } else { Op::Load };
            args.push(b.emit(op, &[at], Imm::Ty(*p), Some(*p)).expect("argument"));
        }
        let r = b.call_ind(target, &args);
        for (a, d) in args.iter().zip(&drops) {
            if *d {
                b.emit(Op::Drop, &[*a], Imm::None, None);
            }
        }
        if ret != MTy::UNIT {
            let at = b
                .emit(
                    Op::PtrField,
                    &[me[1]],
                    Imm::Field(frame, CALL_MAX_PARAMS as u32),
                    Some(MTy::PTR),
                )
                .expect("cell");
            let op = if ret_drops { Op::Put } else { Op::Store };
            b.emit(op, &[at, r], Imm::None, None);
        }
        let unit = b.unit();
        b.ret(Some(unit));
        let f = b.into_func();
        let id = self.b.m.add_func(f);
        self.cx.helpers.insert(key, id);
        id
    }
}
