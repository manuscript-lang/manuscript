//! C ABI shims for `@std/json.ms` (`msrt_json_*`).
//!
//! `JsonValue` has no flat layout, so values cross the boundary as a refcounted document handle
//! ([`DocObj`]) plus `u32` node ids. A parse yields a document the generated decoders read with the
//! accessors; an encoder starts a `builder_new` document, adds nodes bottom-up and serializes the
//! root. Node ids are only valid for the document that issued them.
use crate::{Doc, Limits, Node, Writer};
use alloc::string::String;
use alloc::vec::Vec;
use ms_rt::ffi::{Fail, ObjMut, ObjRef, Object, Out, Status, abi_handle, native};
use ms_rt::tree::{TreeBuilder, TreeCtor, ValueDesc, ValueOut};

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

native! {
    /// Writes the document handle and the root node id through `out` and `root` on success.
    fn msrt_json_parse(
        text: &str,
        has_max_bytes: bool,
        max_bytes: i64,
        has_max_depth: bool,
        max_depth: i64,
        has_max_values: bool,
        max_values: i64,
        out: Out<Object<Doc>>,
        root: Out<u32>,
    ) -> Result<(), Fail> {
        let limits = Limits {
            max_bytes: has_max_bytes.then_some(max_bytes),
            max_depth: has_max_depth.then_some(max_depth),
            max_values: has_max_values.then_some(max_values),
        };
        let (d, id) = crate::parse(text, limits)?;
        out.write(Object(d));
        root.write(id);
        Ok(())
    }

    /// Parses `text` straight into a value of the alternative described by `desc`, built by `ctor`
    /// (see `ms_rt::tree`), written to `out` on success.
    fn msrt_json_parse_tree(
        text: &str,
        has_max_bytes: bool,
        max_bytes: i64,
        has_max_depth: bool,
        max_depth: i64,
        has_max_values: bool,
        max_values: i64,
        desc: ValueDesc,
        ctor: TreeCtor,
        out: ValueOut,
    ) -> Result<(), Fail> {
        let limits = Limits {
            max_bytes: has_max_bytes.then_some(max_bytes),
            max_depth: has_max_depth.then_some(max_depth),
            max_values: has_max_values.then_some(max_values),
        };
        let mut b = TreeBuilder::new(desc, ctor, 64);
        crate::parse_tree(text, limits, &mut b)?;
        b.finish(out);
        Ok(())
    }

    fn msrt_json_kind(d: ObjRef<Doc>, id: u32) -> u8 {
        match &d.nodes[id as usize] {
            Node::Null => KIND_NULL,
            Node::Bool(_) => KIND_BOOL,
            Node::Num(_) | Node::RawNum(_) => KIND_NUMBER,
            Node::Str(_) => KIND_STRING,
            Node::Arr { .. } | Node::ArrB(_) => KIND_ARRAY,
            Node::Obj { .. } | Node::ObjB(_) => KIND_OBJECT,
        }
    }

    fn msrt_json_bool(d: ObjRef<Doc>, id: u32) -> bool {
        matches!(d.nodes[id as usize], Node::Bool(true))
    }

    fn msrt_json_text(d: ObjRef<'_, Doc>, id: u32) -> &str {
        d.0.text_of(id)
    }

    fn msrt_json_len(d: ObjRef<Doc>, id: u32) -> i64 {
        match &d.nodes[id as usize] {
            Node::Arr { len, .. } | Node::Obj { len, .. } => i64::from(*len),
            Node::ArrB(_) => d.items(id).len() as i64,
            Node::ObjB(_) => d.members(id).len() as i64,
            _ => 0,
        }
    }

    /// `i` is below `msrt_json_len`.
    fn msrt_json_item(d: ObjRef<Doc>, id: u32, i: i64) -> u32 {
        match &d.nodes[id as usize] {
            Node::Arr { .. } | Node::ArrB(_) => d.items(id)[i as usize],
            Node::Obj { .. } | Node::ObjB(_) => d.members(id)[i as usize].val,
            _ => 0,
        }
    }

    fn msrt_json_key(d: ObjRef<'_, Doc>, id: u32, i: i64) -> &str {
        match d.0.members(id).get(i as usize) {
            Some(m) => d.0.slice(m.key),
            None => "",
        }
    }

    fn msrt_json_dec_int(text: &str) -> Result<i64, NotNumber> {
        crate::parse_int(text).ok_or(NotNumber)
    }

    fn msrt_json_dec_float(text: &str) -> Result<f64, NotNumber> {
        crate::parse_float(text).ok_or(NotNumber)
    }

    fn msrt_json_writer_new(
        has_max_bytes: bool,
        max_bytes: i64,
        has_indent: bool,
        indent: i64,
    ) -> Object<Writer> {
        Object(Writer::new(
            has_max_bytes.then_some(max_bytes),
            has_indent.then_some(indent),
        ))
    }

    fn msrt_json_w_item(w: ObjMut<Writer>) -> () {
        w.0.item();
    }

    fn msrt_json_w_key(w: ObjMut<Writer>, key: &str) -> () {
        w.0.key(key);
    }

    fn msrt_json_w_undo(w: ObjMut<Writer>) -> () {
        w.0.undo();
    }

    fn msrt_json_w_begin_array(w: ObjMut<Writer>) -> () {
        w.0.begin_array();
    }

    fn msrt_json_w_end_array(w: ObjMut<Writer>) -> () {
        w.0.end_array();
    }

    fn msrt_json_w_begin_object(w: ObjMut<Writer>) -> () {
        w.0.begin_object();
    }

    fn msrt_json_w_end_object(w: ObjMut<Writer>) -> () {
        w.0.end_object();
    }

    fn msrt_json_w_null(w: ObjMut<Writer>) -> () {
        w.0.null();
    }

    fn msrt_json_w_bool(w: ObjMut<Writer>, v: bool) -> () {
        w.0.boolean(v);
    }

    fn msrt_json_w_int(w: ObjMut<Writer>, v: i64) -> () {
        w.0.int(v);
    }

    fn msrt_json_w_float(w: ObjMut<Writer>, v: f64) -> () {
        w.0.float(v);
    }

    fn msrt_json_w_number(w: ObjMut<Writer>, text: &str) -> () {
        w.0.number(text);
    }

    fn msrt_json_w_string(w: ObjMut<Writer>, text: &str) -> () {
        w.0.string(text);
    }

    fn msrt_json_w_finish(w: ObjMut<Writer>) -> Result<String, Fail> {
        w.0.finish()
    }

    fn msrt_json_find(d: ObjRef<Doc>, id: u32, key: &str) -> i64 {
        d.members(id)
            .iter()
            .position(|m| d.slice(m.key) == key)
            .map_or(-1, |i| i as i64)
    }

    fn msrt_json_has_unknown(d: ObjRef<Doc>, id: u32, names: Vec<&str>) -> bool {
        d.members(id)
            .iter()
            .any(|m| !names.contains(&d.slice(m.key)))
    }

    /// Index of the variant name in `names` (-1 when unknown); `payload` is the payload node
    /// (-1 for a bare name) and is written only for a string or single-key object.
    fn msrt_json_variant(d: ObjRef<Doc>, id: u32, names: Vec<&str>, payload: Out<i64>) -> i64 {
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
                msrt_json_parse(&text, 0, 0, 0, 0, 0, 0, d.as_mut_ptr(), &mut root),
                STATUS_OK
            );
            let d = d.assume_init();
            assert_eq!(msrt_json_kind(d, root), KIND_OBJECT);
            assert_eq!(msrt_json_len(d, root), 2);
            let a = msrt_json_item(d, root, 0);
            assert_eq!(msrt_json_len(d, a), 3);
            ms_rt::obj::msrt_release(d.cast());
            ms_rt::ffi::str_release(&text);
        }
    }
}
