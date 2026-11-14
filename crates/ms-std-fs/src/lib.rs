//! `@std/fs` natives for path-based operations. Symbols are `msstd_fs_<name>`.
//!
//! Paths arrive as strings; fallible functions return a `STATUS_*` code (`0` ok) and write results
//! only on success. For `STATUS_FAILED` the diagnostic text is available from
//! the `err` out string of the failing call. `FileInfo` is flattened into
//! [`InfoOut`]; optional limits are a present flag plus an `i64`.
//! ms: domain filesystem
// `libc::statfs` field widths differ per target, so the portable casts look redundant on Linux.
#![allow(clippy::unnecessary_cast)]
#![recursion_limit = "256"]

extern crate alloc;

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
    BytesList, EntryFilter, ErrOut, Has, ObjMut, ObjRef, Object, PairFilter, StatusCode, Str, Text,
    TextList, TypeList, abi_type, native,
};
use ms_rt_abi::{STATUS_FAILED, STATUS_INVALID_INPUT, STATUS_NONE};
use stream::Stream;

/// Raises a pending cancel once the failing operation's frames have returned and dropped what
/// they held. Runs only at the FFI boundary, never on a pool thread.
/// The failure's text is dropped first: the jump skips destructors.
fn raise_cancel(message: &mut Option<Vec<u8>>) {
    if !ms_rt::glue::pool::on_pool_thread() && ms_rt::glue::cancel_pending() {
        drop(message.take());
        ms_rt::glue::cancelled();
    }
}

/// A filesystem result as a status: a failure stores its text in `err`, which the caller reads
/// for `STATUS_FAILED` (so it is always written for that status).
pub fn fs_status<T>(r: Res<T>, err: &ErrOut) -> Result<T, StatusCode> {
    r.map_err(
        |Fail {
             status,
             mut message,
         }| {
            raise_cancel(&mut message);
            if status == STATUS_FAILED {
                err.set_bytes(&message.unwrap_or_default());
            }
            StatusCode(status)
        },
    )
}

/// Like [`fs_status`], naming `path` for every failure but `STATUS_FAILED`, which has its own text:
/// the message reads `filesystem: <failure>: <path>`.
pub fn fs_status_at<T>(path: &[u8], r: Res<T>, err: &ErrOut) -> Result<T, StatusCode> {
    r.map_err(
        |Fail {
             status,
             mut message,
         }| {
            raise_cancel(&mut message);
            if status == STATUS_FAILED {
                err.set_bytes(&message.unwrap_or_default());
            } else {
                err.set_bytes(path);
            }
            StatusCode(status)
        },
    )
}

/// Like [`fs_status_at`] for a two-path operation: the detail reads `<source> -> <destination>`.
pub fn fs_status_pair<T>(
    source: &[u8],
    destination: &[u8],
    r: Res<T>,
    err: &ErrOut,
) -> Result<T, StatusCode> {
    let both = [source, b" -> ", destination].concat();
    fs_status_at(&both, r, err)
}

/// A decoded optional size limit.
fn lim(has: bool, v: i64) -> Res<i64> {
    ops::limit(has, v)
}

abi_type! {
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

abi_type! {
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

abi_type! {
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

abi_type! {
    /// A `Timestamp` at the layout the compiler gives the native time type.
    #[derive(Clone, Copy)]
    pub struct Timestamp {
        pub seconds: i64,
        pub nanos: i64,
    }
}

abi_type! {
    /// One `FileEvent`: the path, then `rename` or `change`.
    pub struct EventOut {
        pub path: Str,
        pub kind: Str,
    }
}

abi_type! {
    /// One `PathEntry`: the path, then the nested `DirectoryEntry`'s name and two flag bytes.
    pub struct PathEntryOut {
        pub path: Str,
        pub name: Str,
        pub directory: u8,
        pub symlink: u8,
    }
}

native! {
    /// Reads a whole file as bytes.
    fn msstd_fs_read_file(path: &str, has_max: Has, max: i64; err: ErrOut) -> Result<Vec<u8>, StatusCode> {
        fs_status_at(path.as_bytes(), lim(*has_max, max).and_then(|m| ops::read_file(path.as_bytes(), m)), &err)
    }

    /// Writes bytes to a file (`replace` truncates, otherwise the file must not exist).
    fn msstd_fs_write_file(path: &str, data: &[u8], replace: bool; err: ErrOut) -> Result<(), StatusCode> {
        fs_status_at(path.as_bytes(), ops::write_file(path.as_bytes(), data, replace), &err)
    }

    /// Takes an admission permit for copying `bytes` for a pool job, parking while the pool is
    /// full; true when one is held and `msstd_fs_release` must follow.
    safe fn msstd_fs_admit(bytes: i64) -> bool {
        // Nothing is held here, so the cancel is raised at once.
        match ms_rt::glue::pool::admit(usize::try_from(bytes).unwrap_or(0)) {
            Ok(held) => held,
            Err(_) => ms_rt::glue::cancelled(),
        }
    }

    /// Returns a permit from `msstd_fs_admit`.
    safe fn msstd_fs_release() -> () {
        ms_rt::glue::pool::release()
    }

    fn msstd_fs_append_file(path: &str, data: &[u8]; err: ErrOut) -> Result<(), StatusCode> {
        fs_status_at(path.as_bytes(), ops::append_file(path.as_bytes(), data), &err)
    }

    /// `follow` resolves a final symlink (`stat`), otherwise it reports the link (`lstat`).
    fn msstd_fs_stat(path: &str, follow: bool; err: ErrOut) -> Result<InfoOut, StatusCode> {
        fs_status_at(path.as_bytes(), ops::stat(path.as_bytes(), follow), &err).map(info_out)
    }

    /// Lists a directory sorted by name into a `List[DirectoryEntry]`.
    fn msstd_fs_list(
        path: &str,
        has_limit: Has,
        limit: i64; err: ErrOut) -> Result<TypeList<EntryOut>, StatusCode> {
        let entries = fs_status_at(path.as_bytes(), lim(*has_limit, limit).and_then(|m| ops::list(path.as_bytes(), m)), &err)?;
        Ok(TypeList::new(entries.iter().map(|e| entry_out(&e.name, e.directory, e.symlink))))
    }

    fn msstd_fs_create_directory(path: &str, recursive: bool; err: ErrOut) -> Result<(), StatusCode> {
        fs_status_at(path.as_bytes(), ops::create_directory(path.as_bytes(), recursive), &err)
    }

    fn msstd_fs_remove(path: &str, recursive: bool; err: ErrOut) -> Result<(), StatusCode> {
        fs_status_at(path.as_bytes(), ops::remove(path.as_bytes(), recursive), &err)
    }

    fn msstd_fs_rename(source: &str, destination: &str; err: ErrOut) -> Result<(), StatusCode> {
        fs_status_pair(source.as_bytes(), destination.as_bytes(), ops::rename(source.as_bytes(), destination.as_bytes()), &err)
    }

    fn msstd_fs_read_link(path: &str; err: ErrOut) -> Result<Text, StatusCode> {
        fs_status_at(path.as_bytes(), ops::read_link(path.as_bytes()), &err).map(Text)
    }

    fn msstd_fs_create_link(path: &str, target: &str; err: ErrOut) -> Result<(), StatusCode> {
        fs_status_at(path.as_bytes(), ops::create_link(path.as_bytes(), target.as_bytes()), &err)
    }

    fn msstd_fs_hard_link(source: &str, destination: &str; err: ErrOut) -> Result<(), StatusCode> {
        fs_status(ops::hard_link(source.as_bytes(), destination.as_bytes()), &err)
    }

    fn msstd_fs_canonicalize(path: &str; err: ErrOut) -> Result<Text, StatusCode> {
        fs_status_at(path.as_bytes(), ops::canonicalize(path.as_bytes()), &err).map(Text)
    }

    safe fn msstd_fs_temporary_root() -> Text {
        Text(ops::temporary_root())
    }

    fn msstd_fs_temporary_directory(pattern: &str; err: ErrOut) -> Result<Text, StatusCode> {
        fs_status(ops::temporary_directory(pattern.as_bytes()), &err).map(Text)
    }

    fn msstd_fs_stat_filesystem(path: &str; err: ErrOut) -> Result<FsOut, StatusCode> {
        fs_status_at(path.as_bytes(), ops::stat_filesystem(path.as_bytes()), &err).map(|s| FsOut {
            kind: s.kind,
            block_size: s.block_size,
            blocks: s.blocks,
            blocks_free: s.blocks_free,
            blocks_available: s.blocks_available,
            files: s.files,
            files_free: s.files_free,
        })
    }

    fn msstd_fs_chmod(path: &str, mode: i64, follow: bool; err: ErrOut) -> Result<(), StatusCode> {
        let p = path.as_bytes();
        fs_status_at(path.as_bytes(), if follow { ops::chmod(p, mode) } else { ops::chmod_link(p, mode) }, &err)
    }

    fn msstd_fs_access(path: &str, mode: i64; err: ErrOut) -> Result<(), StatusCode> {
        fs_status_at(path.as_bytes(), ops::access(path.as_bytes(), mode), &err)
    }

    fn msstd_fs_chown(path: &str, uid: i64, gid: i64, follow: bool; err: ErrOut) -> Result<(), StatusCode> {
        fs_status_at(path.as_bytes(), ops::chown(path.as_bytes(), uid, gid, follow), &err)
    }

    fn msstd_fs_truncate(path: &str, size: i64; err: ErrOut) -> Result<(), StatusCode> {
        fs_status_at(path.as_bytes(), ops::truncate(path.as_bytes(), size), &err)
    }

    fn msstd_fs_set_times(
        path: &str,
        accessed: &Timestamp,
        modified: &Timestamp,
        follow: bool; err: ErrOut) -> Result<(), StatusCode> {
        fs_status_at(path.as_bytes(), ops::set_times(
            path.as_bytes(),
            (accessed.seconds, accessed.nanos),
            (modified.seconds, modified.nanos),
            follow,
        ), &err)
    }

    // ---- File handles, directory cursors, temporary directories, glob and copy ----

    /// `FileSystem.open`: a mode string such as `"r+"` plus permission bits; an unknown mode is
    /// invalid.
    fn msstd_fs_open(path: &str, flags: &str, mode: i64; err: ErrOut) -> Result<Object<Stream>, StatusCode> {
        let opened = file::flags_of_mode(flags.as_bytes())
            .ok_or_else(Fail::invalid)
            .and_then(|f| file::open(path.as_bytes(), i64::from(f), mode));
        fs_status_at(path.as_bytes(), opened, &err).map(Object)
    }

    /// `FileHandle.clone`: a second handle over a duplicate of the descriptor.
    fn msstd_fs_file_clone(h: ObjRef<Stream>; err: ErrOut) -> Result<Object<Stream>, StatusCode> {
        fs_status(file::duplicate(&h), &err).map(Object)
    }

    fn msstd_fs_file_read_at(
        h: ObjMut<Stream>,
        offset: i64,
        has_max: Has,
        max: i64; err: ErrOut) -> Result<Vec<u8>, StatusCode> {
        let mut h = h;
        fs_status(h.read_at(offset, has_max.then_some(max)), &err)
    }

    fn msstd_fs_file_read_file(
        h: ObjMut<Stream>,
        has_max: Has,
        max: i64; err: ErrOut) -> Result<Vec<u8>, StatusCode> {
        let mut h = h;
        fs_status(lim(*has_max, max).and_then(|m| h.read_file(m)), &err)
    }

    fn msstd_fs_file_write_at(
        h: ObjMut<Stream>,
        offset: i64,
        data: &[u8]; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.write_at(offset, data), &err)
    }

    /// `sizes` is a `List[Int]`; the result is a `List[Bytes]`, one chunk per size.
    fn msstd_fs_file_read_vectors(
        h: ObjMut<Stream>,
        sizes: &[i64],
        offset: i64; err: ErrOut) -> Result<BytesList, StatusCode> {
        let mut h = h;
        fs_status(h.read_vectors(sizes, offset), &err).map(BytesList)
    }

    /// `buffers` is a `List[Bytes]`.
    fn msstd_fs_file_write_vectors(
        h: ObjMut<Stream>,
        buffers: Vec<&[u8]>,
        offset: i64; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.write_vectors(&buffers, offset), &err)
    }

    fn msstd_fs_file_seek(
        h: ObjMut<Stream>,
        offset: i64,
        origin: i64; err: ErrOut) -> Result<i64, StatusCode> {
        let mut h = h;
        fs_status(h.seek(offset, origin), &err)
    }

    fn msstd_fs_file_stat(h: ObjMut<Stream>; err: ErrOut) -> Result<InfoOut, StatusCode> {
        let mut h = h;
        fs_status(h.stat(), &err).map(info_out)
    }

    fn msstd_fs_file_truncate(h: ObjMut<Stream>, size: i64; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.truncate(size), &err)
    }

    fn msstd_fs_file_sync(h: ObjMut<Stream>; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.sync(), &err)
    }

    fn msstd_fs_file_data_sync(h: ObjMut<Stream>; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.data_sync(), &err)
    }

    fn msstd_fs_file_try_lock(h: ObjMut<Stream>, exclusive: bool; err: ErrOut) -> Result<i64, StatusCode> {
        let mut h = h;
        fs_status(h.try_lock(exclusive), &err).map(i64::from)
    }

    fn msstd_fs_file_unlock(h: ObjMut<Stream>; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.unlock(), &err)
    }

    fn msstd_fs_file_chmod(h: ObjMut<Stream>, mode: i64; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.chmod(mode), &err)
    }

    fn msstd_fs_file_chown(h: ObjMut<Stream>, uid: i64, gid: i64; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.chown(uid, gid), &err)
    }

    fn msstd_fs_file_set_times(
        h: ObjMut<Stream>,
        accessed: &Timestamp,
        modified: &Timestamp; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.set_times(
            (accessed.seconds, accessed.nanos),
            (modified.seconds, modified.nanos),
        ), &err)
    }

    /// The remaining lines as a `List[String]`.
    fn msstd_fs_file_read_lines(
        h: ObjMut<Stream>,
        max_bytes: i64,
        max_lines: i64; err: ErrOut) -> Result<TextList, StatusCode> {
        let mut h = h;
        fs_status(h.read_lines(max_bytes, max_lines), &err).map(TextList)
    }

    fn msstd_fs_directory_open(path: &str; err: ErrOut) -> Result<Object<dir::Directory>, StatusCode> {
        fs_status_at(path.as_bytes(), dir::Directory::open(path.as_bytes()), &err).map(Object)
    }

    /// The next entry in native order; `STATUS_NONE` at the end.
    fn msstd_fs_directory_read(h: ObjMut<dir::Directory>; err: ErrOut) -> Result<EntryOut, StatusCode> {
        let mut h = h;
        let item = fs_status(h.read(), &err)?.ok_or(StatusCode(STATUS_NONE))?;
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
    fn msstd_fs_temporary_open(prefix: &str; err: ErrOut) -> Result<Object<dir::Temporary>, StatusCode> {
        fs_status(dir::Temporary::create(prefix.as_bytes()), &err).map(Object)
    }

    fn msstd_fs_temporary_path(h: ObjRef<dir::Temporary>) -> Text {
        Text(h.path().to_vec())
    }

    /// Removes the tree; a failure carries its text in `err`.
    fn msstd_fs_temporary_close(h: ObjMut<dir::Temporary>; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        fs_status(h.close(), &err)
    }

    /// `copy`. `clone` is `"none"`, `"try"` or `"force"`; `filter` is null or a closure that
    /// answers whether to copy an entry.
    fn msstd_fs_copy(
        source: &str,
        destination: &str,
        flags: i64,
        clone: &str,
        has_entries: Has,
        entries: i64,
        has_bytes: Has,
        bytes: i64,
        filter: Option<PairFilter>; err: ErrOut) -> Result<(), StatusCode> {
        let Some(clone) = walk::Clone::parse(clone.as_bytes()) else {
            return Err(StatusCode(STATUS_INVALID_INPUT));
        };
        let (entries, bytes) = fs_status(lim(*has_entries, entries).and_then(|e| Ok((e, lim(*has_bytes, bytes)?))), &err)?;
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
        fs_status_pair(source.as_bytes(), destination.as_bytes(), walk::copy(source.as_bytes(), destination.as_bytes(), options, f), &err)
    }

    /// `glob_entries`: `patterns` and `exclude` are `List[String]`; matches come back as a
    /// `List[PathEntry]`. `filter` is null or a closure over `(path, name, directory, symlink)`
    /// that answers whether to exclude the entry.
    fn msstd_fs_glob_entries(
        path: &str,
        patterns: Vec<&str>,
        exclude: Vec<&str>,
        follow_links: bool,
        has_max_entries: Has,
        max_entries: i64,
        has_max_results: Has,
        max_results: i64,
        filter: Option<EntryFilter>; err: ErrOut) -> Result<TypeList<PathEntryOut>, StatusCode> {
        let (max_entries, max_results) = fs_status_at(path.as_bytes(), lim(*has_max_entries, max_entries)
            .and_then(|e| Ok((e, lim(*has_max_results, max_results)?))), &err)?;
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
        let items = fs_status_at(path.as_bytes(), walk::glob_entries(path.as_bytes(), &options, cb), &err)?;
        Ok(TypeList::new(items.iter().map(|e| PathEntryOut {
            path: Str::from_bytes(&e.path),
            name: Str::from_bytes(&e.name),
            directory: u8::from(e.directory),
            symlink: u8::from(e.symlink),
        })))
    }

    /// A polling watcher (`interval_ns` > 0); `max` bounds tracked paths.
    fn msstd_fs_watch(
        path: &str,
        recursive: bool,
        interval_ns: i64,
        has_max: Has,
        max: i64; err: ErrOut) -> Result<Object<watch::Watcher>, StatusCode> {
        let poll = lim(*has_max, max)
            .and_then(|m| watch::Poll::new(path.as_bytes(), recursive, interval_ns, m));
        fs_status_at(path.as_bytes(), poll, &err).map(|p| Object(watch::Watcher::poll(p)))
    }

    /// A native (inotify) watcher; `overflow` is `error` or `ignore`.
    fn msstd_fs_watch_native(
        path: &str,
        recursive: bool,
        has_max: Has,
        max: i64,
        has_events: Has,
        events: i64,
        overflow: &str; err: ErrOut) -> Result<Object<watch::Watcher>, StatusCode> {
        let native = lim(*has_max, max).and_then(|m| {
            let e = if *has_events { events } else { 128 };
            watch::Native::new(
                path.as_bytes(),
                recursive,
                if *has_max { m } else { i64::MAX },
                e,
                overflow.as_bytes(),
            )
        });
        fs_status_at(path.as_bytes(), native, &err).map(|n| Object(watch::Watcher::native(n)))
    }

    /// Waits for activity and returns the `List[FileEvent]`. `STATUS_CLOSED` after close,
    /// `STATUS_LIMIT_EXCEEDED` on overflow.
    fn msstd_fs_watch_next(
        h: ObjMut<watch::Watcher>; err: ErrOut) -> Result<TypeList<EventOut>, StatusCode> {
        let mut h = h;
        let events = fs_status(h.wait(), &err)?;
        Ok(TypeList::new(events.iter().map(|e| EventOut {
            path: Str::from_bytes(&e.path),
            kind: Str::new(if e.rename { "rename" } else { "change" }),
        })))
    }

    fn msstd_fs_watch_close(h: ObjMut<watch::Watcher>) -> () {
        let mut h = h;
        h.close()
    }
}
