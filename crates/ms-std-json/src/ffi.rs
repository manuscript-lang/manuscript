//! C ABI shims for `@std/json.ms` (`msrt_json_*`).
//!
//! `JsonValue` has no flat layout, so values cross the boundary as a refcounted document handle
//! ([`DocObj`]) plus `u32` node ids. A parse yields a document the generated decoders read with the
//! accessors; an encoder starts a `builder_new` document, adds nodes bottom-up and serializes the
//! root. Node ids are only valid for the document that issued them.
use crate::{Doc, Limits, Node, NodeId};
use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::{
    Fail, IdArray, ObjMut, ObjRef, Object, Out, Status, StrArray, abi_handle, native,
};

abi_handle!(Doc);

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

fn put(entries: &mut Vec<(String, NodeId)>, key: &str, id: NodeId) {
    match entries.iter_mut().find(|e| e.0 == key) {
        Some(e) => e.1 = id,
        None => entries.push((String::from(key), id)),
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

    fn msrt_json_kind(d: ObjRef<Doc>, id: u32) -> u8 {
        match &d.nodes[id as usize] {
            Node::Null => KIND_NULL,
            Node::Bool(_) => KIND_BOOL,
            Node::Number(_) => KIND_NUMBER,
            Node::Str(_) => KIND_STRING,
            Node::Array(_) => KIND_ARRAY,
            Node::Object(_) => KIND_OBJECT,
        }
    }

    fn msrt_json_bool(d: ObjRef<Doc>, id: u32) -> bool {
        matches!(d.nodes[id as usize], Node::Bool(true))
    }

    fn msrt_json_text(d: ObjRef<'_, Doc>, id: u32) -> &str {
        match &d.0.nodes[id as usize] {
            Node::Number(s) | Node::Str(s) => s,
            _ => "",
        }
    }

    fn msrt_json_len(d: ObjRef<Doc>, id: u32) -> i64 {
        match &d.nodes[id as usize] {
            Node::Array(v) => v.len() as i64,
            Node::Object(v) => v.len() as i64,
            _ => 0,
        }
    }

    /// `i` is below `msrt_json_len`.
    fn msrt_json_item(d: ObjRef<Doc>, id: u32, i: i64) -> u32 {
        match &d.nodes[id as usize] {
            Node::Array(v) => v[i as usize],
            Node::Object(v) => v[i as usize].1,
            _ => 0,
        }
    }

    fn msrt_json_key(d: ObjRef<'_, Doc>, id: u32, i: i64) -> &str {
        match &d.0.nodes[id as usize] {
            Node::Object(v) => &v[i as usize].0,
            _ => "",
        }
    }

    fn msrt_json_builder_new() -> Object<Doc> {
        Object(Doc::default())
    }

    fn msrt_json_add_null(d: ObjMut<Doc>) -> u32 {
        d.0.add(Node::Null)
    }

    fn msrt_json_add_bool(d: ObjMut<Doc>, v: bool) -> u32 {
        d.0.add(Node::Bool(v))
    }

    fn msrt_json_add_number(d: ObjMut<Doc>, text: &str) -> u32 {
        d.0.add(Node::Number(String::from(text)))
    }

    fn msrt_json_add_string(d: ObjMut<Doc>, text: &str) -> u32 {
        d.0.add(Node::Str(String::from(text)))
    }

    fn msrt_json_add_array(d: ObjMut<Doc>, ids: IdArray, n: i64) -> u32 {
        d.0.add(Node::Array(ids.get(n)))
    }

    fn msrt_json_add_object(d: ObjMut<Doc>, keys: StrArray, ids: IdArray, n: i64) -> u32 {
        let mut entries = Vec::new();
        for (k, id) in keys.get(n).into_iter().zip(ids.get(n)) {
            put(&mut entries, k, id);
        }
        d.0.add(Node::Object(entries))
    }

    fn msrt_json_stringify(
        d: ObjRef<Doc>,
        root: u32,
        has_max_bytes: bool,
        max_bytes: i64,
        has_indent: bool,
        indent: i64,
    ) -> Result<String, Fail> {
        d.stringify(
            root,
            has_max_bytes.then_some(max_bytes),
            has_indent.then_some(indent),
        )
    }

    fn msrt_json_dec_int(text: &str) -> Result<i64, NotNumber> {
        crate::parse_int(text).ok_or(NotNumber)
    }

    fn msrt_json_dec_float(text: &str) -> Result<f64, NotNumber> {
        crate::parse_float(text).ok_or(NotNumber)
    }

    fn msrt_json_add_float(d: ObjMut<Doc>, v: f64) -> u32 {
        match crate::float_text(v) {
            Some(text) => d.0.add(Node::Number(text)),
            None => d.0.add(Node::Null),
        }
    }

    fn msrt_json_add_empty_array(d: ObjMut<Doc>) -> u32 {
        d.0.add(Node::Array(Vec::new()))
    }

    fn msrt_json_array_push(d: ObjMut<Doc>, arr: u32, item: u32) -> () {
        if let Node::Array(v) = &mut d.0.nodes[arr as usize] {
            v.push(item);
        }
    }

    fn msrt_json_add_empty_object(d: ObjMut<Doc>) -> u32 {
        d.0.add(Node::Object(Vec::new()))
    }

    fn msrt_json_object_put(d: ObjMut<Doc>, obj: u32, key: &str, item: u32) -> () {
        if let Node::Object(v) = &mut d.0.nodes[obj as usize] {
            put(v, key, item);
        }
    }

    fn msrt_json_find(d: ObjRef<Doc>, id: u32, key: &str) -> i64 {
        match &d.nodes[id as usize] {
            Node::Object(v) => v.iter().position(|e| e.0 == key).map_or(-1, |i| i as i64),
            _ => -1,
        }
    }

    fn msrt_json_has_unknown(d: ObjRef<Doc>, id: u32, names: Vec<&str>) -> bool {
        match &d.nodes[id as usize] {
            Node::Object(v) => v.iter().any(|e| !names.contains(&e.0.as_str())),
            _ => false,
        }
    }

    /// Index of the variant name in `names` (-1 when unknown); `payload` is the payload node
    /// (-1 for a bare name) and is written only for a string or single-key object.
    fn msrt_json_variant(d: ObjRef<Doc>, id: u32, names: Vec<&str>, payload: Out<i64>) -> i64 {
        let index = |name: &str| names.iter().position(|k| *k == name).map_or(-1, |i| i as i64);
        match &d.nodes[id as usize] {
            Node::Str(s) => {
                payload.write(-1);
                index(s)
            }
            Node::Object(v) if v.len() == 1 => {
                payload.write(i64::from(v[0].1));
                index(&v[0].0)
            }
            _ => -1,
        }
    }

    /// Null when the float has no JSON form.
    fn msrt_json_enc_float(v: f64) -> Option<String> {
        crate::float_text(v)
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _;
    use ms_rt_abi::{STATUS_OK, StrObj};
    use ms_std_core::{ObjCell, new_string, str_ref};

    #[test]
    fn roundtrip() {
        let text = new_string(r#"{"a":[1,"x",null],"b":true}"#);
        let mut d = MaybeUninit::<*mut ObjCell<Doc>>::uninit();
        let mut root = 0u32;
        let mut s = MaybeUninit::<*mut StrObj>::uninit();
        // SAFETY: all pointers are live; results are released below.
        unsafe {
            assert_eq!(
                msrt_json_parse(text, 0, 0, 0, 0, 0, 0, d.as_mut_ptr(), &mut root),
                STATUS_OK
            );
            let d = d.assume_init();
            assert_eq!(msrt_json_kind(d, root), KIND_OBJECT);
            assert_eq!(msrt_json_len(d, root), 2);
            let a = msrt_json_item(d, root, 0);
            assert_eq!(msrt_json_len(d, a), 3);
            assert_eq!(
                msrt_json_stringify(d, root, 0, 0, 1, 2, s.as_mut_ptr()),
                STATUS_OK
            );
            assert!(str_ref(s.assume_init()).starts_with("{\n  \"a\": [\n    1,"));
            ms_rt::obj::msrt_release(s.assume_init().cast());
            ms_rt::obj::msrt_release(d.cast());
            ms_rt::obj::msrt_release(text.cast());
        }
    }
}
