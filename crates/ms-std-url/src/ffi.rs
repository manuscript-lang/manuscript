//! C ABI shims for `@std/url.ms` (`msrt_url_*`).
//!
//! `Url` and `QueryEntry` are passed by pointer to records at their natural layout, fields in
//! declaration order (see [`UrlRec`], [`QueryEntryRec`]). Strings inside a record written by the
//! runtime are owned (+1) by the record; strings inside a record read by the runtime are borrowed.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::Components;
use ms_rt_abi::KIND_CUSTOM;
use ms_std_core::{StrObj, TypeDesc, VecVal, new_string, opt, status_of, str_ref};

unsafe extern "C" {
    fn msrt_list_new(out: *mut VecVal);
    fn msrt_list_push(v: *mut VecVal, d: *const TypeDesc, e: *const u8);
    fn msrt_retain(o: *mut ms_rt_abi::Obj);
    fn msrt_release(o: *mut ms_rt_abi::Obj);
}

/// `Url` record: `scheme, host, port: Optional[Int], path, query, fragment`.
#[repr(C)]
pub struct UrlRec {
    pub scheme: *mut StrObj,
    pub host: *mut StrObj,
    pub port_present: u8,
    pub port: i64,
    pub path: *mut StrObj,
    pub query: *mut StrObj,
    pub fragment: *mut StrObj,
}

/// `QueryEntry` record: `key, value`.
#[repr(C)]
pub struct QueryEntryRec {
    pub key: *mut StrObj,
    pub value: *mut StrObj,
}

unsafe fn read_url(u: *const UrlRec) -> Components {
    // SAFETY: `u` is a live Url record whose strings are live.
    unsafe {
        let u = &*u;
        Components {
            scheme: str_ref(u.scheme).into(),
            host: str_ref(u.host).into(),
            port: opt(u.port_present, u.port),
            path: str_ref(u.path).into(),
            query: str_ref(u.query).into(),
            fragment: str_ref(u.fragment).into(),
        }
    }
}

unsafe fn write_url(c: &Components, out: *mut UrlRec) {
    // SAFETY: `out` is writable.
    unsafe {
        out.write(UrlRec {
            scheme: new_string(&c.scheme),
            host: new_string(&c.host),
            port_present: u8::from(c.port.is_some()),
            port: c.port.unwrap_or(0),
            path: new_string(&c.path),
            query: new_string(&c.query),
            fragment: new_string(&c.fragment),
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_url_encode_component(text: *const StrObj) -> *mut StrObj {
    // SAFETY: `text` is live.
    new_string(&crate::encode_component(unsafe { str_ref(text) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_url_decode_component(
    text: *const StrObj,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: `text` is live; `out` is writable.
    unsafe {
        let r = crate::decode_component(str_ref(text));
        if let Ok(s) = &r {
            out.write(new_string(s));
        }
        status_of(&r)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_url_parse(text: *const StrObj, out: *mut UrlRec) -> u8 {
    // SAFETY: `text` is live; `out` is writable.
    unsafe {
        let r = crate::parse(str_ref(text));
        if let Ok(c) = &r {
            write_url(c, out);
        }
        status_of(&r)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_url_resolve(
    base: *const UrlRec,
    reference: *const StrObj,
    out: *mut UrlRec,
) -> u8 {
    // SAFETY: `base` is a live Url record; `reference` is live; `out` is writable.
    unsafe {
        let r = crate::resolve(&read_url(base), str_ref(reference));
        if let Ok(c) = &r {
            write_url(c, out);
        }
        status_of(&r)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_url_format(value: *const UrlRec, out: *mut *mut StrObj) -> u8 {
    // SAFETY: `value` is a live Url record; `out` is writable.
    unsafe {
        let r = crate::format(&read_url(value));
        if let Ok(s) = &r {
            out.write(new_string(s));
        }
        status_of(&r)
    }
}

unsafe extern "C" fn entry_drop(slot: *mut u8) {
    // SAFETY: `slot` holds a `QueryEntryRec` owning both strings.
    unsafe {
        let e = &*(slot as *const QueryEntryRec);
        msrt_release(e.key.cast());
        msrt_release(e.value.cast());
    }
}

unsafe extern "C" fn entry_copy(src: *const u8, dst: *mut u8) {
    // SAFETY: `src` holds a live record; `dst` is writable and uninitialised.
    unsafe {
        let e = &*(src as *const QueryEntryRec);
        msrt_retain(e.key.cast());
        msrt_retain(e.value.cast());
        (dst as *mut QueryEntryRec).write(QueryEntryRec {
            key: e.key,
            value: e.value,
        });
    }
}

/// Descriptor of `QueryEntry` (a record of two strings), for `List[QueryEntry]`.
pub static DESC_QUERY_ENTRY: TypeDesc = TypeDesc {
    size: 16,
    align: 8,
    kind: KIND_CUSTOM,
    reserved: 0,
    inner0: core::ptr::null(),
    inner1: core::ptr::null(),
    drop: Some(entry_drop),
    copy: Some(entry_copy),
    eq: None,
    hash: None,
};

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_url_parse_query(
    text: *const StrObj,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `text` is live; `out` is writable.
    unsafe {
        let r = crate::parse_query(str_ref(text), opt(has_max, max));
        if let Ok(items) = &r {
            msrt_list_new(out);
            for (k, v) in items {
                let e = QueryEntryRec {
                    key: new_string(k),
                    value: new_string(v),
                };
                msrt_list_push(out, &DESC_QUERY_ENTRY, (&raw const e).cast());
            }
        }
        status_of(&r)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_url_format_query(entries: *const VecVal) -> *mut StrObj {
    // SAFETY: `entries` is a live `List[QueryEntry]`, records stored inline 16 bytes apart.
    unsafe {
        let v = &*entries;
        let items: alloc::vec::Vec<(&str, &str)> = (0..v.len)
            .map(|i| {
                let e = &*(v.ptr as *const QueryEntryRec).add(i);
                (str_ref(e.key), str_ref(e.value))
            })
            .collect();
        new_string(&crate::format_query(&items))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt_abi::STATUS_OK;

    #[test]
    fn abi_roundtrip() {
        let text = new_string("https://Example.com:81/p?a=1&a=2#f");
        let mut rec = MaybeUninit::<UrlRec>::uninit();
        let mut s = MaybeUninit::<*mut StrObj>::uninit();
        let mut q = MaybeUninit::<VecVal>::uninit();
        // SAFETY: all pointers are live; results are released below.
        unsafe {
            assert_eq!(msrt_url_parse(text, rec.as_mut_ptr()), STATUS_OK);
            let r = rec.assume_init_ref();
            assert_eq!(
                (str_ref(r.host), r.port_present, r.port),
                ("example.com", 1, 81)
            );
            assert_eq!(msrt_url_format(rec.as_ptr(), s.as_mut_ptr()), STATUS_OK);
            assert_eq!(
                str_ref(s.assume_init()),
                "https://example.com:81/p?a=1&a=2#f"
            );
            assert_eq!(
                msrt_url_parse_query(r.query, 0, 0, q.as_mut_ptr()),
                STATUS_OK
            );
            assert_eq!((*q.as_ptr()).len, 2);
            let f = msrt_url_format_query(q.as_ptr());
            assert_eq!(str_ref(f), "a=1&a=2");
            ms_rt::vec::msrt_list_drop(q.as_mut_ptr(), &DESC_QUERY_ENTRY);
            for o in [
                r.scheme,
                r.host,
                r.path,
                r.query,
                r.fragment,
                text,
                f,
                s.assume_init(),
            ] {
                msrt_release(o.cast());
            }
        }
    }
}
