//! C ABI shims for `@std/archive.ms` (`msrt_archive_*`).
//!
//! `ArchiveEntry` records are passed at their natural layout ([`EntryRec`]): a `List[ArchiveEntry]`
//! holds them inline. The optional `ArchiveLimits` argument is flattened to a presence flag plus
//! three `has`/value pairs. `format` is the `ArchiveFormat` case name ("zip" or "tar").

use crate::{Entry, Limits};
use alloc::vec::Vec;
use ms_rt::ffi::{Bytes, Fail, RecList, Str, abi_record, native};

abi_record! {
    /// `ArchiveEntry` record: `path, data, directory`.
    pub struct EntryRec {
        pub path: Str,
        pub data: Bytes,
        pub directory: u8,
    }
}

native! {
    fn msrt_archive_pack(
        entries: &RecList<EntryRec>,
        format: &str,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<u8>, Fail> {
        let entries: Vec<Entry> = entries
            .as_slice()
            .iter()
            .map(|e| Entry {
                path: e.path.as_str().into(),
                data: e.data.as_slice().to_vec(),
                directory: e.directory != 0,
            })
            .collect();
        crate::pack(&entries, format, has_max.then_some(max))
    }

    fn msrt_archive_unpack(
        data: &[u8],
        format: &str,
        has_limits: bool,
        has_entries: bool,
        max_entries: i64,
        has_entry_bytes: bool,
        max_entry_bytes: i64,
        has_total: bool,
        max_total_bytes: i64,
    ) -> Result<RecList<EntryRec>, Fail> {
        let limits = has_limits.then_some(Limits {
            max_entries: has_entries.then_some(max_entries),
            max_entry_bytes: has_entry_bytes.then_some(max_entry_bytes),
            max_total_bytes: has_total.then_some(max_total_bytes),
        });
        let entries = crate::unpack(data, format, limits)?;
        Ok(RecList::new(entries.iter().map(|e| EntryRec {
            path: Str::new(&e.path),
            data: Bytes::new(&e.data),
            directory: u8::from(e.directory),
        })))
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
