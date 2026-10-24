//! `@std/fs` natives for path-based operations. Symbols are `msstd_fs_<name>`.
//!
//! Paths arrive as strings; fallible functions return a `STATUS_*` code (`0` ok) and write results
//! only on success. For `STATUS_FAILED` the Go-style diagnostic text is available from
//! `msstd_fs_failure_message` until the next fallible call. `FileInfo` is flattened into
//! [`InfoOut`]; optional limits are a present flag plus an `i64`.
// `libc::statfs` field widths differ per target, so the portable casts look redundant on Linux.
#![allow(clippy::unnecessary_cast)]

extern crate alloc;

pub mod consts;
pub mod dir;
pub mod err;
pub mod file;
pub mod ops;
pub mod path;
#[allow(unsafe_code)] // the runtime flush hook
pub mod stream;
#[allow(unsafe_code)] // libc and Win32 calls
pub mod sys;
pub mod walk;
#[allow(unsafe_code)] // inotify
pub mod watch;

use alloc::vec::Vec;
use err::{Fail, Res};
use ms_rt::ffi::{
    BytesList, EntryFilter, IntList, ObjMut, ObjRef, ObjShare, Object, PairFilter, RecList,
    StatusCode, Str, Text, TextList, abi_record, native,
};
use ms_rt_abi::{STATUS_INVALID_INPUT, STATUS_NONE, StrVal};
use stream::Stream;

/// A filesystem result as a status: a failure records its text for `msstd_fs_failure_message`.
pub fn fs_status<T>(r: Res<T>) -> Result<T, StatusCode> {
    r.map_err(|Fail { status, message }| {
        ms_rt::glue::record_failure(message.unwrap_or_default());
        StatusCode(status)
    })
}

/// A decoded optional size limit.
fn lim(has: bool, v: i64) -> Res<i64> {
    ops::limit(has, v)
}

abi_record! {
    /// Flattened `FileInfo`: a string followed by `i64` words only, so compiled code reads it as a
    /// record. Times are `(seconds, nanoseconds)`; `created_present` says whether the creation time
    /// exists on this host. `kinds` is the `KIND_*` bit set from `ops`; unsigned host counters
    /// carry their bits (`exact` reads them back as unsigned).
    pub struct InfoOut {
        pub name: Str,
        pub size: i64,
        pub mode: i64,
        pub permissions: i64,
        pub modified_seconds: i64,
        pub modified_nanos: i64,
        pub accessed_seconds: i64,
        pub accessed_nanos: i64,
        pub changed_seconds: i64,
        pub changed_nanos: i64,
        pub created_seconds: i64,
        pub created_nanos: i64,
        pub created_present: i64,
        pub kinds: i64,
        pub block_size: i64,
        pub blocks: i64,
        pub rdev: i64,
        pub device: i64,
        pub inode: i64,
        pub links: i64,
        pub uid: i64,
        pub gid: i64,
    }
}

fn info_out(i: ops::Info) -> InfoOut {
    let (cs, cn) = i.created.unwrap_or((0, 0));
    InfoOut {
        name: Str::from_bytes(&i.name),
        size: i.size,
        mode: i.mode,
        permissions: i.permissions,
        modified_seconds: i.modified.0,
        modified_nanos: i.modified.1,
        accessed_seconds: i.accessed.0,
        accessed_nanos: i.accessed.1,
        changed_seconds: i.changed.0,
        changed_nanos: i.changed.1,
        created_seconds: cs,
        created_nanos: cn,
        created_present: i.created.is_some() as i64,
        kinds: i64::from(i.kinds()),
        block_size: i.block_size as i64,
        blocks: i.blocks as i64,
        rdev: i.rdev as i64,
        device: i.device as i64,
        inode: i.inode as i64,
        links: i.links as i64,
        uid: i.uid as i64,
        gid: i.gid as i64,
    }
}

abi_record! {
    /// One `DirectoryEntry` as compiled code lays the record out: the name, then two flag bytes.
    pub struct EntryOut {
        pub name: Str,
        pub directory: u8,
        pub symlink: u8,
    }
}

fn entry_out(name: &[u8], directory: bool, symlink: bool) -> EntryOut {
    EntryOut {
        name: Str::from_bytes(name),
        directory: u8::from(directory),
        symlink: u8::from(symlink),
    }
}

abi_record! {
    /// Flattened filesystem status: type id, block size, blocks, free, available, files, free files.
    pub struct FsOut {
        pub kind: i64,
        pub block_size: i64,
        pub blocks: i64,
        pub blocks_free: i64,
        pub blocks_available: i64,
        pub files: i64,
        pub files_free: i64,
    }
}

abi_record! {
    /// One `PathEntry`: the path, then the nested `DirectoryEntry`'s name and two flag bytes.
    pub struct PathEntryOut {
        pub path: Str,
        pub name: Str,
        pub directory: u8,
        pub symlink: u8,
    }
}

native! {
    /// The text describing the last `STATUS_FAILED` result (a fresh string).
    fn msstd_fs_failure_message() -> out StrVal {
        ms_rt::glue::failure_message()
    }

    /// Reads a whole file as bytes.
    fn msstd_fs_read_file(path: &str, has_max: bool, max: i64) -> Result<Vec<u8>, StatusCode> {
        fs_status(lim(has_max, max).and_then(|m| ops::read_file(path.as_bytes(), m)))
    }

    /// Writes bytes to a file (`replace` truncates, otherwise the file must not exist).
    fn msstd_fs_write_file(path: &str, data: &[u8], replace: bool) -> Result<(), StatusCode> {
        fs_status(ops::write_file(path.as_bytes(), data, replace))
    }

    fn msstd_fs_append_file(path: &str, data: &[u8]) -> Result<(), StatusCode> {
        fs_status(ops::append_file(path.as_bytes(), data))
    }

    fn msstd_fs_copy_file(
        source: &str,
        destination: &str,
        replace: bool,
        has_max: bool,
        max: i64,
    ) -> Result<(), StatusCode> {
        fs_status(lim(has_max, max)
            .and_then(|m| ops::copy_file(source.as_bytes(), destination.as_bytes(), replace, m)))
    }

    /// `follow` resolves a final symlink (`stat`), otherwise it reports the link (`lstat`).
    fn msstd_fs_stat(path: &str, follow: bool) -> Result<InfoOut, StatusCode> {
        fs_status(ops::stat(path.as_bytes(), follow)).map(info_out)
    }

    /// Lists a directory sorted by name into a `List[DirectoryEntry]`.
    fn msstd_fs_list(
        path: &str,
        has_limit: bool,
        limit: i64,
    ) -> Result<RecList<EntryOut>, StatusCode> {
        let entries = fs_status(lim(has_limit, limit).and_then(|m| ops::list(path.as_bytes(), m)))?;
        Ok(RecList::new(entries.iter().map(|e| entry_out(&e.name, e.directory, e.symlink))))
    }

    fn msstd_fs_create_directory(path: &str, recursive: bool) -> Result<(), StatusCode> {
        fs_status(ops::create_directory(path.as_bytes(), recursive))
    }

    fn msstd_fs_remove(path: &str, recursive: bool) -> Result<(), StatusCode> {
        fs_status(ops::remove(path.as_bytes(), recursive))
    }

    fn msstd_fs_rename(source: &str, destination: &str) -> Result<(), StatusCode> {
        fs_status(ops::rename(source.as_bytes(), destination.as_bytes()))
    }

    fn msstd_fs_read_link(path: &str) -> Result<Text, StatusCode> {
        fs_status(ops::read_link(path.as_bytes())).map(Text)
    }

    fn msstd_fs_create_link(path: &str, target: &str) -> Result<(), StatusCode> {
        fs_status(ops::create_link(path.as_bytes(), target.as_bytes()))
    }

    fn msstd_fs_hard_link(source: &str, destination: &str) -> Result<(), StatusCode> {
        fs_status(ops::hard_link(source.as_bytes(), destination.as_bytes()))
    }

    fn msstd_fs_canonicalize(path: &str) -> Result<Text, StatusCode> {
        fs_status(ops::canonicalize(path.as_bytes())).map(Text)
    }

    safe fn msstd_fs_temporary_root() -> Text {
        Text(ops::temporary_root())
    }

    fn msstd_fs_temporary_directory(pattern: &str) -> Result<Text, StatusCode> {
        fs_status(ops::temporary_directory(pattern.as_bytes())).map(Text)
    }

    fn msstd_fs_stat_filesystem(path: &str) -> Result<FsOut, StatusCode> {
        fs_status(ops::stat_filesystem(path.as_bytes())).map(|s| FsOut {
            kind: s.kind,
            block_size: s.block_size,
            blocks: s.blocks,
            blocks_free: s.blocks_free,
            blocks_available: s.blocks_available,
            files: s.files,
            files_free: s.files_free,
        })
    }

    fn msstd_fs_chmod(path: &str, mode: i64, follow: bool) -> Result<(), StatusCode> {
        let p = path.as_bytes();
        fs_status(if follow { ops::chmod(p, mode) } else { ops::chmod_link(p, mode) })
    }

    fn msstd_fs_access(path: &str, mode: i64) -> Result<(), StatusCode> {
        fs_status(ops::access(path.as_bytes(), mode))
    }

    fn msstd_fs_chown(path: &str, uid: i64, gid: i64, follow: bool) -> Result<(), StatusCode> {
        fs_status(ops::chown(path.as_bytes(), uid, gid, follow))
    }

    fn msstd_fs_truncate(path: &str, size: i64) -> Result<(), StatusCode> {
        fs_status(ops::truncate(path.as_bytes(), size))
    }

    fn msstd_fs_set_times(
        path: &str,
        accessed_seconds: i64,
        accessed_nanos: i64,
        modified_seconds: i64,
        modified_nanos: i64,
        follow: bool,
    ) -> Result<(), StatusCode> {
        fs_status(ops::set_times(
            path.as_bytes(),
            (accessed_seconds, accessed_nanos),
            (modified_seconds, modified_nanos),
            follow,
        ))
    }

    // ---- File handles, directory cursors, temporary directories, glob and copy ----

    /// Opens a file handle. The same handle serves the `msstd_io_*` stream exports.
    fn msstd_fs_file_open(
        path: &str,
        flags: i64,
        mode: i64,
    ) -> Result<Object<Stream>, StatusCode> {
        fs_status(file::open(path.as_bytes(), flags, mode)).map(Object)
    }

    /// `FileSystem.open`: a mode string such as `"r+"` plus permission bits; an unknown mode is
    /// invalid.
    fn msstd_fs_open(path: &str, flags: &str, mode: i64) -> Result<Object<Stream>, StatusCode> {
        let opened = file::flags_of_mode(flags.as_bytes())
            .ok_or_else(Fail::invalid)
            .and_then(|f| file::open(path.as_bytes(), i64::from(f), mode));
        fs_status(opened).map(Object)
    }

    /// The stream view of a file handle: the same handle, retained for the caller.
    fn msstd_fs_file_reader(h: ObjShare<Stream>) -> ObjShare<Stream> {
        h
    }

    /// The write-stream view of a file handle: the same handle, retained for the caller.
    fn msstd_fs_file_writer(h: ObjShare<Stream>) -> ObjShare<Stream> {
        h
    }

    /// `flags_of_mode` for `"r"`, `"r+"`, `"w"`, ... ; `STATUS_INVALID_INPUT` for an unknown mode.
    fn msstd_fs_open_flags(mode: &str) -> Result<i64, StatusCode> {
        fs_status(file::flags_of_mode(mode.as_bytes()).ok_or_else(Fail::invalid)).map(i64::from)
    }

    fn msstd_fs_file_read_at(
        h: ObjMut<Stream>,
        offset: i64,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<u8>, StatusCode> {
        let mut h = h;
        fs_status(h.read_at(offset, has_max.then_some(max)))
    }

    fn msstd_fs_file_read_file(
        h: ObjMut<Stream>,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<u8>, StatusCode> {
        let mut h = h;
        fs_status(lim(has_max, max).and_then(|m| h.read_file(m)))
    }

    fn msstd_fs_file_write_at(
        h: ObjMut<Stream>,
        offset: i64,
        data: &[u8],
    ) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.write_at(offset, data))
    }

    /// `sizes` is a `List[Int]`; the result is a `List[Bytes]`, one chunk per size.
    fn msstd_fs_file_read_vectors(
        h: ObjMut<Stream>,
        sizes: &[i64],
        offset: i64,
    ) -> Result<BytesList, StatusCode> {
        let mut h = h;
        fs_status(h.read_vectors(sizes, offset)).map(BytesList)
    }

    /// `buffers` is a `List[Bytes]`.
    fn msstd_fs_file_write_vectors(
        h: ObjMut<Stream>,
        buffers: Vec<&[u8]>,
        offset: i64,
    ) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.write_vectors(&buffers, offset))
    }

    fn msstd_fs_file_seek(
        h: ObjMut<Stream>,
        offset: i64,
        origin: i64,
    ) -> Result<i64, StatusCode> {
        let mut h = h;
        fs_status(h.seek(offset, origin))
    }

    fn msstd_fs_file_stat(h: ObjMut<Stream>) -> Result<InfoOut, StatusCode> {
        let mut h = h;
        fs_status(h.stat()).map(info_out)
    }

    fn msstd_fs_file_truncate(h: ObjMut<Stream>, size: i64) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.truncate(size))
    }

    fn msstd_fs_file_sync(h: ObjMut<Stream>) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.sync())
    }

    fn msstd_fs_file_data_sync(h: ObjMut<Stream>) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.data_sync())
    }

    fn msstd_fs_file_chmod(h: ObjMut<Stream>, mode: i64) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.chmod(mode))
    }

    fn msstd_fs_file_chown(h: ObjMut<Stream>, uid: i64, gid: i64) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.chown(uid, gid))
    }

    fn msstd_fs_file_set_times(
        h: ObjMut<Stream>,
        accessed_seconds: i64,
        accessed_nanos: i64,
        modified_seconds: i64,
        modified_nanos: i64,
    ) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.set_times(
            (accessed_seconds, accessed_nanos),
            (modified_seconds, modified_nanos),
        ))
    }

    /// The remaining lines as a `List[String]`.
    fn msstd_fs_file_read_lines(
        h: ObjMut<Stream>,
        max_bytes: i64,
        max_lines: i64,
    ) -> Result<TextList, StatusCode> {
        let mut h = h;
        fs_status(h.read_lines(max_bytes, max_lines)).map(TextList)
    }

    /// The path a file handle was opened with.
    fn msstd_fs_file_path(h: ObjRef<Stream>) -> Text {
        Text(h.name.to_vec())
    }

    fn msstd_fs_directory_open(path: &str) -> Result<Object<dir::Directory>, StatusCode> {
        fs_status(dir::Directory::open(path.as_bytes())).map(Object)
    }

    /// The next entry in native order; `STATUS_NONE` at the end.
    fn msstd_fs_directory_read(h: ObjMut<dir::Directory>) -> Result<EntryOut, StatusCode> {
        let mut h = h;
        let item = fs_status(h.read())?.ok_or(StatusCode(STATUS_NONE))?;
        Ok(entry_out(&item.name, item.directory, item.symlink))
    }

    fn msstd_fs_directory_close(h: ObjMut<dir::Directory>) -> () {
        let mut h = h;
        h.close()
    }

    fn msstd_fs_directory_path(h: ObjRef<dir::Directory>) -> Text {
        Text(h.path().to_vec())
    }

    /// Creates a temporary directory scoped to the handle (`close` removes the tree).
    fn msstd_fs_temporary_open(prefix: &str) -> Result<Object<dir::Temporary>, StatusCode> {
        fs_status(dir::Temporary::create(prefix.as_bytes())).map(Object)
    }

    fn msstd_fs_temporary_path(h: ObjRef<dir::Temporary>) -> Text {
        Text(h.path().to_vec())
    }

    /// Removes the tree; a failure carries its text for `msstd_fs_failure_message`.
    fn msstd_fs_temporary_close(h: ObjMut<dir::Temporary>) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.close())
    }

    /// `glob`: sorted relative matches as a `List[String]`.
    fn msstd_fs_glob(
        path: &str,
        pattern: &str,
        has_max: bool,
        max: i64,
    ) -> Result<TextList, StatusCode> {
        fs_status(lim(has_max, max).and_then(|m| walk::glob(path.as_bytes(), pattern.as_bytes(), m)))
            .map(TextList)
    }

    /// `copy_tree`: `entries` and `bytes` are budgets (pass `i64::MAX` for unlimited).
    fn msstd_fs_copy_tree(
        source: &str,
        destination: &str,
        replace: bool,
        entries: i64,
        bytes: i64,
    ) -> Result<(), StatusCode> {
        fs_status(walk::copy_tree(
            source.as_bytes(),
            destination.as_bytes(),
            replace,
            entries,
            bytes,
        ))
    }

    /// `copy`. `clone` is `"none"`, `"try"` or `"force"`; `filter` is null or a closure that
    /// answers whether to copy an entry.
    fn msstd_fs_copy(
        source: &str,
        destination: &str,
        flags: i64,
        clone: &str,
        has_entries: bool,
        entries: i64,
        has_bytes: bool,
        bytes: i64,
        filter: Option<PairFilter>,
    ) -> Result<(), StatusCode> {
        let Some(clone) = walk::Clone::parse(clone.as_bytes()) else {
            ms_rt::glue::record_failure(Vec::new());
            return Err(StatusCode(STATUS_INVALID_INPUT));
        };
        let (entries, bytes) = fs_status(lim(has_entries, entries).and_then(|e| Ok((e, lim(has_bytes, bytes)?))))?;
        let options = walk::CopyOptions {
            recursive: flags & 1 != 0,
            replace: flags & 2 != 0,
            error_on_exists: flags & 4 != 0,
            dereference: flags & 8 != 0,
            preserve: flags & 16 != 0,
            verbatim: flags & 32 != 0,
            clone,
            entries,
            bytes,
        };
        let mut call = |s: &[u8], d: &[u8]| filter.as_ref().is_some_and(|f| f.call(s, d));
        let f: Option<walk::Filter<'_>> = if filter.is_some() { Some(&mut call) } else { None };
        fs_status(walk::copy(source.as_bytes(), destination.as_bytes(), options, f))
    }

    /// `glob_entries`: `patterns` and `exclude` are `List[String]`; matches come back as a
    /// `List[PathEntry]`. `filter` is null or a closure over `(path, name, directory, symlink)`
    /// that answers whether to exclude the entry.
    fn msstd_fs_glob_entries(
        path: &str,
        patterns: Vec<&str>,
        exclude: Vec<&str>,
        follow_links: bool,
        has_max_entries: bool,
        max_entries: i64,
        has_max_results: bool,
        max_results: i64,
        filter: Option<EntryFilter>,
    ) -> Result<RecList<PathEntryOut>, StatusCode> {
        let (max_entries, max_results) = fs_status(lim(has_max_entries, max_entries)
            .and_then(|e| Ok((e, lim(has_max_results, max_results)?))))?;
        let patterns: Vec<&[u8]> = patterns.iter().map(|p| p.as_bytes()).collect();
        let exclude: Vec<&[u8]> = exclude.iter().map(|p| p.as_bytes()).collect();
        let options = walk::GlobOptions {
            patterns: &patterns,
            exclude: &exclude,
            follow_links,
            max_entries,
            max_results,
        };
        let mut call = |e: &walk::PathEntry| {
            filter
                .as_ref()
                .is_some_and(|f| f.call(&e.path, &e.name, e.directory, e.symlink))
        };
        let cb: Option<&mut dyn FnMut(&walk::PathEntry) -> bool> =
            if filter.is_some() { Some(&mut call) } else { None };
        let items = fs_status(walk::glob_entries(path.as_bytes(), &options, cb))?;
        Ok(RecList::new(items.iter().map(|e| PathEntryOut {
            path: Str::from_bytes(&e.path),
            name: Str::from_bytes(&e.name),
            directory: u8::from(e.directory),
            symlink: u8::from(e.symlink),
        })))
    }

    /// The `FileMode`/open-flag constants as parallel `names` (`List[String]`) and `values`
    /// (`List[Int]`) lists.
    fn msstd_fs_constants() -> out (TextList, IntList) {
        let table = consts::file_constants();
        (
            TextList(table.iter().map(|(k, _)| k.as_bytes().to_vec()).collect()),
            IntList(table.iter().map(|(_, v)| *v).collect()),
        )
    }

    /// A polling watcher (`interval_ns` > 0); `max` bounds tracked paths.
    fn msstd_fs_watch(
        path: &str,
        recursive: bool,
        interval_ns: i64,
        has_max: bool,
        max: i64,
    ) -> Result<Object<watch::Watcher>, StatusCode> {
        let poll = lim(has_max, max)
            .and_then(|m| watch::Poll::new(path.as_bytes(), recursive, interval_ns, m));
        fs_status(poll).map(|p| Object(watch::Watcher::poll(p)))
    }

    /// A native (inotify) watcher; `overflow` is `error` or `ignore`.
    fn msstd_fs_watch_native(
        path: &str,
        recursive: bool,
        has_max: bool,
        max: i64,
        has_events: bool,
        events: i64,
        overflow: &str,
    ) -> Result<Object<watch::Watcher>, StatusCode> {
        let native = lim(has_max, max).and_then(|m| {
            let e = if has_events { events } else { 128 };
            watch::Native::new(
                path.as_bytes(),
                recursive,
                if has_max { m } else { i64::MAX },
                e,
                overflow.as_bytes(),
            )
        });
        fs_status(native).map(|n| Object(watch::Watcher::native(n)))
    }

    /// Waits for activity. The results are a `List[String]` of paths and one byte per event
    /// (1 `rename`, 0 `change`). `STATUS_CLOSED` after close, `STATUS_LIMIT_EXCEEDED` on overflow.
    fn msstd_fs_watch_next(
        h: ObjMut<watch::Watcher>,
    ) -> Result<(TextList, Vec<u8>), StatusCode> {
        let mut h = h;
        let events = fs_status(h.wait())?;
        Ok((
            TextList(events.iter().map(|e| e.path.clone()).collect()),
            events.iter().map(|e| u8::from(e.rename)).collect(),
        ))
    }

    fn msstd_fs_watch_close(h: ObjMut<watch::Watcher>) -> () {
        let mut h = h;
        h.close()
    }
}
