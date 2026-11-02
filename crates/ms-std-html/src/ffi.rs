//! C ABI shims for `@std/data/html.ms` (`msstd_html_*`).
//!
//! `HtmlNode` is a sum type with recursive lists, so a parse returns a refcounted tree handle
//! ([`TreeObj`]) and the generated lowering walks it with `u32` node ids: `kind`, `text`, `tag`,
//! `namespace`, child and attribute accessors. Ids are only valid for the tree that issued them.

use crate::{Limits, NodeType, Tree};
use alloc::string::String;
use ms_rt::ffi::{Fail, ObjRef, Object, Out, abi_handle, native};

abi_handle!(Tree);

pub const KIND_DOCUMENT: u8 = 0;
pub const KIND_ELEMENT: u8 = 1;
pub const KIND_TEXT: u8 = 2;
pub const KIND_COMMENT: u8 = 3;
pub const KIND_DOCTYPE: u8 = 4;

native! {
    fn msstd_html_escape(text: &str) -> String {
        crate::escape(text)
    }

    fn msstd_html_unescape(text: &str) -> String {
        crate::unescape(text)
    }

    /// Writes the tree handle and the root node id through `out` and `root` when it succeeds.
    fn msstd_html_parse(
        text: &str,
        has_limits: bool,
        has_max_bytes: bool,
        max_bytes: i64,
        has_max_depth: bool,
        max_depth: i64,
        has_max_nodes: bool,
        max_nodes: i64,
        out: Out<Object<Tree>>,
        root: Out<u32>,
    ) -> Result<(), Fail> {
        // Without a limits record the defaults apply; a record's none fields stay unlimited.
        let limits = if has_limits {
            Limits {
                max_bytes: has_max_bytes.then_some(max_bytes),
                max_depth: has_max_depth.then_some(max_depth),
                max_nodes: has_max_nodes.then_some(max_nodes),
            }
        } else {
            Limits::DEFAULT
        };
        let t = crate::parse(text, limits)?;
        root.write(t.root as u32);
        out.write(Object(t));
        Ok(())
    }

    fn msstd_html_kind(t: ObjRef<Tree>, id: u32) -> u8 {
        match t.nodes[id as usize].ty {
            NodeType::Document | NodeType::ScopeMarker => KIND_DOCUMENT,
            NodeType::Element => KIND_ELEMENT,
            NodeType::Text => KIND_TEXT,
            NodeType::Comment => KIND_COMMENT,
            NodeType::Doctype => KIND_DOCTYPE,
        }
    }

    fn msstd_html_data(t: ObjRef<Tree>, id: u32) -> String {
        t.nodes[id as usize].data.clone()
    }

    fn msstd_html_namespace(t: ObjRef<Tree>, id: u32) -> String {
        t.nodes[id as usize].namespace.clone()
    }

    fn msstd_html_doctype_id(t: ObjRef<Tree>, id: u32, which: u8) -> String {
        let key = if which == 0 { "public" } else { "system" };
        let mut value = "";
        for a in &t.nodes[id as usize].attr {
            if a.key == key {
                value = &a.val;
            }
        }
        String::from(value)
    }

    fn msstd_html_child_count(t: ObjRef<Tree>, id: u32) -> i64 {
        let mut n = 0;
        let mut c = t.nodes[id as usize].first;
        while let Some(k) = c {
            n += 1;
            c = t.nodes[k].next;
        }
        n
    }

    fn msstd_html_child(t: ObjRef<Tree>, id: u32, i: i64) -> u32 {
        let mut c = t.nodes[id as usize].first;
        for _ in 0..i {
            c = c.and_then(|k| t.nodes[k].next);
        }
        c.unwrap_or(0) as u32
    }

    fn msstd_html_first_child(t: ObjRef<Tree>, id: u32) -> u32 {
        t.nodes[id as usize].first.map_or(u32::MAX, |k| k as u32)
    }

    fn msstd_html_next_sibling(t: ObjRef<Tree>, id: u32) -> u32 {
        t.nodes[id as usize].next.map_or(u32::MAX, |k| k as u32)
    }

    fn msstd_html_attr_count(t: ObjRef<Tree>, id: u32) -> i64 {
        t.nodes[id as usize].attr.len() as i64
    }

    fn msstd_html_attr(t: ObjRef<Tree>, id: u32, i: i64, which: u8) -> String {
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
        let mut root = 0u32;
        // SAFETY: all pointers are live; results are released below.
        unsafe {
            assert_eq!(
                msstd_html_parse(&text, 0, 0, 0, 0, 0, 0, 0, t.as_mut_ptr(), &mut root),
                STATUS_OK
            );
            let t = t.assume_init();
            assert_eq!(msstd_html_kind(t, root), KIND_DOCUMENT);
            let html = msstd_html_first_child(t, root);
            assert_eq!(take_string(|o| msstd_html_data(t, html, o)), "html");
            let body = msstd_html_child(t, html, 1);
            let p = msstd_html_first_child(t, body);
            assert_eq!(msstd_html_attr_count(t, p), 1);
            let tx = msstd_html_first_child(t, p);
            assert_eq!(take_string(|o| msstd_html_data(t, tx, o)), "x&y");
            ms_rt::obj::msrt_release(t.cast());
            ms_rt::ffi::str_release(&text);
        }
    }
}
