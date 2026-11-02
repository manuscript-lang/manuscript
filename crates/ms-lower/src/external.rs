//! Calls to user `extern fn` declarations: the native symbol is the function's own name and the
//! call follows `ms_abi.h` (the signature table in
//! `documentation/core-language/functions/native-functions.md`):
//!
//! - sized numbers and `Bool` cross directly as their C types (the code generator narrows and
//!   extends them, see `ms_mir::ir::Module::c_externs`);
//! - `String` and `Bytes` are lent by pointer, a `List[T]` as an `ms_list` naming its element
//!   type, an `extern type` as its object;
//! - a result that is not a number comes back through a trailing `out`, followed by `code_out`
//!   and `message_out` when the error type has those fields. Every output is filled with an
//!   empty value before the call and dropped after it, so a shim that writes the wrong output,
//!   or none, leaves nothing undefined.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::hir::CallView;
use ms_check::types as ct;
use ms_mir::ir::{FaultKind, Imm, Op, Value};
use ms_mir::types::{AltId, Ty as MTy, TyKind};
use ms_rt_abi::{
    ELEM_BOOL, ELEM_BYTES, ELEM_FLOAT32, ELEM_FLOAT64, ELEM_INT8, ELEM_INT16, ELEM_INT32,
    ELEM_INT64, ELEM_OBJECT, ELEM_STRING, ELEM_UINT8, ELEM_UINT16, ELEM_UINT32, ELEM_UINT64,
};
use ms_syntax::ast::Expr;

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
        for a in &args {
            let v = self.borrow(a.val);
            self.extern_argument(v, &mut vals)?;
        }
        self.at(e.pos);
        if let TyKind::Alt(a) = self.b.m.types.kind(result).clone() {
            return self.extern_result(symbol, a, result, &mut vals);
        }
        if result == MTy::UNIT {
            self.call_runtime(symbol, &vals, MTy::UNIT)?;
            return Ok(Val {
                v: self.b.unit(),
                own: false,
            });
        }
        if self.is_c_scalar(result) {
            let v = self.call_runtime(symbol, &vals, result)?;
            return Ok(Val { v, own: false });
        }
        if matches!(self.b.m.types.kind(result), TyKind::Obj(..)) {
            // An object comes back as a pointer the shim must not leave NULL.
            let p = self.call_runtime(symbol, &vals, MTy::PTR)?;
            let slot = self.empty_slot(result);
            self.b.emit(Op::Store, &[slot, p], Imm::None, None);
            let v = self.checked_object(symbol, slot, result);
            return Ok(Val { v, own: true });
        }
        let slot = self.empty_slot(result);
        self.push_output(slot, result, &mut vals);
        self.call_runtime(symbol, &vals, MTy::UNIT)?;
        let v = self.move_out(slot, result);
        Ok(Val { v, own: true })
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
        let (rec, rt) = self.b.m.add_record(
            "ms_list",
            vec![("vec".into(), MTy::INT), ("elem".into(), MTy::INT)],
        );
        let r = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(rt), Some(MTy::PTR))
            .expect("slot");
        let vec = self
            .b
            .emit(Op::PtrField, &[r], Imm::Field(rec, 0), Some(MTy::PTR))
            .expect("field");
        self.b.emit(Op::Store, &[vec, slot], Imm::None, None);
        let at = self
            .b
            .emit(Op::PtrField, &[r], Imm::Field(rec, 1), Some(MTy::PTR))
            .expect("field");
        let k = self.b.iconst(code as i64);
        self.b.emit(Op::Store, &[at, k], Imm::None, None);
        Ok(r)
    }

    /// Appends the native form of one borrowed argument.
    fn extern_argument(&mut self, v: Value, vals: &mut Vec<Value>) -> Result<(), Error> {
        let t = self.ty_of(v);
        if self.is_c_scalar(t) || t == MTy::STR || matches!(self.b.m.types.kind(t), TyKind::Obj(..))
        {
            // Numbers in registers; a string as its value (lowered to a pointer); an object as itself.
            vals.push(v);
            return Ok(());
        }
        // Bytes and lists are lent by pointer to the value.
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
        let (with_code, with_message) = (has("code", self), has("message", self));
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
        let raw = self.call_runtime(symbol, vals, MTy::INT)?;
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
            // Usually still NULL, which the runtime's release ignores.
            let p = self
                .b
                .emit(Op::Load, &[slot], Imm::Ty(MTy::PTR), Some(MTy::PTR))
                .expect("load");
            self.call_runtime("msrt_release", &[p], MTy::UNIT)?;
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
                    if name == "code" {
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
}
