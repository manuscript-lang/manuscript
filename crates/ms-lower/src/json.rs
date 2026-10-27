//! `@std/json.ms` `parse` and `stringify` for any type: one decoder and one encoder per type,
//! built in MIR over the runtime's document arena (`msrt_json_*`, see `ms-std-json`).
//!
//! A decoder takes the document handle, a node id and the strict flag (unknown object members
//! fail) and returns an `Optional`: `none` is `InvalidData`. An encoder takes the builder handle
//! and a value and returns the node id, or -1 for a value without a JSON form.

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use crate::native::NArg;
use crate::rtcall::Input;
use ms_check::hir::ModuleHir;
use ms_check::types as ct;
use ms_mir::builder::{FuncBuilder, Var};
use ms_mir::ir::{Cc, FuncId, Imm, Mode, Module, Op, Param, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use std::rc::Rc;

const KIND_NULL: i64 = 0;
const KIND_BOOL: i64 = 1;
const KIND_NUMBER: i64 = 2;
const KIND_STRING: i64 = 3;
const KIND_ARRAY: i64 = 4;
const KIND_OBJECT: i64 = 5;

/// A queued decoder or encoder.
pub struct JsonJob {
    /// The type read or written.
    pub ty: ct::Ty,
    /// Whether this is the encoder.
    pub encode: bool,
    /// Module of the use.
    pub hir: Rc<ModuleHir>,
}

/// `name` as a JSON string literal, so a fixed member name is escaped once at compile time.
fn json_quote(name: &str) -> String {
    let mut out = String::with_capacity(name.len() + 2);
    out.push('"');
    for c in name.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c < ' ' => out.push_str(&format!("\\u{:04x}", u32::from(c))),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn borrowed(ty: MTy) -> Param {
    Param {
        ty,
        mode: Mode::Borrow,
    }
}

impl Cx {
    /// The decoder (`encode` false) or encoder of `t`, reserved on first use.
    pub(crate) fn json_fn(
        &mut self,
        m: &mut Module,
        hir: &Rc<ModuleHir>,
        t: &ct::Ty,
        encode: bool,
    ) -> Result<FuncId, Error> {
        let key = format!(
            "json-{}:{}",
            if encode { "enc" } else { "dec" },
            ct::type_key(t)
        );
        if let Some(f) = self.helpers.get(&key) {
            return Ok(*f);
        }
        let mt = self.lower_ty(m, t)?;
        let doc = m.types.obj("JsonDoc", Vec::new());
        let (name, params, ret) = if encode {
            let writer = m.types.obj("JsonWriter", Vec::new());
            (
                "json_encode",
                vec![borrowed(writer), borrowed(mt)],
                MTy::INT,
            )
        } else {
            let o = m.types.opt(mt);
            (
                "json_decode",
                vec![borrowed(doc), borrowed(MTy::INT), borrowed(MTy::BOOL)],
                o,
            )
        };
        let id = m.add_func(ms_mir::ir::Func::new(name, params, ret));
        self.helpers.insert(key, id);
        self.queue.push(Job {
            func: id,
            kind: JobKind::Json(Rc::new(JsonJob {
                ty: t.clone(),
                encode,
                hir: hir.clone(),
            })),
        });
        Ok(id)
    }
}

/// Lowers the body of a queued decoder or encoder.
pub(crate) fn build_json(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &JsonJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let file = m.add_file(job.hir.data.file.as_str());
    let b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    let mut fl = FnLower::new(cx, b, job.hir.clone(), ct::Subst::new(), file, proto.ret);
    let result = if job.encode {
        fl.lower_encoder(&job.ty)
    } else {
        fl.lower_decoder(&job.ty)
    };
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

/// One field of a record or alternative case, as the JSON rules see it.
struct JField {
    name: String,
    ty: ct::Ty,
}

impl FnLower<'_> {
    // ------------------------------------------------------------ shared pieces

    fn jdoc_ty(&mut self) -> MTy {
        self.b.m.types.obj("JsonDoc", Vec::new())
    }

    /// A runtime call whose `u8`/`u32` result is masked to its defined bits, as an `Int`.
    pub(crate) fn jcall_masked(
        &mut self,
        sym: &str,
        args: &[Value],
        mask: i64,
    ) -> Result<Value, Error> {
        let raw = self.call_runtime(sym, args, MTy::INT)?;
        let m = self.b.iconst(mask);
        Ok(self.b.binop(Op::And, raw, m))
    }

    fn jkind(&mut self, doc: Value, id: Value) -> Result<Value, Error> {
        self.jcall_masked("msrt_json_kind", &[doc, id], 0xff)
    }

    fn jitem(&mut self, doc: Value, id: Value, i: Value) -> Result<Value, Error> {
        self.jcall_masked("msrt_json_item", &[doc, id, i], 0xffff_ffff)
    }

    fn jlen(&mut self, doc: Value, id: Value) -> Result<Value, Error> {
        self.call_runtime("msrt_json_len", &[doc, id], MTy::INT)
    }

    /// An owned string.
    fn jtext(&mut self, doc: Value, id: Value) -> Result<Value, Error> {
        self.call_runtime("msrt_json_text", &[doc, id], MTy::STR)
    }

    pub(crate) fn jslot(&mut self, t: MTy) -> Value {
        self.b
            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
            .expect("slot")
    }

    /// Ends the function with `none` (the document does not fit the type).
    fn jfail(&mut self) {
        let n = self.none_owned(self.ret_ty);
        self.b.ret(Some(n));
    }

    /// Continues only when `ok`; otherwise drops `drops` and the variables' values and fails.
    fn jrequire(&mut self, ok: Value, drops: &[Value], vars: &[Var]) {
        let (cont, bad) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(ok, cont, &[], bad, &[]);
        self.b.seal_block(cont);
        self.b.seal_block(bad);
        self.b.switch_to(bad);
        for d in drops {
            self.drop_value(*d);
        }
        for v in vars {
            let x = self.b.use_var(*v);
            self.drop_value(x);
        }
        self.jfail();
        self.b.switch_to(cont);
    }

    fn jexpect_kind(&mut self, doc: Value, id: Value, kind: i64) -> Result<(), Error> {
        let k = self.jkind(doc, id)?;
        let want = self.b.iconst(kind);
        let ok = self.b.icmp(Cc::Eq, k, want);
        self.jrequire(ok, &[], &[]);
        Ok(())
    }

    /// Ends the function with `some(v)`, `v` owned.
    fn jfinish(&mut self, v: Value) {
        let s = self.b.opt_some(v);
        self.b.ret(Some(s));
    }

    /// The decoded value of `r` (an owned `Optional`), or failure; `r` is consumed.
    fn junwrap(&mut self, r: Value, drops: &[Value], vars: &[Var]) -> Value {
        let ok = self.b.opt_is_some(r);
        let mut all = drops.to_vec();
        all.push(r);
        self.jrequire(ok, &all, vars);
        let x = self.b.opt_get(r);
        let owned = self.owned(Val { v: x, own: false });
        self.drop_value(r);
        owned
    }

    fn jdecode_call(
        &mut self,
        t: &ct::Ty,
        doc: Value,
        id: Value,
        strict: Value,
    ) -> Result<Value, Error> {
        let hir = self.hir.clone();
        let f = self.cx.json_fn(self.b.m, &hir, t, false)?;
        Ok(self.b.call(f, &[doc, id, strict]))
    }

    fn jencode_call(&mut self, t: &ct::Ty, doc: Value, value: Value) -> Result<Value, Error> {
        let hir = self.hir.clone();
        let f = self.cx.json_fn(self.b.m, &hir, t, true)?;
        Ok(self.b.call(f, &[doc, value]))
    }

    /// Writes a nested value: scalars inline, anything else through its encoder.
    fn jencode_nested(&mut self, t: &ct::Ty, doc: Value, value: Value) -> Result<Value, Error> {
        if matches!(t.id.as_str(), "Int" | "Float" | "Bool" | "String") {
            let mt = self.jmty(t)?;
            return self.jencode(t, mt, doc, value);
        }
        self.jencode_call(t, doc, value)
    }

    pub(crate) fn jmty(&mut self, t: &ct::Ty) -> Result<MTy, Error> {
        self.cx.lower_ty(self.b.m, t)
    }

    pub(crate) fn jvar(&mut self, t: MTy) -> Var {
        self.fresh_var(t)
    }

    fn jnames(&mut self, names: &[String]) -> Value {
        let items: Vec<Value> = names
            .iter()
            .map(|n| {
                let s = self.b.str_lit(n);
                self.owned(Val { v: s, own: false })
            })
            .collect();
        self.b.list_lit(MTy::STR, &items)
    }

    // ----------------------------------------------------------------- decoding

    pub(crate) fn lower_decoder(&mut self, t: &ct::Ty) -> Result<(), Error> {
        let p = self.b.params();
        let (doc, id, strict) = (p[0], p[1], p[2]);
        let mt = self.jmty(t)?;
        if t.is_source_type("@std/json.ms", "JsonValue") {
            return self.jdecode_tree(t, mt, doc, id, strict);
        }
        match t.id.as_str() {
            "Int" => {
                self.jexpect_kind(doc, id, KIND_NUMBER)?;
                let text = self.jtext(doc, id)?;
                let slot = self.jslot(MTy::INT);
                let st = self.status_code("msrt_json_dec_int", &[text, slot])?;
                self.drop_value(text);
                let zero = self.b.iconst(0);
                let ok = self.b.icmp(Cc::Eq, st, zero);
                self.jrequire(ok, &[], &[]);
                let v = self.take_slot(slot, MTy::INT);
                self.jfinish(v);
                return Ok(());
            }
            "Float" => {
                self.jexpect_kind(doc, id, KIND_NUMBER)?;
                let text = self.jtext(doc, id)?;
                let slot = self.jslot(MTy::FLOAT);
                let st = self.status_code("msrt_json_dec_float", &[text, slot])?;
                self.drop_value(text);
                let zero = self.b.iconst(0);
                let ok = self.b.icmp(Cc::Eq, st, zero);
                self.jrequire(ok, &[], &[]);
                let v = self.take_slot(slot, MTy::FLOAT);
                self.jfinish(v);
                return Ok(());
            }
            "Bool" => {
                self.jexpect_kind(doc, id, KIND_BOOL)?;
                let raw = self.jcall_masked("msrt_json_bool", &[doc, id], 0xff)?;
                let zero = self.b.iconst(0);
                let v = self.b.icmp(Cc::Ne, raw, zero);
                self.jfinish(v);
                return Ok(());
            }
            "String" => {
                self.jexpect_kind(doc, id, KIND_STRING)?;
                let v = self.jtext(doc, id)?;
                self.jfinish(v);
                return Ok(());
            }
            _ => {}
        }
        if t.is_std("Optional") {
            let null = self.jkind(doc, id)?;
            let k = self.b.iconst(KIND_NULL);
            let is_null = null_cmp(self, null, k);
            let (yes, no) = (self.b.new_block(), self.b.new_block());
            self.b.br_if(is_null, yes, &[], no, &[]);
            self.b.seal_block(yes);
            self.b.seal_block(no);
            self.b.switch_to(yes);
            let n = self.none_owned(mt);
            self.jfinish(n);
            self.b.switch_to(no);
            let r = self.jdecode_call(&t.args[0], doc, id, strict)?;
            let ok = self.b.opt_is_some(r);
            self.jrequire(ok, &[r], &[]);
            // The inner decoder's `some(x)` is already the `Optional` value.
            self.jfinish(r);
            return Ok(());
        }
        // Standard value types read from their JSON text.
        let parsed = if t.is_std("Duration") {
            Some((KIND_NUMBER, "msrt_json_dec_int", false))
        } else if t.is_std("Timestamp") {
            Some((KIND_STRING, "msstd_time_parse_timestamp", false))
        } else if t.is_std("Bytes") {
            Some((KIND_STRING, "msrt_encoding_base64_decode", true))
        } else if t.is_source_type("@std/net.ms", "Url") {
            Some((KIND_STRING, "msrt_url_parse", false))
        } else if t.is_source_type("@std/net.ms", "IpAddress") {
            Some((KIND_STRING, "msrt_json_dec_ip", false))
        } else if t.is_source_type("@std/net.ms", "Cidr") {
            Some((KIND_STRING, "msrt_json_dec_cidr", false))
        } else if t.is_std("Decimal") {
            Some((KIND_NUMBER, "msstd_decimal_parse", false))
        } else if t.is_std("BigInt") {
            Some((KIND_NUMBER, "msstd_bigint_parse", false))
        } else {
            None
        };
        if let Some((kind, sym, base64)) = parsed {
            self.jexpect_kind(doc, id, kind)?;
            let text = self.jtext(doc, id)?;
            let slot = self.jslot(mt);
            let st = if base64 {
                // Standard alphabet, no output budget.
                let plain = self.b.bconst(false);
                let none = self.b.bconst(false);
                let zero = self.b.iconst(0);
                self.status_code(sym, &[text, plain, none, zero, slot])?
            } else if sym == "msstd_bigint_parse" {
                // Decimal digits, at most 10000 of them.
                let radix = self.b.iconst(10);
                let has_max = self.b.bconst(true);
                let max = self.b.iconst(10_000);
                self.status_code(sym, &[text, radix, has_max, max, slot])?
            } else {
                self.status_code(sym, &[text, slot])?
            };
            self.drop_value(text);
            let zero = self.b.iconst(0);
            let ok = self.b.icmp(Cc::Eq, st, zero);
            self.jrequire(ok, &[], &[]);
            let v = self.take_slot(slot, mt);
            self.jfinish(v);
            return Ok(());
        }
        if t.is_std("List") {
            self.jexpect_kind(doc, id, KIND_ARRAY)?;
            let l = self.jdecode_items(&t.args[0], mt, doc, id, strict)?;
            self.jfinish(l);
            return Ok(());
        }
        if t.is_std("Set") {
            self.jexpect_kind(doc, id, KIND_ARRAY)?;
            let lt = self
                .cx
                .lower_ty(self.b.m, &ct::standard("List", vec![t.args[0].clone()]))?;
            let l = self.jdecode_items(&t.args[0], lt, doc, id, strict)?;
            let mark = self.temps.len();
            let set = self.set_from_list(Val { v: l, own: true }, mt)?;
            let set = self.owned(set);
            self.flush_temps(mark);
            self.jfinish(set);
            return Ok(());
        }
        if t.is_std("Map") {
            let key = &t.args[0];
            let readable = matches!(key.id.as_str(), "String" | "Int" | "Bool")
                || key.is_std("Duration")
                || jkey_alt(key);
            if !readable {
                // Other key types are never readable.
                self.jfail();
                return Ok(());
            }
            self.jexpect_kind(doc, id, KIND_OBJECT)?;
            let m = self.jdecode_members(&t.args[0], &t.args[1], mt, doc, id, strict)?;
            self.jfinish(m);
            return Ok(());
        }
        match t.kind {
            ct::Kind::Record => {
                let fields = jfields(&ct::fields(t));
                self.jexpect_kind(doc, id, KIND_OBJECT)?;
                let vals = self.jdecode_fields(t, None, &fields, doc, id, strict)?;
                let TyKind::Rec(r) = self.b.m.types.kind(mt).clone() else {
                    return Err(Error::new("a record type lowers to a record"));
                };
                let v = self.b.rec_new(r, &vals);
                self.jfinish(v);
                Ok(())
            }
            ct::Kind::Alternative => self.jdecode_alternative(t, mt, doc, id, strict),
            // No JSON form (a function, an interface value, ...): never readable.
            _ => {
                self.jfail();
                Ok(())
            }
        }
    }

    /// An owned list of the decoded array elements of node `id`.
    fn jdecode_items(
        &mut self,
        elem: &ct::Ty,
        lt: MTy,
        doc: Value,
        id: Value,
        strict: Value,
    ) -> Result<Value, Error> {
        let et = self.jmty(elem)?;
        let n = self.jlen(doc, id)?;
        let acc = self.jvar(lt);
        let zero = self.b.iconst(0);
        let empty = self.b.list_new(et, n);
        self.b.def_var(acc, empty);
        self.counted_loop(zero, n, &mut |s, iv| {
            let item = s.jitem(doc, id, iv)?;
            let r = s.jdecode_call(elem, doc, item, strict)?;
            let x = s.junwrap(r, &[], &[acc]);
            let l = s.b.use_var(acc);
            let l2 = s.b.list_push(l, x);
            s.b.def_var(acc, l2);
            Ok(())
        })?;
        Ok(self.b.use_var(acc))
    }

    /// An owned map of the decoded members of the object node `id`.
    fn jdecode_members(
        &mut self,
        key: &ct::Ty,
        value: &ct::Ty,
        mt: MTy,
        doc: Value,
        id: Value,
        strict: Value,
    ) -> Result<Value, Error> {
        let key_mt = self.jmty(key)?;
        let n = self.jlen(doc, id)?;
        let acc = self.jvar(mt);
        let empty = self.map_new(mt)?;
        let empty = self.jreserve(empty, n)?;
        self.b.def_var(acc, empty);
        let zero = self.b.iconst(0);
        // The parser rejects repeated names, so only a key read from them can collide.
        let names_are_keys = key.id.as_str() == "String";
        self.counted_loop(zero, n, &mut |s, iv| {
            let name = s.call_runtime("msrt_json_key", &[doc, id, iv], MTy::STR)?;
            let k = s.jdecode_key(key, key_mt, name, acc)?;
            let item = s.jitem(doc, id, iv)?;
            let r = s.jdecode_call(value, doc, item, strict)?;
            let x = s.junwrap(r, &[k], &[acc]);
            if !names_are_keys {
                // Two names that read as one key collide.
                let m = s.b.use_var(acc);
                let dup = s.jmap_contains(m, k)?;
                let zero = s.b.iconst(0);
                let fresh = s.b.icmp(Cc::Eq, dup, zero);
                s.jrequire(fresh, &[k, x], &[acc]);
            }
            let m = s.b.use_var(acc);
            let m2 = s.map_insert(m, k, x)?;
            s.b.def_var(acc, m2);
            Ok(())
        })?;
        Ok(self.b.use_var(acc))
    }

    /// The owned map `m` with room for `n` entries.
    fn jreserve(&mut self, m: Value, n: Value) -> Result<Value, Error> {
        let mt = self.ty_of(m);
        let slot = self.put_slot(m);
        let (kd, vd) = self.map_descs(mt)?;
        let vd = vd.ok_or_else(|| Error::new("a map has a value descriptor"))?;
        self.call_runtime("msrt_map_reserve", &[slot, kd, vd, n], MTy::UNIT)?;
        Ok(self.take_slot(slot, mt))
    }

    /// Whether the borrowed map `m` has the borrowed key `k`, as 0 or 1.
    fn jmap_contains(&mut self, m: Value, k: Value) -> Result<Value, Error> {
        let kt = self.ty_of(k);
        let copy = self.owned(Val { v: k, own: false });
        let slot = self.put_slot(copy);
        let (kd, vd) = self.map_descs(self.ty_of(m))?;
        let vd = vd.ok_or_else(|| Error::new("a map has a value descriptor"))?;
        // The runtime returns a Bool, the type `Map.contains` declares for the same symbol.
        let has = self.call_runtime("msrt_map_contains", &[m, kd, vd, slot], MTy::BOOL)?;
        let found = self
            .b
            .emit(Op::B2I, &[has], Imm::None, Some(MTy::INT))
            .expect("b2i");
        let back = self.take_slot(slot, kt);
        self.drop_value(back);
        Ok(found)
    }

    /// The key of type `key` that the member name `name` (owned) reads as; fails otherwise.
    fn jdecode_key(
        &mut self,
        key: &ct::Ty,
        key_mt: MTy,
        name: Value,
        acc: Var,
    ) -> Result<Value, Error> {
        if key.id.as_str() == "String" {
            return Ok(name);
        }
        if key.id.as_str() == "Int" || key.is_std("Duration") {
            let slot = self.jslot(MTy::INT);
            let st = self.status_code("msrt_json_dec_int", &[name, slot])?;
            self.drop_value(name);
            let z = self.b.iconst(0);
            let ok = self.b.icmp(Cc::Eq, st, z);
            self.jrequire(ok, &[], &[acc]);
            return Ok(self.take_slot(slot, MTy::INT));
        }
        if key.id.as_str() == "Bool" {
            let (t, f) = (self.b.str_lit("true"), self.b.str_lit("false"));
            let is_t = self.call_runtime("msrt_string_eq", &[name, t], MTy::BOOL)?;
            let is_f = self.call_runtime("msrt_string_eq", &[name, f], MTy::BOOL)?;
            self.drop_value(name);
            let any = self.b.binop(Op::Or, is_t, is_f);
            self.jrequire(any, &[], &[acc]);
            return Ok(is_t);
        }
        // A payload-free case by name: select between the case values, without branches.
        let TyKind::Alt(a) = self.b.m.types.kind(key_mt).clone() else {
            return Err(Error::new("an alternative key lowers to an alternative"));
        };
        let cases = ct::cases(key);
        // The index of the payload-free case the name selects, or -1.
        let mut idx = self.b.iconst(-1);
        for (i, c) in cases
            .iter()
            .enumerate()
            .filter(|(_, c)| c.fields.is_empty())
        {
            let lit = self.b.str_lit(c.name.as_str());
            let hit = self.call_runtime("msrt_string_eq", &[name, lit], MTy::BOOL)?;
            let k = self.b.iconst(i as i64);
            idx = self.b.select(hit, k, idx);
        }
        self.drop_value(name);
        let zero = self.b.iconst(0);
        let any = self.b.icmp(Cc::Ge, idx, zero);
        self.jrequire(any, &[], &[acc]);
        let out = self.jvar(key_mt);
        let join = self.b.new_block();
        let arms: Vec<(i64, _)> = cases
            .iter()
            .enumerate()
            .filter(|(_, c)| c.fields.is_empty())
            .map(|(i, _)| (i as i64, self.b.new_block()))
            .collect();
        let none = self.b.new_block();
        self.b.switch(idx, &arms, none);
        for (i, blk) in &arms {
            self.b.seal_block(*blk);
            self.b.switch_to(*blk);
            let v = self.b.alt_new(a, *i as u32, &[]);
            self.b.def_var(out, v);
            self.b.br(join, &[]);
        }
        self.b.seal_block(none);
        self.b.switch_to(none);
        self.b.unreachable();
        self.b.seal_block(join);
        self.b.switch_to(join);
        Ok(self.b.use_var(out))
    }

    /// The owned field values of the object node `id`, in declaration order. `owner` is the record
    /// type whose declaration holds the defaults; payload fields of a case have none.
    fn jdecode_fields(
        &mut self,
        owner: &ct::Ty,
        case: Option<ct::Name>,
        fields: &[JField],
        doc: Value,
        id: Value,
        strict: Value,
    ) -> Result<Vec<Value>, Error> {
        // Unknown members fail in strict mode.
        let (check, cont) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(strict, check, &[], cont, &[]);
        self.b.seal_block(check);
        self.b.switch_to(check);
        let names: Vec<String> = fields.iter().map(|f| f.name.clone()).collect();
        let list = self.jnames(&names);
        let unknown = self.jcall_masked("msrt_json_has_unknown", &[doc, id, list], 0xff)?;
        self.drop_value(list);
        let zero = self.b.iconst(0);
        let none_unknown = self.b.icmp(Cc::Eq, unknown, zero);
        self.jrequire(none_unknown, &[], &[]);
        self.b.br(cont, &[]);
        self.b.seal_block(cont);
        self.b.switch_to(cont);
        let mut vars: Vec<Var> = Vec::new();
        for (i, f) in fields.iter().enumerate() {
            let ft = self.jmty(&f.ty)?;
            let var = self.jvar(ft);
            let key = self.b.str_lit(&f.name);
            let idx = self.call_runtime("msrt_json_find", &[doc, id, key], MTy::INT)?;
            let z = self.b.iconst(0);
            let found = self.b.icmp(Cc::Ge, idx, z);
            let (present, absent, join) =
                (self.b.new_block(), self.b.new_block(), self.b.new_block());
            self.b.br_if(found, present, &[], absent, &[]);
            self.b.seal_block(present);
            self.b.seal_block(absent);
            self.b.switch_to(present);
            let item = self.jitem(doc, id, idx)?;
            let r = self.jdecode_call(&f.ty, doc, item, strict)?;
            let x = self.junwrap(r, &[], &vars);
            self.b.def_var(var, x);
            self.b.br(join, &[]);
            self.b.switch_to(absent);
            let earlier: Vec<(ct::Name, Value)> = fields
                .iter()
                .zip(&vars)
                .map(|(f, v)| (ct::n(&f.name), self.b.use_var(*v)))
                .collect();
            let d = self.jabsent(owner, case, i, &f.ty, ft, &earlier)?;
            match d {
                Some(d) => {
                    self.b.def_var(var, d);
                    self.b.br(join, &[]);
                }
                None => {
                    // A required member is missing.
                    for v in &vars {
                        let x = self.b.use_var(*v);
                        self.drop_value(x);
                    }
                    self.jfail();
                }
            }
            self.b.seal_block(join);
            self.b.switch_to(join);
            vars.push(var);
        }
        let mut vals = Vec::new();
        for v in vars {
            vals.push(self.b.use_var(v));
        }
        Ok(vals)
    }

    /// The owned value of an absent member: its default, `none` for an `Optional`, else `None`.
    fn jabsent(
        &mut self,
        owner: &ct::Ty,
        case: Option<ct::Name>,
        i: usize,
        ty: &ct::Ty,
        mt: MTy,
        earlier: &[(ct::Name, Value)],
    ) -> Result<Option<Value>, Error> {
        if ty.id.as_str() == "Unit" {
            // `Unit` has no JSON form: encoding omits the member and decoding restores it.
            return Ok(Some(self.b.unit()));
        }
        if case.is_some() {
            return Ok(ty.is_std("Optional").then(|| self.none_owned(mt)));
        }
        let has_default = owner
            .symbol()
            .and_then(|s| s.decl.clone())
            .and_then(|d| d.record_fields().get(i).map(|f| f.default.is_some()))
            .unwrap_or(false);
        if has_default || ty.is_std("Optional") {
            // Temporaries of the default end with it: this value joins other paths.
            let mark = self.temps.len();
            let v = self.field_default(owner, None, i, earlier)?;
            self.flush_temps(mark);
            return Ok(Some(v));
        }
        Ok(None)
    }

    fn jdecode_alternative(
        &mut self,
        t: &ct::Ty,
        mt: MTy,
        doc: Value,
        id: Value,
        strict: Value,
    ) -> Result<(), Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("an alternative lowers to an alternative"));
        };
        let cases = ct::cases(t);
        let names: Vec<String> = cases.iter().map(|c| c.name.to_string()).collect();
        let list = self.jnames(&names);
        let slot = self.jslot(MTy::INT);
        let idx = self.call_runtime("msrt_json_variant", &[doc, id, list, slot], MTy::INT)?;
        self.drop_value(list);
        let payload = self.take_slot(slot, MTy::INT);
        let zero = self.b.iconst(0);
        let known = self.b.icmp(Cc::Ge, idx, zero);
        self.jrequire(known, &[], &[]);
        let blocks: Vec<_> = cases.iter().map(|_| self.b.new_block()).collect();
        let other = self.b.new_block();
        let arms: Vec<(i64, _)> = blocks
            .iter()
            .enumerate()
            .map(|(i, b)| (i as i64, *b))
            .collect();
        self.b.switch(idx, &arms, other);
        self.b.seal_block(other);
        self.b.switch_to(other);
        self.jfail();
        for (i, c) in cases.iter().enumerate() {
            self.b.seal_block(blocks[i]);
            self.b.switch_to(blocks[i]);
            let z = self.b.iconst(0);
            if c.fields.is_empty() {
                // A payload-free case is its name as a string.
                let plain = self.b.icmp(Cc::Lt, payload, z);
                self.jrequire(plain, &[], &[]);
                let v = self.b.alt_new(a, i as u32, &[]);
                self.jfinish(v);
                continue;
            }
            let tagged = self.b.icmp(Cc::Ge, payload, z);
            self.jrequire(tagged, &[], &[]);
            let mask = self.b.iconst(0xffff_ffff);
            let pid = self.b.binop(Op::And, payload, mask);
            self.jexpect_kind(doc, pid, KIND_OBJECT)?;
            let fields = jfields(&c.fields);
            let vals = self.jdecode_fields(t, Some(c.name), &fields, doc, pid, strict)?;
            let v = self.b.alt_new(a, i as u32, &vals);
            self.jfinish(v);
        }
        Ok(())
    }

    /// `JsonValue` keeps the document's shape: the case follows the node kind.
    fn jdecode_tree(
        &mut self,
        t: &ct::Ty,
        mt: MTy,
        doc: Value,
        id: Value,
        strict: Value,
    ) -> Result<(), Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("JsonValue is an alternative"));
        };
        let cases = ct::cases(t);
        let case_index = |name: &str| cases.iter().position(|c| c.name.as_str() == name);
        let missing = || Error::new("JsonValue lacks a case");
        let kind = self.jkind(doc, id)?;
        let blocks: Vec<_> = (0..6).map(|_| self.b.new_block()).collect();
        let other = self.b.new_block();
        let arms: Vec<(i64, _)> = blocks
            .iter()
            .enumerate()
            .map(|(i, b)| (i as i64, *b))
            .collect();
        self.b.switch(kind, &arms, other);
        self.b.seal_block(other);
        self.b.switch_to(other);
        self.jfail();
        for (k, block) in blocks.iter().enumerate() {
            self.b.seal_block(*block);
            self.b.switch_to(*block);
            let v = match k as i64 {
                KIND_NULL => {
                    let c = case_index("Null").ok_or_else(missing)?;
                    self.b.alt_new(a, c as u32, &[])
                }
                KIND_BOOL => {
                    let c = case_index("BoolValue").ok_or_else(missing)?;
                    let raw = self.jcall_masked("msrt_json_bool", &[doc, id], 0xff)?;
                    let z = self.b.iconst(0);
                    let b = self.b.icmp(Cc::Ne, raw, z);
                    self.b.alt_new(a, c as u32, &[b])
                }
                KIND_NUMBER => {
                    let c = case_index("NumberValue").ok_or_else(missing)?;
                    let s = self.jtext(doc, id)?;
                    self.b.alt_new(a, c as u32, &[s])
                }
                KIND_STRING => {
                    let c = case_index("StringValue").ok_or_else(missing)?;
                    let s = self.jtext(doc, id)?;
                    self.b.alt_new(a, c as u32, &[s])
                }
                KIND_ARRAY => {
                    let c = case_index("ArrayValue").ok_or_else(missing)?;
                    let lt = self.jmty(&cases[c].fields[0].ty)?;
                    let l = self.jdecode_items(t, lt, doc, id, strict)?;
                    self.b.alt_new(a, c as u32, &[l])
                }
                _ => {
                    let c = case_index("ObjectValue").ok_or_else(missing)?;
                    let map = &cases[c].fields[0].ty;
                    let mapt = self.jmty(map)?;
                    let m =
                        self.jdecode_members(&map.args[0], &map.args[1], mapt, doc, id, strict)?;
                    self.b.alt_new(a, c as u32, &[m])
                }
            };
            self.jfinish(v);
        }
        Ok(())
    }

    // ----------------------------------------------------------------- encoding

    pub(crate) fn lower_encoder(&mut self, t: &ct::Ty) -> Result<(), Error> {
        let p = self.b.params();
        let (w, value) = (p[0], p[1]);
        let mt = self.jmty(t)?;
        let written = self.jencode(t, mt, w, value)?;
        self.b.ret(Some(written));
        Ok(())
    }

    fn jwriter_ty(&mut self) -> MTy {
        self.b.m.types.obj("JsonWriter", Vec::new())
    }

    /// A writer call without a result.
    fn jw(&mut self, sym: &str, args: &[Value]) -> Result<(), Error> {
        self.call_runtime(sym, args, MTy::UNIT)?;
        Ok(())
    }

    /// The result of an encoder that wrote its value.
    fn jwritten(&mut self) -> Value {
        self.b.iconst(0)
    }

    /// The result of an encoder whose value has no JSON form; nothing was written. The omission
    /// is noted for strict `stringify`.
    fn jno_form(&mut self, w: Value) -> Result<Value, Error> {
        self.jw("msrt_json_w_no_form", &[w])?;
        Ok(self.b.iconst(-1))
    }

    /// Writes `value` (borrowed) to the writer `w`; 0, or -1 when it has no JSON form and nothing
    /// was written.
    fn jencode(&mut self, t: &ct::Ty, mt: MTy, w: Value, value: Value) -> Result<Value, Error> {
        if t.is_source_type("@std/json.ms", "JsonValue") {
            return self.jencode_tree(t, mt, w, value);
        }
        match t.id.as_str() {
            "Int" => {
                self.jw("msrt_json_w_int", &[w, value])?;
                return Ok(self.jwritten());
            }
            "Float" => {
                self.jw("msrt_json_w_float", &[w, value])?;
                return Ok(self.jwritten());
            }
            "Bool" => {
                self.jw("msrt_json_w_bool", &[w, value])?;
                return Ok(self.jwritten());
            }
            "String" => {
                self.jw("msrt_json_w_string", &[w, value])?;
                return Ok(self.jwritten());
            }
            "Unit" | "Never" => return self.jno_form(w),
            _ => {}
        }
        if t.is_std("Optional") {
            let has = self.b.opt_is_some(value);
            let out = self.b.declare_var(MTy::INT, Mode::Borrow);
            let (yes, no, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
            self.b.br_if(has, yes, &[], no, &[]);
            self.b.seal_block(yes);
            self.b.seal_block(no);
            self.b.switch_to(yes);
            let inner = self.b.opt_get(value);
            let written = self.jencode_nested(&t.args[0], w, inner)?;
            self.b.def_var(out, written);
            self.b.br(join, &[]);
            self.b.switch_to(no);
            self.jw("msrt_json_w_null", &[w])?;
            let written = self.jwritten();
            self.b.def_var(out, written);
            self.b.br(join, &[]);
            self.b.seal_block(join);
            self.b.switch_to(join);
            return Ok(self.b.use_var(out));
        }
        if t.is_std("List") {
            return self.jencode_list(&t.args[0], w, value);
        }
        if t.is_std("Set") {
            return self.jencode_set(&t.args[0], w, value);
        }
        if t.is_std("Map") {
            return self.jencode_map(&t.args[0], &t.args[1], w, value);
        }
        if t.is_std("Duration") {
            self.jw("msrt_json_w_int", &[w, value])?;
            return Ok(self.jwritten());
        }
        if let Some(c) = self.json_encode_impl(t) {
            // `JsonEncode` replaces the structural encoding.
            let fid = self.cx.function_for(self.b.m, &c, &ct::Subst::new())?;
            let tree = self.b.call(fid, &[value]);
            let jt = ct::sub(&self.cx.callable_result(&c)?, &ct::Subst::new());
            let written = self.jencode_call(&jt, w, tree)?;
            self.drop_value(tree);
            return Ok(written);
        }
        if t.is_std("Timestamp") || t.is_std("Decimal") {
            let text = self.format_value(Val {
                v: value,
                own: false,
            })?;
            let sym = if t.is_std("Decimal") {
                "msrt_json_w_number"
            } else {
                "msrt_json_w_string"
            };
            self.jw(sym, &[w, text.v])?;
            if text.own {
                self.drop_value(text.v);
            }
            return Ok(self.jwritten());
        }
        // Bytes are standard base64 text.
        if mt == MTy::BYTES && t.is_std("Bytes") {
            let no_url = self.b.bconst(false);
            let text =
                self.call_runtime("msrt_encoding_base64_encode", &[value, no_url], MTy::STR)?;
            self.jw("msrt_json_w_string", &[w, text])?;
            self.drop_value(text);
            return Ok(self.jwritten());
        }
        // A BigInt is its digits.
        if t.is_std("BigInt") {
            let radix = self.b.iconst(10);
            let text =
                self.call_runtime("msstd_bigint_to_string_radix", &[value, radix], MTy::STR)?;
            self.jw("msrt_json_w_number", &[w, text])?;
            self.drop_value(text);
            return Ok(self.jwritten());
        }
        // A URL is its formatted text.
        if t.is_source_type("@std/net.ms", "Url") {
            return self.jencode_url(w, value);
        }
        // An address or network is its text.
        for (name, sym) in [
            ("IpAddress", "msrt_net_ip_address_text"),
            ("Cidr", "msrt_net_cidr_text"),
        ] {
            if t.is_source_type("@std/net.ms", name) {
                let text = self.call_runtime(sym, &[value], MTy::STR)?;
                self.jw("msrt_json_w_string", &[w, text])?;
                self.drop_value(text);
                return Ok(self.jwritten());
            }
        }
        match t.kind {
            ct::Kind::Record => {
                let fields = jfields(&ct::fields(t));
                let TyKind::Rec(r) = self.b.m.types.kind(mt).clone() else {
                    return Err(Error::new("a record type lowers to a record"));
                };
                self.jw("msrt_json_w_begin_object", &[w])?;
                for (i, f) in fields.iter().enumerate() {
                    let fv = self.b.rec_get(r, i as u32, value);
                    self.jencode_member(w, &f.name, &f.ty, fv)?;
                }
                self.jw("msrt_json_w_end_object", &[w])?;
                Ok(self.jwritten())
            }
            ct::Kind::Alternative => self.jencode_alternative(t, mt, w, value),
            // No JSON form: omitted, `null` in a list, `InvalidData` at the root.
            _ => self.jno_form(w),
        }
    }

    /// Calls `body` to write one value after `start` has begun its slot (a key or an item); when
    /// the value has no JSON form, removes the slot again and runs `fallback`.
    fn jslot_or(
        &mut self,
        w: Value,
        written: Value,
        fallback: &mut dyn FnMut(&mut Self) -> Result<(), Error>,
    ) -> Result<(), Error> {
        let z = self.b.iconst(0);
        let has_form = self.b.icmp(Cc::Ge, written, z);
        let (undo, after) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(has_form, after, &[], undo, &[]);
        self.b.seal_block(undo);
        self.b.switch_to(undo);
        self.jw("msrt_json_w_undo", &[w])?;
        fallback(self)?;
        self.b.br(after, &[]);
        self.b.seal_block(after);
        self.b.switch_to(after);
        Ok(())
    }

    /// Writes member `name` unless the value has no JSON form; an absent optional field is
    /// omitted too.
    fn jencode_member(
        &mut self,
        w: Value,
        name: &str,
        ty: &ct::Ty,
        value: Value,
    ) -> Result<(), Error> {
        let after = self.b.new_block();
        let (inner_ty, inner) = if ty.is_std("Optional") {
            let some = self.b.opt_is_some(value);
            let present = self.b.new_block();
            self.b.br_if(some, present, &[], after, &[]);
            self.b.seal_block(present);
            self.b.switch_to(present);
            (ty.args[0].clone(), self.b.opt_get(value))
        } else {
            (ty.clone(), value)
        };
        let key = self.b.str_lit(&json_quote(name));
        self.jw("msrt_json_w_key_quoted", &[w, key])?;
        let written = self.jencode_nested(&inner_ty, w, inner)?;
        self.jslot_or(w, written, &mut |_| Ok(()))?;
        self.b.br(after, &[]);
        self.b.seal_block(after);
        self.b.switch_to(after);
        Ok(())
    }

    /// The `to_json` of the type's `JsonEncode` implementation, when it has one.
    fn json_encode_impl(&self, t: &ct::Ty) -> Option<Rc<ms_check::hir::Callable>> {
        let key = ct::type_key(t);
        let m = self.cx.methods.iter().find(|m| {
            m.contract
                .as_ref()
                .is_some_and(|c| c.is_source_type("@std/json.ms", "JsonEncode"))
                && ct::type_key(&m.receiver) == key
        })?;
        let decl = m.decl.as_ref()?;
        self.callable_of_decl(m.module, Some(decl.id())).ok()
    }

    /// `Url` as the string `url.format` makes; a URL that cannot be formatted has no JSON form.
    fn jencode_url(&mut self, w: Value, value: Value) -> Result<Value, Error> {
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(MTy::STR), Some(MTy::PTR))
            .expect("slot");
        let code = self.status_code("msrt_url_format", &[value, slot])?;
        let zero = self.b.iconst(0);
        let good = self.b.icmp(Cc::Eq, code, zero);
        let out = self.b.declare_var(MTy::INT, Mode::Borrow);
        let (yes, no, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br_if(good, yes, &[], no, &[]);
        self.b.seal_block(yes);
        self.b.seal_block(no);
        self.b.switch_to(yes);
        let text = self
            .b
            .emit(Op::Take, &[slot], Imm::Ty(MTy::STR), Some(MTy::STR))
            .expect("take");
        self.jw("msrt_json_w_string", &[w, text])?;
        self.drop_value(text);
        let written = self.jwritten();
        self.b.def_var(out, written);
        self.b.br(join, &[]);
        self.b.switch_to(no);
        let none = self.jno_form(w)?;
        self.b.def_var(out, none);
        self.b.br(join, &[]);
        self.b.seal_block(join);
        self.b.switch_to(join);
        Ok(self.b.use_var(out))
    }

    /// Writes one array item; an element without a JSON form is `null`.
    fn jencode_item(&mut self, elem: &ct::Ty, w: Value, item: Value) -> Result<(), Error> {
        self.jw("msrt_json_w_item", &[w])?;
        let written = self.jencode_nested(elem, w, item)?;
        self.jslot_or(w, written, &mut |s| {
            s.jw("msrt_json_w_item", &[w])?;
            s.jw("msrt_json_w_null", &[w])
        })
    }

    /// A set is an array of its elements in insertion order.
    fn jencode_set(&mut self, elem: &ct::Ty, w: Value, value: Value) -> Result<Value, Error> {
        self.jw("msrt_json_w_begin_array", &[w])?;
        let elem = elem.clone();
        self.each_entry(value, &mut |s, key, _| s.jencode_item(&elem, w, key))?;
        self.jw("msrt_json_w_end_array", &[w])?;
        Ok(self.jwritten())
    }

    /// Writes the member name of the map key `k` of type `key`.
    fn jencode_map_key(&mut self, key: &ct::Ty, w: Value, k: Value) -> Result<(), Error> {
        if key.id.as_str() == "String" {
            return self.jw("msrt_json_w_key", &[w, k]);
        }
        if !jplain_alt(key) {
            let name = self.format_value(Val { v: k, own: false })?;
            self.jw("msrt_json_w_key", &[w, name.v])?;
            if name.own {
                self.drop_value(name.v);
            }
            return Ok(());
        }
        // The case name, selected by the key's tag.
        let key_mt = self.jmty(key)?;
        let TyKind::Alt(_) = self.b.m.types.kind(key_mt).clone() else {
            return Err(Error::new("an alternative key lowers to an alternative"));
        };
        let cases = ct::cases(key);
        let tag = self.b.alt_tag(k);
        let blocks: Vec<_> = cases.iter().map(|_| self.b.new_block()).collect();
        let join = self.b.new_block();
        let arms: Vec<(i64, _)> = blocks
            .iter()
            .enumerate()
            .map(|(i, b)| (i as i64, *b))
            .collect();
        let other = self.b.new_block();
        self.b.switch(tag, &arms, other);
        self.b.seal_block(other);
        self.b.switch_to(other);
        self.b.unreachable();
        for (i, c) in cases.iter().enumerate() {
            self.b.seal_block(blocks[i]);
            self.b.switch_to(blocks[i]);
            let name = self.b.str_lit(&json_quote(c.name.as_str()));
            self.jw("msrt_json_w_key_quoted", &[w, name])?;
            self.b.br(join, &[]);
        }
        self.b.seal_block(join);
        self.b.switch_to(join);
        Ok(())
    }

    /// A map is an object whose keys are the text form of its keys; a value without a JSON form
    /// leaves its entry out.
    fn jencode_map(
        &mut self,
        key: &ct::Ty,
        value_ty: &ct::Ty,
        w: Value,
        value: Value,
    ) -> Result<Value, Error> {
        let keyable = matches!(key.id.as_str(), "String" | "Int" | "Bool" | "Float")
            || key.is_std("Duration")
            || key.is_std("Timestamp")
            || key.is_std("Decimal")
            || jplain_alt(key);
        if !keyable {
            return self.jno_form(w);
        }
        self.jw("msrt_json_w_begin_object", &[w])?;
        let (key, value_ty) = (key.clone(), value_ty.clone());
        self.each_entry(value, &mut |s, k, v| {
            let v = v.ok_or_else(|| Error::new("a map entry has a value"))?;
            s.jencode_map_key(&key, w, k)?;
            let written = s.jencode_nested(&value_ty, w, v)?;
            s.jslot_or(w, written, &mut |_| Ok(()))
        })?;
        self.jw("msrt_json_w_end_object", &[w])?;
        Ok(self.jwritten())
    }

    fn jencode_list(&mut self, elem: &ct::Ty, w: Value, value: Value) -> Result<Value, Error> {
        self.jw("msrt_json_w_begin_array", &[w])?;
        let n = self.b.list_len(value);
        let zero = self.b.iconst(0);
        self.counted_loop(zero, n, &mut |s, iv| {
            let item = s.b.list_get(value, iv);
            s.jencode_item(elem, w, item)
        })?;
        self.jw("msrt_json_w_end_array", &[w])?;
        Ok(self.jwritten())
    }

    fn jencode_alternative(
        &mut self,
        t: &ct::Ty,
        mt: MTy,
        w: Value,
        value: Value,
    ) -> Result<Value, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("an alternative lowers to an alternative"));
        };
        let cases = ct::cases(t);
        let tag = self.b.alt_tag(value);
        let blocks: Vec<_> = cases.iter().map(|_| self.b.new_block()).collect();
        let join = self.b.new_block();
        let arms: Vec<(i64, _)> = blocks
            .iter()
            .enumerate()
            .map(|(i, b)| (i as i64, *b))
            .collect();
        let other = self.b.new_block();
        self.b.switch(tag, &arms, other);
        self.b.seal_block(other);
        self.b.switch_to(other);
        self.b.unreachable();
        for (i, c) in cases.iter().enumerate() {
            self.b.seal_block(blocks[i]);
            self.b.switch_to(blocks[i]);
            if c.fields.is_empty() {
                let name = self.b.str_lit(c.name.as_str());
                self.jw("msrt_json_w_string", &[w, name])?;
            } else {
                self.jw("msrt_json_w_begin_object", &[w])?;
                let key = self.b.str_lit(&json_quote(c.name.as_str()));
                self.jw("msrt_json_w_key_quoted", &[w, key])?;
                self.jw("msrt_json_w_begin_object", &[w])?;
                for (j, f) in c.fields.iter().enumerate() {
                    let fv = self.b.alt_get(a, i as u32, j as u32, value);
                    self.jencode_member(w, f.name.as_str(), &f.ty, fv)?;
                }
                self.jw("msrt_json_w_end_object", &[w])?;
                self.jw("msrt_json_w_end_object", &[w])?;
            }
            self.b.br(join, &[]);
        }
        self.b.seal_block(join);
        self.b.switch_to(join);
        Ok(self.jwritten())
    }

    /// A stored `JsonValue` is written as it is, by the runtime walking the value through
    /// [`Self::json_tree_view`].
    fn jencode_tree(
        &mut self,
        t: &ct::Ty,
        mt: MTy,
        w: Value,
        value: Value,
    ) -> Result<Value, Error> {
        let view = self.json_tree_view(t, mt)?;
        let view = self
            .b
            .emit(Op::FuncAddr, &[], Imm::Func(view), Some(MTy::PTR))
            .expect("func.addr");
        let desc = self.type_desc(mt);
        // The runtime reads the value from memory; the copy is bitwise and never dropped.
        let slot = self.jslot(mt);
        self.b.emit(Op::Store, &[slot, value], Imm::None, None);
        self.jw("msrt_json_w_tree", &[w, desc, view, slot])?;
        Ok(self.jwritten())
    }

    // ------------------------------------------------------------- entry points

    /// `parse[T](text, limits, ignore_unknown_fields)`.
    pub(crate) fn json_parse(&mut self, t: &ct::Ty, rty: MTy, args: &[NArg]) -> Result<Val, Error> {
        let text = self.jarg(args, "text")?;
        let text = self.borrow(text);
        let ignore = args
            .iter()
            .find(|a| a.name.as_str() == "ignore_unknown_fields");
        let strict = match ignore {
            Some(a) => {
                let v = self.borrow(a.val);
                let z = self.b.bconst(false);
                self.b.icmp(Cc::Eq, v, z)
            }
            None => self.b.bconst(false),
        };
        let limits = args
            .iter()
            .find(|a| a.name.as_str() == "limits")
            .map(|a| a.val);
        let flat = self.jlimits(limits)?;
        // An untyped parse is built by the runtime while scanning, without a document.
        let tree = t.is_source_type("@std/json.ms", "JsonValue");
        let doc_ty = self.jdoc_ty();
        let mut vals = vec![text];
        vals.extend(flat);
        let (doc_slot, root_slot) = if tree {
            let mt = self.jmty(t)?;
            let ctor = self.json_tree_ctor(t, mt)?;
            let ctor = self
                .b
                .emit(Op::FuncAddr, &[], Imm::Func(ctor), Some(MTy::PTR))
                .expect("func.addr");
            let desc = self.type_desc(mt);
            let slot = self.jslot(mt);
            vals.extend([desc, ctor, slot]);
            (slot, slot)
        } else {
            let doc_slot = self.jslot(doc_ty);
            let root_slot = self.jslot(MTy::INT);
            vals.push(doc_slot);
            vals.push(root_slot);
            (doc_slot, root_slot)
        };
        let sym = if tree {
            "msrt_json_parse_tree"
        } else {
            "msrt_json_parse"
        };
        let code = self.status_code(sym, &vals)?;
        let zero = self.b.iconst(0);
        let good = self.b.icmp(Cc::Eq, code, zero);
        let TyKind::Alt(ra) = self.b.m.types.kind(rty).clone() else {
            return Err(Error::new("parse returns a Result"));
        };
        let ok = self.ok_case_index(ra)?;
        let err = self.b.m.alts[ra.index()]
            .cases
            .iter()
            .position(|c| c.name == "error")
            .ok_or_else(|| Error::new("not a Result"))?;
        self.two_ways(
            good,
            rty,
            &mut |s| {
                if tree {
                    let mt = s.jmty(t)?;
                    let x = s.take_slot(doc_slot, mt);
                    return Ok(Some(s.b.alt_new(ra, ok as u32, &[x])));
                }
                let doc = s.take_slot(doc_slot, doc_ty);
                let raw = s.take_slot(root_slot, MTy::INT);
                let m = s.b.iconst(0xffff_ffff);
                let root = s.b.binop(Op::And, raw, m);
                let r = s.jdecode_call(t, doc, root, strict)?;
                s.drop_value(doc);
                let good = s.b.opt_is_some(r);
                let v = s.two_ways(
                    good,
                    rty,
                    &mut |s| {
                        // Dropping `r` beside the copy lets the optimizer move the payload out.
                        let x = s.b.opt_get(r);
                        let x = s.owned(Val { v: x, own: false });
                        s.drop_value(r);
                        Ok(Some(s.b.alt_new(ra, ok as u32, &[x])))
                    },
                    &mut |s| {
                        s.drop_value(r);
                        let e = s.json_error(ra, err, "InvalidData")?;
                        Ok(Some(e))
                    },
                )?;
                Ok(Some(v.v))
            },
            &mut |s| {
                let et = s.b.m.alts[ra.index()].cases[err].fields[0].1;
                let TyKind::Alt(ea) = s.b.m.types.kind(et).clone() else {
                    return Err(Error::new("a runtime status needs an error alternative"));
                };
                let cases = s.status_cases(ea);
                let e = s.status_error(ea, code, &cases, None)?;
                Ok(Some(s.b.alt_new(ra, err as u32, &[e])))
            },
        )
    }

    /// The thunk the runtime calls to make a `JsonValue` of a case from its payload:
    /// `ctor(kind, payload, out)` moves the payload (`Bool` byte, `String`, list or map) into a
    /// new value of the case of that node kind written at `out`.
    fn json_tree_ctor(&mut self, t: &ct::Ty, mt: MTy) -> Result<FuncId, Error> {
        let key = format!("json-tree:{}", ct::type_key(t));
        if let Some(f) = self.cx.helpers.get(&key) {
            return Ok(*f);
        }
        let TyKind::Alt(a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("JsonValue is an alternative"));
        };
        let cases = ct::cases(t);
        let case = |name: &str| {
            cases
                .iter()
                .position(|c| c.name.as_str() == name)
                .ok_or_else(|| Error::new("JsonValue lacks a case"))
        };
        let order = [
            "Null",
            "BoolValue",
            "NumberValue",
            "StringValue",
            "ArrayValue",
            "ObjectValue",
        ]
        .map(case);
        let mut index = [0usize; 6];
        for (slot, found) in index.iter_mut().zip(order) {
            *slot = found?;
        }
        let payload_tys = [
            None,
            Some(MTy::BOOL),
            Some(MTy::STR),
            Some(MTy::STR),
            Some(self.jmty(&cases[index[4]].fields[0].ty)?),
            Some(self.jmty(&cases[index[5]].fields[0].ty)?),
        ];
        let mut tb = FuncBuilder::new(
            self.b.m,
            "json_tree_ctor",
            vec![borrowed(MTy::INT), borrowed(MTy::PTR), borrowed(MTy::PTR)],
            MTy::INT,
        );
        tb.func_mut().linkage = ms_mir::ir::Linkage::Internal;
        let args = tb.params();
        let (kind, payload, out) = (args[0], args[1], args[2]);
        let blocks: Vec<_> = (0..6).map(|_| tb.new_block()).collect();
        let other = tb.new_block();
        let arms: Vec<(i64, _)> = blocks
            .iter()
            .enumerate()
            .map(|(i, b)| (i as i64, *b))
            .collect();
        tb.switch(kind, &arms, other);
        tb.seal_block(other);
        tb.switch_to(other);
        let zero = tb.iconst(0);
        tb.ret(Some(zero));
        for (k, block) in blocks.iter().enumerate() {
            tb.seal_block(*block);
            tb.switch_to(*block);
            let fields: Vec<Value> = payload_tys[k]
                .map(|ty| {
                    tb.emit(Op::Take, &[payload], Imm::Ty(ty), Some(ty))
                        .expect("take")
                })
                .into_iter()
                .collect();
            let v = tb.alt_new(a, index[k] as u32, &fields);
            tb.emit(Op::Put, &[out, v], Imm::None, None);
            let zero = tb.iconst(0);
            tb.ret(Some(zero));
        }
        let thunk = tb.into_func();
        let id = self.b.m.add_func(thunk);
        self.cx.helpers.insert(key, id);
        Ok(id)
    }

    /// The thunk the runtime calls to read a `JsonValue`: `view(value, payload)` returns the node
    /// kind of the case `value` holds and writes the case's payload (`Bool` byte, `String`, list
    /// or map; nothing for `Null`) at `payload`, bitwise.
    fn json_tree_view(&mut self, t: &ct::Ty, mt: MTy) -> Result<FuncId, Error> {
        let key = format!("json-tree-view:{}", ct::type_key(t));
        if let Some(f) = self.cx.helpers.get(&key) {
            return Ok(*f);
        }
        let TyKind::Alt(a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("JsonValue is an alternative"));
        };
        let cases = ct::cases(t);
        let kinds = [
            "Null",
            "BoolValue",
            "NumberValue",
            "StringValue",
            "ArrayValue",
            "ObjectValue",
        ];
        let mut tb = FuncBuilder::new(
            self.b.m,
            "json_tree_view",
            vec![borrowed(MTy::PTR), borrowed(MTy::PTR)],
            MTy::INT,
        );
        tb.func_mut().linkage = ms_mir::ir::Linkage::Internal;
        let args = tb.params();
        let (value, out) = (args[0], args[1]);
        let v = tb
            .emit(Op::Load, &[value], Imm::Ty(mt), Some(mt))
            .expect("load");
        let tag = tb.alt_tag(v);
        let blocks: Vec<_> = cases.iter().map(|_| tb.new_block()).collect();
        let arms: Vec<(i64, _)> = blocks
            .iter()
            .enumerate()
            .map(|(i, b)| (i as i64, *b))
            .collect();
        let other = tb.new_block();
        tb.switch(tag, &arms, other);
        tb.seal_block(other);
        tb.switch_to(other);
        tb.unreachable();
        for (i, c) in cases.iter().enumerate() {
            tb.seal_block(blocks[i]);
            tb.switch_to(blocks[i]);
            let kind = kinds
                .iter()
                .position(|k| *k == c.name.as_str())
                .ok_or_else(|| Error::new("json: unexpected JsonValue case"))?;
            if !c.fields.is_empty() {
                let payload = tb.alt_get(a, i as u32, 0, v);
                tb.emit(Op::Store, &[out, payload], Imm::None, None);
            }
            let k = tb.iconst(kind as i64);
            tb.ret(Some(k));
        }
        let thunk = tb.into_func();
        let id = self.b.m.add_func(thunk);
        self.cx.helpers.insert(key, id);
        Ok(id)
    }

    /// `error(JsonError.<case>)`.
    fn json_error(
        &mut self,
        ra: ms_mir::types::AltId,
        err: usize,
        case: &str,
    ) -> Result<Value, Error> {
        let et = self.b.m.alts[ra.index()].cases[err].fields[0].1;
        let TyKind::Alt(ea) = self.b.m.types.kind(et).clone() else {
            return Err(Error::new("JsonError is an alternative"));
        };
        let idx = self.b.m.alts[ea.index()]
            .cases
            .iter()
            .position(|c| c.name == case)
            .ok_or_else(|| Error::new("JsonError lacks a case"))?;
        let e = self.b.alt_new(ea, idx as u32, &[]);
        Ok(self.b.alt_new(ra, err as u32, &[e]))
    }

    pub(crate) fn jarg(&self, args: &[NArg], name: &str) -> Result<Val, Error> {
        args.iter()
            .find(|a| a.name.as_str() == name)
            .map(|a| a.val)
            .ok_or_else(|| Error::new(format!("missing argument {name}")))
    }

    /// The flattened `(has, value)` pairs of the optional `JsonLimits` argument.
    pub(crate) fn jlimits(&mut self, limits: Option<Val>) -> Result<Vec<Value>, Error> {
        let Some(l) = limits else {
            let (f, z) = (self.b.bconst(false), self.b.iconst(0));
            return Ok(vec![f, z, f, z, f, z]);
        };
        let lv = self.borrow(l);
        if !matches!(self.b.m.types.kind(self.ty_of(lv)), TyKind::Opt(_)) {
            // Written as the record itself: the optional wrapper is implicit.
            return self.jlimit_fields(lv);
        }
        // Without a branch: the fields of an absent record are masked out by its presence.
        let has = self.b.opt_is_some(lv);
        let rec = self.b.opt_get(lv);
        let mut out = self.jlimit_fields(rec)?;
        for i in 0..3 {
            out[i * 2] = self.b.binop(Op::And, out[i * 2], has);
        }
        Ok(out)
    }

    /// The `(has, value)` pairs of a present `JsonLimits` record.
    fn jlimit_fields(&mut self, rec: Value) -> Result<Vec<Value>, Error> {
        let TyKind::Rec(r) = self.b.m.types.kind(self.ty_of(rec)).clone() else {
            return Err(Error::new("JsonLimits is a record"));
        };
        let mut out = Vec::new();
        for i in 0..3 {
            let f = self.b.rec_get(r, i, rec);
            let (h, v) = self.flatten_optional(
                Input {
                    val: Some(Val { v: f, own: false }),
                    wrapped: false,
                },
                "i64",
            )?;
            out.push(h);
            out.push(v);
        }
        Ok(out)
    }

    /// `stringify(value, max_bytes, indent, strict)`.
    pub(crate) fn json_stringify(
        &mut self,
        t: ct::Ty,
        rty: MTy,
        args: &[NArg],
    ) -> Result<Val, Error> {
        let value = self.jarg(args, "value")?;
        let value = self.borrow(value);
        let flat = |s: &mut Self, name: &str| -> Result<(Value, Value), Error> {
            let a = args.iter().find(|a| a.name.as_str() == name);
            s.flatten_optional(
                Input {
                    val: a.map(|a| a.val),
                    wrapped: false,
                },
                "i64",
            )
        };
        let (hm, vm) = flat(self, "max_bytes")?;
        let (hi, vi) = flat(self, "indent")?;
        let writer_ty = self.jwriter_ty();
        let writer = self.call_runtime("msrt_json_writer_new", &[hm, vm, hi, vi], writer_ty)?;
        let wvar = self.jvar(writer_ty);
        self.b.def_var(wvar, writer);
        let enc = {
            let hir = self.hir.clone();
            self.cx.json_fn(self.b.m, &hir, &t, true)?
        };
        let written = self.b.call(enc, &[writer, value]);
        let zero = self.b.iconst(0);
        let has_form = self.b.icmp(Cc::Ge, written, zero);
        // `strict` also rejects a value left out below the root.
        let has_form = match args.iter().find(|a| a.name.as_str() == "strict") {
            Some(a) => {
                let strict = self.borrow(a.val);
                let lost = self.call_runtime("msrt_json_w_lost", &[writer], MTy::BOOL)?;
                let bad = self.b.binop(Op::And, strict, lost);
                let f = self.b.bconst(false);
                let intact = self.b.icmp(Cc::Eq, bad, f);
                self.b.binop(Op::And, has_form, intact)
            }
            None => has_form,
        };
        let TyKind::Alt(ra) = self.b.m.types.kind(rty).clone() else {
            return Err(Error::new("stringify returns a Result"));
        };
        let err = self.b.m.alts[ra.index()]
            .cases
            .iter()
            .position(|c| c.name == "error")
            .ok_or_else(|| Error::new("not a Result"))?;
        let out = self.two_ways(
            has_form,
            rty,
            &mut |s| {
                let slot = s.jslot(MTy::STR);
                let code = s.status_code("msrt_json_w_finish", &[writer, slot])?;
                Ok(Some(
                    s.status_result(
                        "msrt_json_w_finish",
                        code,
                        Some((slot, MTy::STR)),
                        None,
                        rty,
                    )?
                    .v,
                ))
            },
            &mut |s| Ok(Some(s.json_error(ra, err, "InvalidData")?)),
        )?;
        let writer = self.b.use_var(wvar);
        self.drop_value(writer);
        Ok(out)
    }
}

fn null_cmp(fl: &mut FnLower<'_>, kind: Value, null: Value) -> Value {
    fl.b.icmp(Cc::Eq, kind, null)
}

fn jfields(params: &[ct::Param]) -> Vec<JField> {
    params
        .iter()
        .map(|p| JField {
            name: p.name.to_string(),
            ty: p.ty.clone(),
        })
        .collect()
}

/// An alternative whose cases all lack payload.
/// An alternative a member name can select: some case has no payload.
fn jkey_alt(t: &ct::Ty) -> bool {
    t.kind == ct::Kind::Alternative
        && !t.is_std("Optional")
        && ct::cases(t).iter().any(|c| c.fields.is_empty())
}

fn jplain_alt(t: &ct::Ty) -> bool {
    t.kind == ct::Kind::Alternative
        && !t.is_std("Optional")
        && !ct::cases(t).is_empty()
        && ct::cases(t).iter().all(|c| c.fields.is_empty())
}
