//! C ABI shims for `@std/archive.ms` (`msrt_archive_*`).
//!
//! `ArchiveEntry` records are passed at their natural layout ([`EntryRec`]): a `List[ArchiveEntry]`
//! holds them inline. The optional `ArchiveLimits` argument is flattened to a presence flag plus
//! three `has`/value pairs. `format` is the `ArchiveFormat` case name ("zip" or "tar").
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::{Entry, Limits};
use alloc::vec::Vec;
use ms_rt_abi::KIND_CUSTOM;
use ms_std_core::{
    StrObj, TypeDesc, VecVal, bytes_ref, new_string, opt, status_of, str_ref, write_bytes,
};

unsafe extern "C" {
    fn msrt_list_new(out: *mut VecVal);
    fn msrt_list_push(v: *mut VecVal, d: *const TypeDesc, e: *const u8);
    fn msrt_retain(o: *mut ms_rt_abi::Obj);
    fn msrt_release(o: *mut ms_rt_abi::Obj);
    fn msrt_bytes_drop(b: *mut VecVal);
    fn msrt_bytes_copy(b: *const VecVal, out: *mut VecVal);
}

/// `ArchiveEntry` record: `path, data, directory`.
#[repr(C)]
pub struct EntryRec {
    pub path: *mut StrObj,
    pub data: VecVal,
    pub directory: u8,
}

unsafe extern "C" fn entry_drop(slot: *mut u8) {
    // SAFETY: `slot` holds an `EntryRec` owning its string and bytes.
    unsafe {
        let e = slot.cast::<EntryRec>();
        msrt_release((*e).path.cast());
        msrt_bytes_drop(&raw mut (*e).data);
    }
}

unsafe extern "C" fn entry_copy(src: *const u8, dst: *mut u8) {
    // SAFETY: `src` holds a live record; `dst` is writable and uninitialised.
    unsafe {
        let e = src.cast::<EntryRec>();
        msrt_retain((*e).path.cast());
        let d = dst.cast::<EntryRec>();
        (&raw mut (*d).path).write((*e).path);
        msrt_bytes_copy(&raw const (*e).data, &raw mut (*d).data);
        (&raw mut (*d).directory).write((*e).directory);
    }
}

/// Descriptor of `ArchiveEntry`, for `List[ArchiveEntry]`.
pub static DESC_ENTRY: TypeDesc = TypeDesc {
    size: core::mem::size_of::<EntryRec>() as u32,
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

unsafe fn read_entries(list: *const VecVal) -> Vec<Entry> {
    // SAFETY: `list` is a live `List[ArchiveEntry]`; records are stored inline.
    unsafe {
        let v = &*list;
        (0..v.len)
            .map(|i| {
                let e = &*(v.ptr as *const EntryRec).add(i);
                Entry {
                    path: str_ref(e.path).into(),
                    data: bytes_ref(&raw const e.data).to_vec(),
                    directory: e.directory != 0,
                }
            })
            .collect()
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_archive_pack(
    entries: *const VecVal,
    format: *const StrObj,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: arguments are live; `out` is writable.
    unsafe {
        let r = crate::pack(&read_entries(entries), str_ref(format), opt(has_max, max));
        if let Ok(b) = &r {
            write_bytes(out, b);
        }
        status_of(&r)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_archive_unpack(
    data: *const VecVal,
    format: *const StrObj,
    has_limits: u8,
    has_entries: u8,
    max_entries: i64,
    has_entry_bytes: u8,
    max_entry_bytes: i64,
    has_total: u8,
    max_total_bytes: i64,
    out: *mut VecVal,
) -> u8 {
    let limits = (has_limits != 0).then_some(Limits {
        max_entries: opt(has_entries, max_entries),
        max_entry_bytes: opt(has_entry_bytes, max_entry_bytes),
        max_total_bytes: opt(has_total, max_total_bytes),
    });
    // SAFETY: arguments are live; `out` is writable.
    unsafe {
        let r = crate::unpack(bytes_ref(data), str_ref(format), limits);
        if let Ok(entries) = &r {
            msrt_list_new(out);
            for e in entries {
                let mut rec = core::mem::MaybeUninit::<EntryRec>::uninit();
                let p = rec.as_mut_ptr();
                (&raw mut (*p).path).write(new_string(&e.path));
                write_bytes(&raw mut (*p).data, &e.data);
                (&raw mut (*p).directory).write(u8::from(e.directory));
                msrt_list_push(out, &DESC_ENTRY, p.cast());
            }
        }
        status_of::<Vec<Entry>>(&r)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ms_rt as _; // links the msrt_* runtime symbols

    #[test]
    fn pack_unpack_roundtrip() {
        for format in ["tar", "zip"] {
            let entries = alloc::vec![
                Entry {
                    path: "d".into(),
                    data: Vec::new(),
                    directory: true
                },
                Entry {
                    path: "d/a.txt".into(),
                    data: b"hello".to_vec(),
                    directory: false
                },
            ];
            let packed = crate::pack(&entries, format, None).unwrap();
            let back = crate::unpack(&packed, format, None).unwrap();
            assert_eq!(back.len(), 2, "{format}");
            assert_eq!(
                (back[1].path.as_str(), back[1].data.as_slice()),
                ("d/a.txt", &b"hello"[..])
            );
        }
    }
}
