//! `FileSystem.stat` and `FileHandle.stat`: the runtime fills a flat word record
//! (`InfoOut` in `ms-std-fs`) and this module builds the `FileInfo` record from it.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_mir::ir::{Cc, Imm, Op, Value};
use ms_mir::types::{AltId, RecId, Ty as MTy, TyKind};

/// `InfoOut` word order after the leading name. The producer in `ms-std-fs` writes the same.
const WORDS: [&str; 21] = [
    "size",
    "mode",
    "permissions",
    "modified_seconds",
    "modified_nanos",
    "accessed_seconds",
    "accessed_nanos",
    "changed_seconds",
    "changed_nanos",
    "created_seconds",
    "created_nanos",
    "created_present",
    "kinds",
    "block_size",
    "blocks",
    "rdev",
    "device",
    "inode",
    "links",
    "uid",
    "gid",
];

/// `FileInfo` flags and the `KIND_*` bit of `InfoOut.kinds` each reads.
const KINDS: [(&str, i64); 7] = [
    ("directory", 1),
    ("symlink", 2),
    ("regular", 4),
    ("fifo", 8),
    ("socket", 16),
    ("block_device", 32),
    ("char_device", 64),
];

/// Entries of `FileInfo.exact` backed by an unsigned host counter, in `InfoOut` order.
const COUNTERS: [&str; 8] = [
    "device",
    "inode",
    "links",
    "uid",
    "gid",
    "block_size",
    "blocks",
    "rdev",
];

/// `FileInfo.exact` entries holding nanoseconds since the epoch, with their `InfoOut` prefix.
const TIMES: [(&str, &str); 4] = [
    ("accessed_ns", "accessed"),
    ("modified_ns", "modified"),
    ("changed_ns", "changed"),
    ("created_ns", "created"),
];

impl FnLower<'_> {
    /// The record the runtime writes `InfoOut` as: the name and one `Int` per word.
    fn info_raw(&mut self) -> (RecId, MTy) {
        let key = "native:FsInfoRaw";
        if let Some(t) = self.cx.tycache.get(key).copied()
            && let TyKind::Rec(r) = self.b.m.types.kind(t)
        {
            return (*r, t);
        }
        let mut fields = vec![("name".to_string(), MTy::STR)];
        fields.extend(WORDS.iter().map(|w| (w.to_string(), MTy::INT)));
        let (id, ty) = self.b.m.add_record("FsInfoRaw", fields);
        self.cx.tycache.insert(key.to_string(), ty);
        (id, ty)
    }

    /// `Result[FileInfo, E]` from a runtime call that fills `InfoOut` through the last argument.
    pub(crate) fn finish_stat(
        &mut self,
        sym: &str,
        mut vals: Vec<Value>,
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new(format!("{sym}: stat needs a Result")));
        };
        let (raw_id, raw_ty) = self.info_raw();
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(raw_ty), Some(MTy::PTR))
            .expect("slot");
        vals.push(slot);
        let status = self.call_runtime(sym, &vals, MTy::BOOL)?;
        let code = self
            .b
            .emit(Op::B2I, &[status], Imm::None, Some(MTy::INT))
            .expect("b2i");
        let zero = self.b.iconst(0);
        let good = self.b.icmp(Cc::Eq, code, zero);
        let ok = self.ok_case_index(a)?;
        self.two_ways(
            good,
            result,
            &mut |s| {
                let raw =
                    s.b.emit(Op::Take, &[slot], Imm::Ty(raw_ty), Some(raw_ty))
                        .expect("take");
                let info = s.file_info(a, ok, raw_id, raw)?;
                s.b.emit(Op::Drop, &[raw], Imm::None, None);
                Ok(Some(s.b.alt_new(a, ok as u32, &[info])))
            },
            &mut |s| s.status_failure(result, code, sym).map(Some),
        )
    }

    /// The owned `FileInfo` for the borrowed raw record.
    fn file_info(
        &mut self,
        a: AltId,
        ok: usize,
        raw_id: RecId,
        raw: Value,
    ) -> Result<Value, Error> {
        let info_ty = self.b.m.alts[a.index()].cases[ok].fields[0].1;
        let TyKind::Rec(info_id) = self.b.m.types.kind(info_ty).clone() else {
            return Err(Error::new("stat does not produce a record"));
        };
        let fields = self.b.m.records[info_id.index()].fields.clone();
        let word = |s: &mut Self, name: &str| -> Value {
            let at = WORDS
                .iter()
                .position(|w| *w == name)
                .expect("known InfoOut word") as u32;
            s.b.rec_get(raw_id, at + 1, raw)
        };
        let mut values = Vec::new();
        for (name, ty) in &fields {
            let v = match name.as_str() {
                "name" => {
                    let n = self.b.rec_get(raw_id, 0, raw);
                    self.b
                        .emit(Op::Copy, &[n], Imm::None, Some(MTy::STR))
                        .expect("copy")
                }
                "directory" | "symlink" | "regular" | "fifo" | "socket" | "block_device"
                | "char_device" => {
                    let bit = KINDS
                        .iter()
                        .find(|(n, _)| *n == name)
                        .map(|(_, b)| *b)
                        .expect("kind bit");
                    let kinds = word(self, "kinds");
                    let mask = self.b.iconst(bit);
                    let hit = self.b.binop(Op::And, kinds, mask);
                    let zero = self.b.iconst(0);
                    self.b.icmp(Cc::Ne, hit, zero)
                }
                "modified" | "accessed" | "changed" => self.timestamp(raw_id, raw, *ty, name)?,
                "created" => self.created(raw_id, raw, *ty)?,
                "exact" => self.exact(raw_id, raw, *ty)?,
                other => word(self, other),
            };
            values.push(v);
        }
        Ok(self.b.rec_new(info_id, &values))
    }

    /// The `Timestamp` of the `<prefix>_seconds` and `<prefix>_nanos` words.
    fn timestamp(
        &mut self,
        raw_id: RecId,
        raw: Value,
        ty: MTy,
        prefix: &str,
    ) -> Result<Value, Error> {
        let TyKind::Rec(ts) = self.b.m.types.kind(ty).clone() else {
            return Err(Error::new("a timestamp field is not a record"));
        };
        let at = |s: &mut Self, suffix: &str| {
            let name = format!("{prefix}_{suffix}");
            let i = WORDS.iter().position(|w| *w == name).expect("time word") as u32;
            s.b.rec_get(raw_id, i + 1, raw)
        };
        let (secs, nanos) = (at(self, "seconds"), at(self, "nanos"));
        Ok(self.b.rec_new(ts, &[secs, nanos]))
    }

    /// `Timestamp?`: present when the host recorded a creation time.
    fn created(&mut self, raw_id: RecId, raw: Value, ty: MTy) -> Result<Value, Error> {
        let TyKind::Opt(inner) = self.b.m.types.kind(ty).clone() else {
            return Err(Error::new("`created` is not an optional"));
        };
        let at = WORDS
            .iter()
            .position(|w| *w == "created_present")
            .expect("word") as u32;
        let flag = self.b.rec_get(raw_id, at + 1, raw);
        let zero = self.b.iconst(0);
        let present = self.b.icmp(Cc::Ne, flag, zero);
        let made = self.two_ways(
            present,
            ty,
            &mut |s| {
                let t = s.timestamp(raw_id, raw, inner, "created")?;
                Ok(Some(s.b.opt_some(t)))
            },
            &mut |s| Ok(Some(s.none_owned(ty))),
        )?;
        Ok(made.v)
    }

    /// `exact`: unbounded copies of the numeric fields and the times in nanoseconds.
    fn exact(&mut self, raw_id: RecId, raw: Value, ty: MTy) -> Result<Value, Error> {
        let TyKind::Obj(_, args) = self.b.m.types.kind(ty).clone() else {
            return Err(Error::new("`exact` is not a map"));
        };
        let big = args[1];
        let at = |name: &str| WORDS.iter().position(|w| *w == name).expect("word") as u32 + 1;
        let mut map = self.map_new(ty)?;
        let mut entries: Vec<(&str, Value)> = Vec::new();
        for name in ["size", "mode"] {
            let n = self.b.rec_get(raw_id, at(name), raw);
            entries.push((name, self.call_runtime("msstd_bigint_from_int", &[n], big)?));
        }
        for name in COUNTERS {
            let n = self.b.rec_get(raw_id, at(name), raw);
            entries.push((name, self.call_runtime("msstd_bigint_from_u64", &[n], big)?));
        }
        for (key, prefix) in TIMES {
            let s = self
                .b
                .rec_get(raw_id, at(&format!("{prefix}_seconds")), raw);
            let n = self.b.rec_get(raw_id, at(&format!("{prefix}_nanos")), raw);
            let v = self.call_runtime("msstd_bigint_from_seconds_nanos", &[s, n], big)?;
            entries.push((key, v));
        }
        for (key, value) in entries {
            let lit = self.b.str_lit(key);
            let key = self
                .b
                .emit(Op::Copy, &[lit], Imm::None, Some(MTy::STR))
                .expect("copy");
            map = self.map_insert(map, key, value)?;
        }
        Ok(map)
    }
}
