//! C ABI shims for `@std/html.ms` (`msrt_html_*`).
//!
//! `HtmlNode` is a sum type with recursive lists, so a parse returns a refcounted tree handle
//! ([`TreeObj`]) and the generated lowering walks it with `u32` node ids: `kind`, `text`, `tag`,
//! `namespace`, child and attribute accessors. Ids are only valid for the tree that issued them.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::{Limits, NodeType, Tree};
use alloc::boxed::Box;
use ms_rt_abi::Obj;
use ms_std_core::{StrObj, new_string, opt, status_of, str_ref};

unsafe extern "C" {
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_free(p: *mut u8);
}

#[repr(C)]
pub struct TreeObj {
    header: Obj,
    tree: *mut Tree,
}

pub const KIND_DOCUMENT: u8 = 0;
pub const KIND_ELEMENT: u8 = 1;
pub const KIND_TEXT: u8 = 2;
pub const KIND_COMMENT: u8 = 3;
pub const KIND_DOCTYPE: u8 = 4;

unsafe extern "C" fn tree_drop(o: *mut Obj) {
    let t = o.cast::<TreeObj>();
    // SAFETY: `o` was built by `msrt_html_parse`; `tree` came from `Box::into_raw`.
    unsafe {
        drop(Box::from_raw((*t).tree));
        msrt_free(o.cast());
    }
}

unsafe fn tree<'a>(t: *const TreeObj) -> &'a Tree {
    // SAFETY: `t` is a live handle.
    unsafe { &*(*t).tree }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_html_escape(text: *const StrObj) -> *mut StrObj {
    // SAFETY: `text` is live.
    new_string(&crate::escape(unsafe { str_ref(text) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_html_unescape(text: *const StrObj) -> *mut StrObj {
    // SAFETY: `text` is live.
    new_string(&crate::unescape(unsafe { str_ref(text) }))
}

/// Parses `text`; on success `out` receives the tree handle (+1) and `root` the document node.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn msrt_html_parse(
    text: *const StrObj,
    has_max_bytes: u8,
    max_bytes: i64,
    has_max_depth: u8,
    max_depth: i64,
    has_max_nodes: u8,
    max_nodes: i64,
    out: *mut *mut TreeObj,
    root: *mut u32,
) -> u8 {
    let limits = Limits {
        max_bytes: opt(has_max_bytes, max_bytes),
        max_depth: opt(has_max_depth, max_depth),
        max_nodes: opt(has_max_nodes, max_nodes),
    };
    // SAFETY: `text` is live; `out` and `root` are writable; the allocation is sized for
    // `TreeObj` and fully initialised before it is published.
    unsafe {
        let r = crate::parse(str_ref(text), limits);
        let status = status_of(&r.as_ref().map(|_| ()).map_err(|e| *e));
        if let Ok(t) = r {
            root.write(t.root as u32);
            let p = msrt_alloc(core::mem::size_of::<TreeObj>()).cast::<TreeObj>();
            p.write(TreeObj {
                header: Obj {
                    rc: 1,
                    drop: Some(tree_drop),
                },
                tree: Box::into_raw(Box::new(t)),
            });
            out.write(p);
        }
        status
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_html_kind(t: *const TreeObj, id: u32) -> u8 {
    // SAFETY: `t` is a live handle and `id` one of its nodes.
    match unsafe { tree(t).nodes[id as usize].ty } {
        NodeType::Document | NodeType::ScopeMarker => KIND_DOCUMENT,
        NodeType::Element => KIND_ELEMENT,
        NodeType::Text => KIND_TEXT,
        NodeType::Comment => KIND_COMMENT,
        NodeType::Doctype => KIND_DOCTYPE,
    }
}

/// Text or comment contents, element tag, or doctype name (+1).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_html_data(t: *const TreeObj, id: u32) -> *mut StrObj {
    // SAFETY: as `msrt_html_kind`.
    new_string(unsafe { &tree(t).nodes[id as usize].data })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_html_namespace(t: *const TreeObj, id: u32) -> *mut StrObj {
    // SAFETY: as `msrt_html_kind`.
    new_string(unsafe { &tree(t).nodes[id as usize].namespace })
}

/// Doctype public (`which` 0) or system (`which` 1) identifier (+1); empty when absent.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_html_doctype_id(
    t: *const TreeObj,
    id: u32,
    which: u8,
) -> *mut StrObj {
    let key = if which == 0 { "public" } else { "system" };
    // SAFETY: as `msrt_html_kind`.
    let node = unsafe { &tree(t).nodes[id as usize] };
    let mut value = "";
    for a in &node.attr {
        if a.key == key {
            value = &a.val;
        }
    }
    new_string(value)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_html_child_count(t: *const TreeObj, id: u32) -> i64 {
    // SAFETY: as `msrt_html_kind`.
    let tr = unsafe { tree(t) };
    let mut n = 0;
    let mut c = tr.nodes[id as usize].first;
    while let Some(k) = c {
        n += 1;
        c = tr.nodes[k].next;
    }
    n
}

/// The `i`th child of `id`. Walking is linear; callers iterate with [`msrt_html_first_child`] and
/// [`msrt_html_next_sibling`] instead when order matters for cost.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_html_child(t: *const TreeObj, id: u32, i: i64) -> u32 {
    // SAFETY: as `msrt_html_kind`; `i` is below the child count.
    let tr = unsafe { tree(t) };
    let mut c = tr.nodes[id as usize].first;
    for _ in 0..i {
        c = c.and_then(|k| tr.nodes[k].next);
    }
    c.unwrap_or(0) as u32
}

/// First child of `id`, or `u32::MAX` when there is none.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_html_first_child(t: *const TreeObj, id: u32) -> u32 {
    // SAFETY: as `msrt_html_kind`.
    unsafe {
        tree(t).nodes[id as usize]
            .first
            .map_or(u32::MAX, |k| k as u32)
    }
}

/// Next sibling of `id`, or `u32::MAX` when it is the last.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_html_next_sibling(t: *const TreeObj, id: u32) -> u32 {
    // SAFETY: as `msrt_html_kind`.
    unsafe {
        tree(t).nodes[id as usize]
            .next
            .map_or(u32::MAX, |k| k as u32)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_html_attr_count(t: *const TreeObj, id: u32) -> i64 {
    // SAFETY: as `msrt_html_kind`.
    unsafe { tree(t).nodes[id as usize].attr.len() as i64 }
}

/// Attribute `i` of element `id`: `which` 0 name, 1 namespace, 2 value (+1).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_html_attr(
    t: *const TreeObj,
    id: u32,
    i: i64,
    which: u8,
) -> *mut StrObj {
    // SAFETY: as `msrt_html_kind`; `i` is below the attribute count.
    let a = unsafe { &tree(t).nodes[id as usize].attr[i as usize] };
    new_string(match which {
        0 => &a.key,
        1 => &a.namespace,
        _ => &a.val,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _;
    use ms_rt_abi::STATUS_OK;

    #[test]
    fn parse_walk() {
        let text = new_string("<p class=a>x&amp;y");
        let mut t = MaybeUninit::<*mut TreeObj>::uninit();
        let mut root = 0u32;
        // SAFETY: all pointers are live; results are released below.
        unsafe {
            assert_eq!(
                msrt_html_parse(text, 0, 0, 0, 0, 0, 0, t.as_mut_ptr(), &mut root),
                STATUS_OK
            );
            let t = t.assume_init();
            assert_eq!(msrt_html_kind(t, root), KIND_DOCUMENT);
            let html = msrt_html_first_child(t, root);
            assert_eq!(str_ref(msrt_html_data(t, html)), "html");
            let body = msrt_html_child(t, html, 1);
            let p = msrt_html_first_child(t, body);
            assert_eq!(msrt_html_attr_count(t, p), 1);
            let tx = msrt_html_first_child(t, p);
            assert_eq!(str_ref(msrt_html_data(t, tx)), "x&y");
            ms_rt::obj::msrt_release(t.cast());
            ms_rt::obj::msrt_release(text.cast());
        }
    }
}
