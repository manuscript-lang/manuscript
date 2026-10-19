//! C ABI shims for `@std/json.ms` (`msrt_json_*`).
//!
//! `JsonValue` has no flat layout, so values cross the boundary as a refcounted document handle
//! ([`DocObj`]) plus `u32` node ids. A parse yields a document the generated decoders read with the
//! accessors; an encoder starts a `builder_new` document, adds nodes bottom-up and serializes the
//! root. Node ids are only valid for the document that issued them.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::{Doc, Limits, Node, NodeId};
use alloc::boxed::Box;
use alloc::string::String;
use alloc::vec::Vec;
use ms_rt_abi::Obj;
use ms_rt_abi::VecVal;
use ms_std_core::{StrObj, new_string, opt, read_string_list, status_of, str_ref};

unsafe extern "C" {
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_free(p: *mut u8);
}

#[repr(C)]
pub struct DocObj {
    header: Obj,
    doc: *mut Doc,
}

pub const KIND_NULL: u8 = 0;
pub const KIND_BOOL: u8 = 1;
pub const KIND_NUMBER: u8 = 2;
pub const KIND_STRING: u8 = 3;
pub const KIND_ARRAY: u8 = 4;
pub const KIND_OBJECT: u8 = 5;

unsafe extern "C" fn doc_drop(o: *mut Obj) {
    let d = o.cast::<DocObj>();
    // SAFETY: `o` was built by `new_handle`; `doc` came from `Box::into_raw`.
    unsafe {
        drop(Box::from_raw((*d).doc));
        msrt_free(o.cast());
    }
}

unsafe fn new_handle(doc: Doc) -> *mut DocObj {
    // SAFETY: allocation sized for `DocObj`, fully initialised before it is returned.
    unsafe {
        let p = msrt_alloc(core::mem::size_of::<DocObj>()).cast::<DocObj>();
        p.write(DocObj {
            header: Obj {
                rc: 1,
                drop: Some(doc_drop),
            },
            doc: Box::into_raw(Box::new(doc)),
        });
        p
    }
}

unsafe fn doc<'a>(d: *const DocObj) -> &'a Doc {
    // SAFETY: `d` is a live handle.
    unsafe { &*(*d).doc }
}

unsafe fn doc_mut<'a>(d: *mut DocObj) -> &'a mut Doc {
    // SAFETY: `d` is a live handle, uniquely used while building.
    unsafe { &mut *(*d).doc }
}

/// Parses `text`; on success `out` receives the document handle (+1) and `root` its root node.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn msrt_json_parse(
    text: *const StrObj,
    has_max_bytes: u8,
    max_bytes: i64,
    has_max_depth: u8,
    max_depth: i64,
    has_max_values: u8,
    max_values: i64,
    out: *mut *mut DocObj,
    root: *mut u32,
) -> u8 {
    let limits = Limits {
        max_bytes: opt(has_max_bytes, max_bytes),
        max_depth: opt(has_max_depth, max_depth),
        max_values: opt(has_max_values, max_values),
    };
    // SAFETY: `text` is live; `out` and `root` are writable.
    unsafe {
        let r = crate::parse(str_ref(text), limits);
        let status = status_of(&r.as_ref().map(|_| ()).map_err(|e| *e));
        if let Ok((d, id)) = r {
            out.write(new_handle(d));
            root.write(id);
        }
        status
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_kind(d: *const DocObj, id: u32) -> u8 {
    // SAFETY: `d` is a live handle and `id` one of its nodes.
    match unsafe { &doc(d).nodes[id as usize] } {
        Node::Null => KIND_NULL,
        Node::Bool(_) => KIND_BOOL,
        Node::Number(_) => KIND_NUMBER,
        Node::Str(_) => KIND_STRING,
        Node::Array(_) => KIND_ARRAY,
        Node::Object(_) => KIND_OBJECT,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_bool(d: *const DocObj, id: u32) -> u8 {
    // SAFETY: as `msrt_json_kind`.
    u8::from(matches!(
        unsafe { &doc(d).nodes[id as usize] },
        Node::Bool(true)
    ))
}

/// Number text or string content (+1); an empty string for other kinds.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_text(d: *const DocObj, id: u32) -> *mut StrObj {
    // SAFETY: as `msrt_json_kind`.
    match unsafe { &doc(d).nodes[id as usize] } {
        Node::Number(s) | Node::Str(s) => new_string(s),
        _ => new_string(""),
    }
}

/// Element or member count of an array or object; 0 for other kinds.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_len(d: *const DocObj, id: u32) -> i64 {
    // SAFETY: as `msrt_json_kind`.
    match unsafe { &doc(d).nodes[id as usize] } {
        Node::Array(v) => v.len() as i64,
        Node::Object(v) => v.len() as i64,
        _ => 0,
    }
}

/// Element `i` of an array, or the value of member `i` of an object (insertion order).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_item(d: *const DocObj, id: u32, i: i64) -> u32 {
    // SAFETY: as `msrt_json_kind`; `i` is below `msrt_json_len`.
    match unsafe { &doc(d).nodes[id as usize] } {
        Node::Array(v) => v[i as usize],
        Node::Object(v) => v[i as usize].1,
        _ => 0,
    }
}

/// Key of member `i` of an object (+1).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_key(d: *const DocObj, id: u32, i: i64) -> *mut StrObj {
    // SAFETY: as `msrt_json_item`.
    match unsafe { &doc(d).nodes[id as usize] } {
        Node::Object(v) => new_string(&v[i as usize].0),
        _ => new_string(""),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_builder_new() -> *mut DocObj {
    // SAFETY: a fresh handle.
    unsafe { new_handle(Doc::default()) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_add_null(d: *mut DocObj) -> u32 {
    // SAFETY: `d` is a live builder.
    unsafe { doc_mut(d).add(Node::Null) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_add_bool(d: *mut DocObj, v: u8) -> u32 {
    // SAFETY: `d` is a live builder.
    unsafe { doc_mut(d).add(Node::Bool(v != 0)) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_add_number(d: *mut DocObj, text: *const StrObj) -> u32 {
    // SAFETY: `d` is a live builder and `text` a live string.
    unsafe { doc_mut(d).add(Node::Number(String::from(str_ref(text)))) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_add_string(d: *mut DocObj, text: *const StrObj) -> u32 {
    // SAFETY: `d` is a live builder and `text` a live string.
    unsafe { doc_mut(d).add(Node::Str(String::from(str_ref(text)))) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_add_array(d: *mut DocObj, ids: *const u32, n: i64) -> u32 {
    // SAFETY: `ids` points at `n` node ids of this builder.
    unsafe {
        let items = core::slice::from_raw_parts(ids, n as usize).to_vec();
        doc_mut(d).add(Node::Array(items))
    }
}

/// Adds an object from parallel `keys` / `ids` arrays. Later duplicates of a key replace the
/// earlier value in place, as a `Map` would.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_add_object(
    d: *mut DocObj,
    keys: *const *const StrObj,
    ids: *const u32,
    n: i64,
) -> u32 {
    // SAFETY: `keys` and `ids` point at `n` live entries.
    unsafe {
        let mut entries: Vec<(String, NodeId)> = Vec::new();
        for i in 0..n as usize {
            let k = str_ref(*keys.add(i));
            let id = *ids.add(i);
            match entries.iter_mut().find(|e| e.0 == k) {
                Some(e) => e.1 = id,
                None => entries.push((String::from(k), id)),
            }
        }
        doc_mut(d).add(Node::Object(entries))
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_stringify(
    d: *const DocObj,
    root: u32,
    has_max_bytes: u8,
    max_bytes: i64,
    has_indent: u8,
    indent: i64,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: `d` is a live handle; `out` is writable.
    unsafe {
        let r = doc(d).stringify(root, opt(has_max_bytes, max_bytes), opt(has_indent, indent));
        if let Ok(s) = &r {
            out.write(new_string(s));
        }
        status_of(&r)
    }
}

/// `strconv.Itoa`-style decode of number text; status 0 on success.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_dec_int(text: *const StrObj, out: *mut i64) -> u8 {
    // SAFETY: `text` is live; `out` is writable.
    unsafe {
        match crate::parse_int(str_ref(text)) {
            Some(v) => {
                out.write(v);
                0
            }
            None => 1,
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_dec_float(text: *const StrObj, out: *mut f64) -> u8 {
    // SAFETY: `text` is live; `out` is writable.
    unsafe {
        match crate::parse_float(str_ref(text)) {
            Some(v) => {
                out.write(v);
                0
            }
            None => 1,
        }
    }
}

/// Adds a number from `v`, or `null` when `v` is NaN or infinite.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_add_float(d: *mut DocObj, v: f64) -> u32 {
    // SAFETY: `d` is a live builder handle.
    unsafe {
        match crate::float_text(v) {
            Some(text) => doc_mut(d).add(Node::Number(text)),
            None => doc_mut(d).add(Node::Null),
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_add_empty_array(d: *mut DocObj) -> u32 {
    // SAFETY: `d` is a live builder handle.
    unsafe { doc_mut(d).add(Node::Array(Vec::new())) }
}

/// Appends node `item` to the array node `arr`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_array_push(d: *mut DocObj, arr: u32, item: u32) {
    // SAFETY: `d` is a live builder handle; `arr` is an array node of it.
    unsafe {
        if let Node::Array(v) = &mut doc_mut(d).nodes[arr as usize] {
            v.push(item);
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_add_empty_object(d: *mut DocObj) -> u32 {
    // SAFETY: `d` is a live builder handle.
    unsafe { doc_mut(d).add(Node::Object(Vec::new())) }
}

/// Sets member `key` of the object node `obj`; a repeated key replaces the earlier value in place.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_object_put(
    d: *mut DocObj,
    obj: u32,
    key: *const StrObj,
    item: u32,
) {
    // SAFETY: `d` is a live builder handle; `obj` is an object node of it; `key` is live.
    unsafe {
        let k = str_ref(key);
        if let Node::Object(v) = &mut doc_mut(d).nodes[obj as usize] {
            match v.iter_mut().find(|e| e.0 == k) {
                Some(e) => e.1 = item,
                None => v.push((String::from(k), item)),
            }
        }
    }
}

/// Index of member `key` of an object node, or -1.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_find(d: *const DocObj, id: u32, key: *const StrObj) -> i64 {
    // SAFETY: as `msrt_json_item`; `key` is live.
    unsafe {
        let k = str_ref(key);
        match &doc(d).nodes[id as usize] {
            Node::Object(v) => v.iter().position(|e| e.0 == k).map_or(-1, |i| i as i64),
            _ => -1,
        }
    }
}

/// Whether the object node has a member whose key is not in `names` (a list of strings).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_has_unknown(
    d: *const DocObj,
    id: u32,
    names: *const VecVal,
) -> u8 {
    // SAFETY: as `msrt_json_item`; `names` is a live string list.
    unsafe {
        let known = read_string_list(names);
        match &doc(d).nodes[id as usize] {
            Node::Object(v) => u8::from(v.iter().any(|e| !known.contains(&e.0.as_str()))),
            _ => 0,
        }
    }
}

/// The case of an alternative the node names: a string is a payload-free case, an object with one
/// member is the case of that key and `payload` receives the member's node. -1 when none matches.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_variant(
    d: *const DocObj,
    id: u32,
    names: *const VecVal,
    payload: *mut i64,
) -> i64 {
    // SAFETY: as `msrt_json_item`; `names` is a live string list; `payload` is writable.
    unsafe {
        let known = read_string_list(names);
        let index = |name: &str| {
            known
                .iter()
                .position(|k| *k == name)
                .map_or(-1, |i| i as i64)
        };
        match &doc(d).nodes[id as usize] {
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
}

/// Shortest round-trip text of `v` (+1); null when `v` is NaN or infinite (encoded as `null`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_json_enc_float(v: f64) -> *mut StrObj {
    match crate::float_text(v) {
        Some(s) => new_string(&s),
        None => core::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _;
    use ms_rt_abi::STATUS_OK;

    #[test]
    fn roundtrip() {
        let text = new_string(r#"{"a":[1,"x",null],"b":true}"#);
        let mut d = MaybeUninit::<*mut DocObj>::uninit();
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
