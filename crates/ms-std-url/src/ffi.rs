//! C ABI shims for `@std/net.ms` (`msrt_url_*`).
//!
//! `Url` and `QueryEntry` are records at their natural layout, fields in declaration order (see
//! [`UrlRec`], [`QueryEntryRec`]). Strings inside a record written by the runtime are owned (+1)
//! by the record; strings inside a record read by the runtime are borrowed.
use crate::Components;
use alloc::string::String;
use alloc::vec::Vec;
use ms_rt::ffi::{Fail, OptInt, RecList, Str, abi_record, native};

abi_record! {
    /// `Url` record: `scheme, host, port: Int?, path, query, fragment`.
    pub struct UrlRec {
        pub scheme: Str,
        pub host: Str,
        pub port: OptInt,
        pub path: Str,
        pub query: Str,
        pub fragment: Str,
    }
}

abi_record! {
    /// `QueryEntry` record: `key, value`.
    pub struct QueryEntryRec {
        pub key: Str,
        pub value: Str,
    }
}

fn read_url(u: &UrlRec) -> Components {
    Components {
        scheme: u.scheme.as_str().into(),
        host: u.host.as_str().into(),
        port: u.port.get(),
        path: u.path.as_str().into(),
        query: u.query.as_str().into(),
        fragment: u.fragment.as_str().into(),
    }
}

fn write_url(c: Components) -> UrlRec {
    UrlRec {
        scheme: Str::new(&c.scheme),
        host: Str::new(&c.host),
        port: OptInt::new(c.port),
        path: Str::new(&c.path),
        query: Str::new(&c.query),
        fragment: Str::new(&c.fragment),
    }
}

native! {
    fn msrt_url_encode_component(text: &str) -> String {
        crate::encode_component(text)
    }

    fn msrt_url_decode_component(text: &str) -> Result<String, Fail> {
        crate::decode_component(text)
    }

    fn msrt_url_parse(text: &str) -> Result<UrlRec, Fail> {
        crate::parse(text).map(write_url)
    }

    fn msrt_url_resolve(base: &UrlRec, reference: &str) -> Result<UrlRec, Fail> {
        crate::resolve(&read_url(base), reference).map(write_url)
    }

    fn msrt_url_format(value: &UrlRec) -> Result<String, Fail> {
        crate::format(&read_url(value))
    }

    fn msrt_url_parse_query(
        text: &str,
        has_max: bool,
        max: i64,
    ) -> Result<RecList<QueryEntryRec>, Fail> {
        crate::parse_query(text, has_max.then_some(max)).map(|items| {
            RecList::new(items.iter().map(|(k, v)| QueryEntryRec {
                key: Str::new(k),
                value: Str::new(v),
            }))
        })
    }

    fn msrt_url_format_query(entries: &RecList<QueryEntryRec>) -> String {
        let items: Vec<(&str, &str)> = entries
            .as_slice()
            .iter()
            .map(|e| (e.key.as_str(), e.value.as_str()))
            .collect();
        crate::format_query(&items)
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt::ffi::AbiRecord;
    use ms_rt::ffi::{StrVal, VecVal, new_string, str_ref, take_string};
    use ms_rt_abi::STATUS_OK;

    #[test]
    fn abi_roundtrip() {
        let text = new_string("https://Example.com:81/p?a=1&a=2#f");
        let mut rec = MaybeUninit::<UrlRec>::uninit();
        let mut s = MaybeUninit::<StrVal>::uninit();
        let mut q = MaybeUninit::<VecVal>::uninit();
        // SAFETY: all pointers are live; results are released below.
        unsafe {
            assert_eq!(msrt_url_parse(&text, rec.as_mut_ptr()), STATUS_OK);
            let r = rec.assume_init_ref();
            assert_eq!((r.host.as_str(), r.port.get()), ("example.com", Some(81)));
            assert_eq!(msrt_url_format(rec.as_ptr(), s.as_mut_ptr()), STATUS_OK);
            assert_eq!(str_ref(s.as_ptr()), "https://example.com:81/p?a=1&a=2#f");
            assert_eq!(
                msrt_url_parse_query(r.query.as_ptr(), 0, 0, q.as_mut_ptr()),
                STATUS_OK
            );
            assert_eq!((*q.as_ptr()).len, 2);
            let f = take_string(|o| msrt_url_format_query(q.as_ptr().cast(), o));
            assert_eq!(f, "a=1&a=2");
            ms_rt::vec::msrt_list_drop(q.as_mut_ptr(), QueryEntryRec::desc());
            for o in [
                r.scheme.as_ptr(),
                r.host.as_ptr(),
                r.path.as_ptr(),
                r.query.as_ptr(),
                r.fragment.as_ptr(),
            ] {
                ms_rt::ffi::str_release(&*o);
            }
            for o in [text, s.assume_init()] {
                ms_rt::ffi::str_release(&o);
            }
        }
    }
}
