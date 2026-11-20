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

pub mod err;
pub mod file;
pub mod ops;
pub mod path;
#[allow(unsafe_code)] // the runtime flush hook
pub mod stream;
#[allow(unsafe_code)] // libc and Win32 calls
pub mod sys;
#[allow(unsafe_code)] // inotify
pub mod watch;

use alloc::vec::Vec;
use err::{Fail, Res};
use ms_rt::ffi::{
    BytesList, ErrOut, Has, ObjMut, ObjRef, Object, StatusCode, Str, TextList, TypeList, abi_type,
    native,
};
use ms_rt_abi::STATUS_FAILED;
use stream::Stream;

/// Delivers a pending cancel once the failing operation's frames have returned and dropped what
/// they held. Runs only at the FFI boundary, never on a pool thread; the native then returns its
/// status as usual. The failure's text is dropped first while a cancel can still jump.
fn raise_cancel(message: &mut Option<Vec<u8>>) {
    if !ms_rt::glue::pool::on_pool_thread() && ms_rt::glue::cancel_pending() {
        drop(message.take());
        ms_rt::glue::cancel_return();
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

native! {
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
