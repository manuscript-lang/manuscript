//! C ABI shims for `@std/data/html.ms` (`msstd_html_*`).
//!
//! `HtmlNode` is a sum type with recursive lists, so a parse returns an owned tree handle and
//! `@std/data/html.ms` walks it with node ids: `kind`, `data`, `namespace`, child and attribute
//! accessors. Ids are only valid for the tree that issued them; `-1` is no node.
//! ms: domain HTML

use crate::{Limits, NodeType, Tree};
use alloc::string::String;
use ms_rt::ffi::{Fail, Has, ObjRef, Object, abi_handle, native};

abi_handle!(Tree);

pub const KIND_DOCUMENT: i64 = 0;
pub const KIND_ELEMENT: i64 = 1;
pub const KIND_TEXT: i64 = 2;
pub const KIND_COMMENT: i64 = 3;
pub const KIND_DOCTYPE: i64 = 4;

native! {
    // ms: leaf
    fn msstd_html_escape(text: &str) -> String {
        crate::escape(text)
    }

    // ms: leaf
    fn msstd_html_unescape(text: &str) -> String {
        crate::unescape(text)
    }

    /// Parses into a tree handle; without `has_limits` the defaults apply, otherwise a none
    /// bound stays unlimited.
    // ms: leaf
    fn msstd_html_parse(
        text: &str,
        has_limits: Has,
        has_max_bytes: Has,
        max_bytes: i64,
        has_max_depth: Has,
        max_depth: i64,
        has_max_nodes: Has,
        max_nodes: i64,
    ) -> Result<Object<Tree>, Fail> {
        let limits = if *has_limits {
            Limits {
                max_bytes: has_max_bytes.then_some(max_bytes),
                max_depth: has_max_depth.then_some(max_depth),
                max_nodes: has_max_nodes.then_some(max_nodes),
            }
        } else {
            Limits::DEFAULT
        };
        crate::parse(text, limits).map(Object)
    }

    // ms: leaf
    fn msstd_html_root(t: ObjRef<Tree>) -> i64 {
        t.root as i64
    }

    // ms: leaf
    fn msstd_html_kind(t: ObjRef<Tree>, id: i64) -> i64 {
        match t.nodes[id as usize].ty {
            NodeType::Document | NodeType::ScopeMarker => KIND_DOCUMENT,
            NodeType::Element => KIND_ELEMENT,
            NodeType::Text => KIND_TEXT,
            NodeType::Comment => KIND_COMMENT,
            NodeType::Doctype => KIND_DOCTYPE,
        }
    }

    // ms: leaf
    fn msstd_html_data(t: ObjRef<Tree>, id: i64) -> String {
        t.nodes[id as usize].data.clone()
    }

    // ms: leaf
    fn msstd_html_namespace(t: ObjRef<Tree>, id: i64) -> String {
        t.nodes[id as usize].namespace.clone()
    }

    // ms: leaf
    fn msstd_html_doctype_id(t: ObjRef<Tree>, id: i64, which: i64) -> String {
        let key = if which == 0 { "public" } else { "system" };
        let mut value = "";
        for a in &t.nodes[id as usize].attr {
            if a.key == key {
                value = &a.val;
            }
        }
        String::from(value)
    }

    // ms: leaf
    fn msstd_html_first_child(t: ObjRef<Tree>, id: i64) -> i64 {
        t.nodes[id as usize].first.map_or(-1, |k| k as i64)
    }

    // ms: leaf
    fn msstd_html_next_sibling(t: ObjRef<Tree>, id: i64) -> i64 {
        t.nodes[id as usize].next.map_or(-1, |k| k as i64)
    }

    // ms: leaf
    fn msstd_html_attr_count(t: ObjRef<Tree>, id: i64) -> i64 {
        t.nodes[id as usize].attr.len() as i64
    }

    // ms: leaf
    fn msstd_html_attr(t: ObjRef<Tree>, id: i64, i: i64, which: i64) -> String {
        let a = &t.nodes[id as usize].attr[i as usize];
        String::from(match which {
            0 => &a.key,
            1 => &a.namespace,
            _ => &a.val,
        })
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _;
    use ms_rt::ffi::{ObjCell, new_string, take_string};
    use ms_rt_abi::STATUS_OK;

    #[test]
    fn parse_walk() {
        let text = new_string("<p class=a>x&amp;y");
        let mut t = MaybeUninit::<*mut ObjCell<Tree>>::uninit();
        let no = ms_rt_abi::HasRaw(0);
        // SAFETY: all pointers are live; results are released below.
        unsafe {
            assert_eq!(
                msstd_html_parse(&text, no, no, 0, no, 0, no, 0, t.as_mut_ptr()),
                STATUS_OK
            );
            let t = t.assume_init();
            let root = msstd_html_root(t);
            assert_eq!(msstd_html_kind(t, root), KIND_DOCUMENT);
            let html = msstd_html_first_child(t, root);
            assert_eq!(take_string(|o| msstd_html_data(t, html, o)), "html");
            let body = msstd_html_next_sibling(t, msstd_html_first_child(t, html));
            let p = msstd_html_first_child(t, body);
            assert_eq!(msstd_html_attr_count(t, p), 1);
            let tx = msstd_html_first_child(t, p);
            assert_eq!(take_string(|o| msstd_html_data(t, tx, o)), "x&y");
            ms_rt::obj::msrt_obj_drop(t.cast());
            ms_rt::ffi::str_release(&text);
        }
    }
}
