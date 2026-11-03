//! C ABI shims for `@std/data/json.ms` (`msstd_json_*`).
//!
//! `JsonValue` has no flat layout, so values cross the boundary as an owned document handle
//! ([`DocObj`]) plus `u32` node ids. A parse yields a document the generated decoders read with the
//! accessors; an encoder starts a `builder_new` document, adds nodes bottom-up and serializes the
//! root. Node ids are only valid for the document that issued them.
use crate::{Doc, Limits, Node, Writer};
use alloc::string::{String, ToString};
use alloc::vec::Vec;
use ms_rt::ffi::{
    ErrOut, Fail, Has, ObjMut, ObjRef, Object, Out, Status, StatusCode, abi_handle, native,
};
use ms_rt::tree::{
    ListRef, MapRef, SinkObj, TreeBuilder, TreeCtor, TreeSink, TreeView, ValueDesc, ValueOut,
    ValueRef, WalkRef,
};

abi_handle!(Doc);
abi_handle!(Writer);

pub const KIND_NULL: u8 = 0;
pub const KIND_BOOL: u8 = 1;
pub const KIND_NUMBER: u8 = 2;
pub const KIND_STRING: u8 = 3;
pub const KIND_ARRAY: u8 = 4;
pub const KIND_OBJECT: u8 = 5;

/// A decimal text that is not an in-range number: status 1.
pub struct NotNumber;

impl Status for NotNumber {
    fn status(self) -> u8 {
        1
    }
}

/// The status of a failed parse; a syntax error also says where it stopped, in `err`.
fn located(fail: Fail, text: &str, at: crate::Where, err: &ErrOut) -> StatusCode {
    if fail == Fail::InvalidData {
        err.set(&crate::explain(text, at));
    }
    StatusCode(fail.status())
}

native! {
    /// Writes the document handle and the root node id through `out` and `root` on success.
    // ms: leaf
    fn msstd_json_parse(
        text: &str,
        has_max_bytes: Has,
        max_bytes: i64,
        has_max_depth: Has,
        max_depth: i64,
        has_max_values: Has,
        max_values: i64,
        out: Out<Object<Doc>>,
        root: Out<u32>;
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let limits = Limits {
            max_bytes: has_max_bytes.then_some(max_bytes),
            max_depth: has_max_depth.then_some(max_depth),
            max_values: has_max_values.then_some(max_values),
        };
        let (d, id) = crate::parse_located(text, limits).map_err(|(f, at)| located(f, text, at, &err))?;
        out.write(Object(d));
        root.write(id);
        Ok(())
    }

    /// Parses `text` straight into a value of the alternative described by `desc`, built by `ctor`
    /// (see `ms_rt::tree`), written to `out` on success.
    // ms: leaf
    fn msstd_json_parse_tree(
        text: &str,
        has_max_bytes: Has,
        max_bytes: i64,
        has_max_depth: Has,
        max_depth: i64,
        has_max_values: Has,
        max_values: i64,
        desc: ValueDesc,
        ctor: TreeCtor,
        out: ValueOut;
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let limits = Limits {
            max_bytes: has_max_bytes.then_some(max_bytes),
            max_depth: has_max_depth.then_some(max_depth),
            max_values: has_max_values.then_some(max_values),
        };
        let mut b = TreeBuilder::new(desc, ctor, 64);
        crate::parse_tree_located(text, limits, &mut b)
            .map_err(|(f, at)| located(f, text, at, &err))?;
        b.finish(out);
        Ok(())
    }

    // ms: leaf
    fn msstd_json_kind(d: ObjRef<Doc>, id: u32) -> u8 {
        match &d.nodes[id as usize] {
            Node::Null => KIND_NULL,
            Node::Bool(_) => KIND_BOOL,
            Node::Num(_) | Node::RawNum(_) => KIND_NUMBER,
            Node::Str(_) => KIND_STRING,
            Node::Arr { .. } | Node::ArrB(_) => KIND_ARRAY,
            Node::Obj { .. } | Node::ObjB(_) => KIND_OBJECT,
        }
    }

    // ms: leaf
    fn msstd_json_bool(d: ObjRef<Doc>, id: u32) -> bool {
        matches!(d.nodes[id as usize], Node::Bool(true))
    }

    // ms: leaf
    fn msstd_json_text(d: ObjRef<'_, Doc>, id: u32) -> &str {
        d.0.text_of(id)
    }

    // ms: leaf
    fn msstd_json_len(d: ObjRef<Doc>, id: u32) -> i64 {
        match &d.nodes[id as usize] {
            Node::Arr { len, .. } | Node::Obj { len, .. } => i64::from(*len),
            Node::ArrB(_) => d.items(id).len() as i64,
            Node::ObjB(_) => d.members(id).len() as i64,
            _ => 0,
        }
    }

    /// `i` is below `msstd_json_len`.
    // ms: leaf
    fn msstd_json_item(d: ObjRef<Doc>, id: u32, i: i64) -> u32 {
        match &d.nodes[id as usize] {
            Node::Arr { .. } | Node::ArrB(_) => d.items(id)[i as usize],
            Node::Obj { .. } | Node::ObjB(_) => d.members(id)[i as usize].val,
            _ => 0,
        }
    }

    // ms: leaf
    fn msstd_json_key(d: ObjRef<'_, Doc>, id: u32, i: i64) -> &str {
        match d.0.members(id).get(i as usize) {
            Some(m) => d.0.slice(m.key),
            None => "",
        }
    }

    // ms: leaf
    fn msstd_json_dec_int(text: &str) -> Result<i64, NotNumber> {
        crate::parse_int(text).ok_or(NotNumber)
    }

    /// An integer in `lo..=hi`, for the sized signed and narrower unsigned types.
    // ms: leaf
    fn msstd_json_dec_int_in(text: &str, lo: i64, hi: i64) -> Result<i64, NotNumber> {
        crate::parse_int(text)
            .filter(|v| (lo..=hi).contains(v))
            .ok_or(NotNumber)
    }

    /// A `UInt64` as its bit pattern.
    // ms: leaf
    fn msstd_json_dec_uint(text: &str) -> Result<i64, NotNumber> {
        text.parse::<u64>().map(|v| v as i64).map_err(|_| NotNumber)
    }

    /// A `Float32` value as the `f64` holding it; a finite number too large for `f32` is not a number.
    // ms: leaf
    fn msstd_json_dec_float32(text: &str) -> Result<f64, NotNumber> {
        let v: f32 = text.parse().map_err(|_| NotNumber)?;
        if v.is_finite() { Ok(f64::from(v)) } else { Err(NotNumber) }
    }

    // ms: leaf
    fn msstd_json_dec_float(text: &str) -> Result<f64, NotNumber> {
        crate::parse_float(text).ok_or(NotNumber)
    }

    // ms: leaf
    fn msstd_json_writer_new(
        has_max_bytes: Has,
        max_bytes: i64,
        has_indent: Has,
        indent: i64,
    ) -> Object<Writer> {
        Object(Writer::new(
            has_max_bytes.then_some(max_bytes),
            has_indent.then_some(indent),
        ))
    }

    // ms: leaf
    fn msstd_json_w_item(w: ObjMut<Writer>) -> () {
        w.0.item();
    }

    // ms: leaf
    fn msstd_json_w_key(w: ObjMut<Writer>, key: &str) -> () {
        w.0.key(key);
    }

    // ms: leaf
    fn msstd_json_w_key_quoted(w: ObjMut<Writer>, quoted_name: &str) -> () {
        w.0.key_quoted(quoted_name);
    }

    // ms: leaf
    fn msstd_json_w_undo(w: ObjMut<Writer>) -> () {
        w.0.undo();
    }

    // ms: leaf
    fn msstd_json_w_begin_array(w: ObjMut<Writer>) -> () {
        w.0.begin_array();
    }

    // ms: leaf
    fn msstd_json_w_end_array(w: ObjMut<Writer>) -> () {
        w.0.end_array();
    }

    // ms: leaf
    fn msstd_json_w_begin_object(w: ObjMut<Writer>) -> () {
        w.0.begin_object();
    }

    // ms: leaf
    fn msstd_json_w_end_object(w: ObjMut<Writer>) -> () {
        w.0.end_object();
    }

    // ms: leaf
    fn msstd_json_w_no_form(w: ObjMut<Writer>) -> () {
        w.0.lost = true;
    }

    // ms: leaf
    fn msstd_json_w_lost(w: ObjRef<Writer>) -> bool {
        w.lost
    }

    // ms: leaf
    fn msstd_json_w_null(w: ObjMut<Writer>) -> () {
        w.0.null();
    }

    // ms: leaf
    fn msstd_json_w_bool(w: ObjMut<Writer>, v: bool) -> () {
        w.0.boolean(v);
    }

    // ms: leaf
    fn msstd_json_w_int(w: ObjMut<Writer>, v: i64) -> () {
        w.0.int(v);
    }

    /// A `UInt64` given as its bit pattern.
    // ms: leaf
    fn msstd_json_w_uint(w: ObjMut<Writer>, v: i64) -> () {
        w.0.number(&(v as u64).to_string());
    }

    /// A `Float32` held in an `f64`, written as the shortest decimal that reads back as that `f32`.
    // ms: leaf
    fn msstd_json_w_float32(w: ObjMut<Writer>, v: f64) -> () {
        match (v as f32).to_string().parse::<f64>() {
            Ok(short) if v.is_finite() => w.0.float(short),
            _ => w.0.float(v),
        }
    }

    // ms: leaf
    fn msstd_json_w_float(w: ObjMut<Writer>, v: f64) -> () {
        w.0.float(v);
    }

    // ms: leaf
    fn msstd_json_w_number(w: ObjMut<Writer>, text: &str) -> () {
        w.0.number(text);
    }

    // ms: leaf
    fn msstd_json_w_string(w: ObjMut<Writer>, text: &str) -> () {
        w.0.string(text);
    }

    /// Writes the tree of the alternative described by `desc` that `root` holds, read through
    /// `view` (see `ms_rt::tree`), as the next value.
    // ms: leaf
    fn msstd_json_w_tree(
        w: SinkObj<Writer>,
        desc: ValueDesc,
        view: TreeView,
        root: ValueRef,
    ) -> () {
        w.walk(desc, view, root);
    }

    /// The view thunk's call for an array: opens it and queues its elements.
    // ms: leaf
    fn msstd_json_tree_array(walk: WalkRef<Writer>, list: ListRef) -> () {
        walk.0.array(list.0);
    }

    /// The view thunk's call for an object: opens it and queues its members.
    // ms: leaf
    fn msstd_json_tree_object(walk: WalkRef<Writer>, map: MapRef) -> () {
        walk.0.object(map.0);
    }

    // ms: leaf
    fn msstd_json_w_finish(w: ObjMut<Writer>) -> Result<String, Fail> {
        w.0.finish()
    }

    // ms: leaf
    fn msstd_json_find(d: ObjRef<Doc>, id: u32, key: &str) -> i64 {
        d.members(id)
            .iter()
            .position(|m| d.slice(m.key) == key)
            .map_or(-1, |i| i as i64)
    }

    // ms: leaf
    fn msstd_json_has_unknown(d: ObjRef<Doc>, id: u32, names: Vec<&str>) -> bool {
        d.members(id)
            .iter()
            .any(|m| !names.contains(&d.slice(m.key)))
    }

    /// Index of the variant name in `names` (-1 when unknown); `payload` is the payload node
    /// (-1 for a bare name) and is written only for a string or single-key object.
    // ms: leaf
    fn msstd_json_variant(d: ObjRef<Doc>, id: u32, names: Vec<&str>, payload: Out<i64>) -> i64 {
        let index = |name: &str| names.iter().position(|k| *k == name).map_or(-1, |i| i as i64);
        match (&d.nodes[id as usize], d.members(id)) {
            (Node::Str(s), _) => {
                payload.write(-1);
                index(d.slice(*s))
            }
            (_, [m]) => {
                payload.write(i64::from(m.val));
                index(d.slice(m.key))
            }
            _ => -1,
        }
    }
}

impl TreeSink for Writer {
    fn item(&mut self) {
        Writer::item(self);
    }
    fn key(&mut self, name: &str) {
        Writer::key_walked(self, name);
    }
    fn begin_array(&mut self) {
        Writer::begin_array(self);
    }
    fn end_array(&mut self) {
        Writer::end_array(self);
    }
    fn begin_object(&mut self) {
        Writer::begin_object(self);
    }
    fn end_object(&mut self) {
        Writer::end_object(self);
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _;
    use ms_rt::ffi::{ObjCell, new_string};
    use ms_rt_abi::STATUS_OK;

    #[test]
    fn roundtrip() {
        let text = new_string(r#"{"a":[1,"x",null],"b":true}"#);
        let mut d = MaybeUninit::<*mut ObjCell<Doc>>::uninit();
        let mut root = 0u32;
        // SAFETY: all pointers are live; results are released below.
        unsafe {
            assert_eq!(
                msstd_json_parse(
                    &text,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(0),
                    0,
                    d.as_mut_ptr(),
                    &mut root,
                    ms_rt_abi::ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OK
            );
            let d = d.assume_init();
            assert_eq!(msstd_json_kind(d, root), KIND_OBJECT);
            assert_eq!(msstd_json_len(d, root), 2);
            let a = msstd_json_item(d, root, 0);
            assert_eq!(msstd_json_len(d, a), 3);
            ms_rt::obj::msrt_obj_drop(d.cast());
            ms_rt::ffi::str_release(&text);
        }
    }
}
