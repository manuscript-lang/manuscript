//! `@std/fs` natives for path-based operations. Symbols are `msstd_fs_<name>`.
//!
//! Paths arrive as strings; fallible functions return a `STATUS_*` code (`0` ok) and write results
//! only on success. For `STATUS_FAILED` the Go-style diagnostic text is available from
//! `msstd_fs_failure_message` until the next fallible call. `FileInfo` is flattened into
//! [`InfoOut`]; optional limits are a present flag plus an `i64`.
#![no_std]
// The exports below are the C ABI compiled code links against.
#![allow(unsafe_code)]
#![allow(clippy::missing_safety_doc)]
// `libc::stat` field widths differ per target, so the portable casts look redundant on Linux.
#![allow(clippy::unnecessary_cast)]

extern crate alloc;

pub mod consts;
pub mod dir;
pub mod err;
pub mod file;
pub mod ops;
pub mod path;
pub mod stream;
pub mod sys;
pub mod walk;
pub mod watch;

use alloc::vec::Vec;
use err::{Fail, Res};
use ms_rt_abi::{Closure, STATUS_OK, StrObj, VecVal};
use ms_std_rt::{Handle, new_handle, new_string, str_bytes, write_bytes, write_string_list};

fn finish<T>(r: Res<T>, ok: impl FnOnce(T)) -> u8 {
    match r {
        Ok(v) => {
            ok(v);
            STATUS_OK
        }
        Err(Fail { status, message }) => {
            ms_std_rt::record_failure(message.unwrap_or_default());
            status
        }
    }
}

/// The text describing the last `STATUS_FAILED` result (a fresh string).
#[unsafe(no_mangle)]
pub extern "C" fn msstd_fs_failure_message() -> *mut StrObj {
    ms_std_rt::failure_message()
}

/// A decoded optional size limit (`has` is non-zero when present).
fn lim(has: u8, v: i64) -> Res<i64> {
    ops::limit(has != 0, v)
}

/// Flattened `FileInfo`: a string followed by `i64` words only, so compiled code reads it as a
/// record. Times are `(seconds, nanoseconds)`; `created_present` says whether the creation time
/// exists on this host. `kinds` is the `KIND_*` bit set from `ops`; unsigned host counters carry
/// their bits (`exact` reads them back as unsigned).
#[repr(C)]
pub struct InfoOut {
    pub name: *mut StrObj,
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

fn info_out(i: ops::Info, out: *mut InfoOut) {
    let (cs, cn) = i.created.unwrap_or((0, 0));
    // SAFETY: callers pass a writable `InfoOut`.
    unsafe {
        out.write(InfoOut {
            name: new_string(&i.name),
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
        })
    }
}

/// Reads a whole file as bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_read_file(
    path: *const StrObj,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = lim(has_max, max).and_then(|m| ops::read_file(unsafe { str_bytes(path) }, m));
    // SAFETY: `out` is writable.
    finish(r, |b| unsafe { write_bytes(&b, out) })
}

/// Writes bytes to a file (`replace` truncates, otherwise the file must not exist).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_write_file(
    path: *const StrObj,
    data: *const VecVal,
    replace: u8,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = ops::write_file(
        unsafe { str_bytes(path) },
        unsafe { ms_std_rt::vec_bytes(data) },
        replace != 0,
    );
    finish(r, |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_append_file(path: *const StrObj, data: *const VecVal) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = ops::append_file(unsafe { str_bytes(path) }, unsafe {
        ms_std_rt::vec_bytes(data)
    });
    finish(r, |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_copy_file(
    source: *const StrObj,
    destination: *const StrObj,
    replace: u8,
    has_max: u8,
    max: i64,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let (source, destination) = unsafe { (str_bytes(source), str_bytes(destination)) };
    let r = lim(has_max, max).and_then(|m| ops::copy_file(source, destination, replace != 0, m));
    finish(r, |()| ())
}

/// `follow` non-zero resolves a final symlink (`stat`), zero reports the link (`lstat`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_stat(path: *const StrObj, follow: u8, out: *mut InfoOut) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = ops::stat(unsafe { str_bytes(path) }, follow != 0);
    finish(r, |i| info_out(i, out))
}

/// One `DirectoryEntry` as compiled code lays the record out: the name, then two flag bytes.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct EntryOut {
    pub name: *mut StrObj,
    pub directory: u8,
    pub symlink: u8,
}

fn entry_out(e: &ops::Entry) -> EntryOut {
    EntryOut {
        name: new_string(&e.name),
        directory: e.directory as u8,
        symlink: e.symlink as u8,
    }
}

/// Lists a directory sorted by name into a `List[DirectoryEntry]`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_list(
    path: *const StrObj,
    has_limit: u8,
    limit: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = lim(has_limit, limit).and_then(|m| ops::list(unsafe { str_bytes(path) }, m));
    finish(r, |entries| {
        let items: Vec<EntryOut> = entries.iter().map(entry_out).collect();
        // SAFETY: `out` is writable.
        unsafe { ms_std_rt::write_list(&items, out) }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_create_directory(path: *const StrObj, recursive: u8) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(
        ops::create_directory(unsafe { str_bytes(path) }, recursive != 0),
        |()| (),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_remove(path: *const StrObj, recursive: u8) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(
        ops::remove(unsafe { str_bytes(path) }, recursive != 0),
        |()| (),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_rename(source: *const StrObj, destination: *const StrObj) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(
        ops::rename(unsafe { str_bytes(source) }, unsafe {
            str_bytes(destination)
        }),
        |()| (),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_read_link(path: *const StrObj, out: *mut *mut StrObj) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(ops::read_link(unsafe { str_bytes(path) }), |t| unsafe {
        *out = new_string(&t)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_create_link(path: *const StrObj, target: *const StrObj) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(
        ops::create_link(unsafe { str_bytes(path) }, unsafe { str_bytes(target) }),
        |()| (),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_hard_link(
    source: *const StrObj,
    destination: *const StrObj,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(
        ops::hard_link(unsafe { str_bytes(source) }, unsafe {
            str_bytes(destination)
        }),
        |()| (),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_canonicalize(path: *const StrObj, out: *mut *mut StrObj) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(ops::canonicalize(unsafe { str_bytes(path) }), |s| unsafe {
        *out = new_string(&s)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_fs_temporary_root() -> *mut StrObj {
    new_string(&ops::temporary_root())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_temporary_directory(
    pattern: *const StrObj,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(
        ops::temporary_directory(unsafe { str_bytes(pattern) }),
        |s| unsafe { *out = new_string(&s) },
    )
}

/// Flattened filesystem status: type id, block size, blocks, free, available, files, free files.
#[repr(C)]
pub struct FsOut {
    pub kind: i64,
    pub block_size: i64,
    pub blocks: i64,
    pub blocks_free: i64,
    pub blocks_available: i64,
    pub files: i64,
    pub files_free: i64,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_stat_filesystem(path: *const StrObj, out: *mut FsOut) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(
        ops::stat_filesystem(unsafe { str_bytes(path) }),
        |s| unsafe {
            out.write(FsOut {
                kind: s.kind,
                block_size: s.block_size,
                blocks: s.blocks,
                blocks_free: s.blocks_free,
                blocks_available: s.blocks_available,
                files: s.files,
                files_free: s.files_free,
            })
        },
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_chmod(path: *const StrObj, mode: i64, follow: u8) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let p = unsafe { str_bytes(path) };
    finish(
        if follow != 0 {
            ops::chmod(p, mode)
        } else {
            ops::chmod_link(p, mode)
        },
        |()| (),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_access(path: *const StrObj, mode: i64) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(ops::access(unsafe { str_bytes(path) }, mode), |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_chown(path: *const StrObj, uid: i64, gid: i64, follow: u8) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(
        ops::chown(unsafe { str_bytes(path) }, uid, gid, follow != 0),
        |()| (),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_truncate(path: *const StrObj, size: i64) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(ops::truncate(unsafe { str_bytes(path) }, size), |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_set_times(
    path: *const StrObj,
    accessed_seconds: i64,
    accessed_nanos: i64,
    modified_seconds: i64,
    modified_nanos: i64,
    follow: u8,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = ops::set_times(
        unsafe { str_bytes(path) },
        (accessed_seconds, accessed_nanos),
        (modified_seconds, modified_nanos),
        follow != 0,
    );
    finish(r, |()| ())
}

// ---------------------------------------------------------------------------
// File handles, directory cursors, temporary directories, glob and copy
// ---------------------------------------------------------------------------

type FileHandle = Handle<stream::Stream>;

/// Opens a file handle. The same handle serves the `msstd_io_*` stream exports.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_open(
    path: *const StrObj,
    flags: i64,
    mode: i64,
    out: *mut *mut FileHandle,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = file::open(unsafe { str_bytes(path) }, flags, mode);
    // SAFETY: handles and output pointers follow the ABI contract.
    finish(r, |s| unsafe { *out = new_handle(s) })
}

/// `FileSystem.open`: a mode string such as `"r+"` plus permission bits; an unknown mode is invalid.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_open(
    path: *const StrObj,
    flags: *const StrObj,
    mode: i64,
    out: *mut *mut FileHandle,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let (path, flags) = unsafe { (str_bytes(path), str_bytes(flags)) };
    let r = file::flags_of_mode(flags)
        .ok_or_else(Fail::invalid)
        .and_then(|f| file::open(path, f as i64, mode));
    // SAFETY: handles and output pointers follow the ABI contract.
    finish(r, |s| unsafe { *out = new_handle(s) })
}

/// The stream view of a file handle: the same handle, retained for the caller.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_reader(h: *mut FileHandle) -> *mut Handle<stream::Stream> {
    // SAFETY: `h` is a live handle; the caller receives its own reference.
    unsafe { ms_std_rt::retain(h.cast()) };
    h
}

/// The write-stream view of a file handle: the same handle, retained for the caller.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_writer(h: *mut FileHandle) -> *mut Handle<stream::Stream> {
    // SAFETY: `h` is a live handle; the caller receives its own reference.
    unsafe { ms_std_rt::retain(h.cast()) };
    h
}

/// `flags_of_mode` for `"r"`, `"r+"`, `"w"`, ... ; `STATUS_INVALID_INPUT` for an unknown mode.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_open_flags(mode: *const StrObj, out: *mut i64) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = file::flags_of_mode(unsafe { str_bytes(mode) }).ok_or_else(Fail::invalid);
    // SAFETY: handles and output pointers follow the ABI contract.
    finish(r, |f| unsafe { *out = f as i64 })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_read_at(
    h: *mut FileHandle,
    offset: i64,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `h` is a live file handle; `out` is writable.
    let r = unsafe { (*h).value.read_at(offset, (has_max != 0).then_some(max)) };
    // SAFETY: handles and output pointers follow the ABI contract.
    finish(r, |b| unsafe { write_bytes(&b, out) })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_read_file(
    h: *mut FileHandle,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `h` is a live file handle; `out` is writable.
    let r = lim(has_max, max).and_then(|m| unsafe { (*h).value.read_file(m) });
    // SAFETY: handles and output pointers follow the ABI contract.
    finish(r, |b| unsafe { write_bytes(&b, out) })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_write_at(
    h: *mut FileHandle,
    offset: i64,
    data: *const VecVal,
) -> u8 {
    // SAFETY: `h` is a live file handle; `data` is a byte list.
    let r = unsafe { (*h).value.write_at(offset, ms_std_rt::vec_bytes(data)) };
    finish(r, |()| ())
}

/// `sizes` is a `List[Int]`; `out` receives a `List[Bytes]`, one chunk per size.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_read_vectors(
    h: *mut FileHandle,
    sizes: *const VecVal,
    offset: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `h` is a live file handle; `sizes` is an Int list.
    let r = unsafe {
        (*h).value
            .read_vectors(ms_std_rt::list_slice::<i64>(sizes), offset)
    };
    finish(r, |chunks| {
        let items: Vec<VecVal> = chunks
            .iter()
            .map(|c| {
                let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
                // SAFETY: `write_bytes` initialises the whole `VecVal`.
                unsafe {
                    write_bytes(c, v.as_mut_ptr());
                    v.assume_init_read()
                }
            })
            .collect();
        // SAFETY: `out` is writable.
        unsafe { ms_std_rt::write_list(&items, out) }
    })
}

/// `buffers` is a `List[Bytes]`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_write_vectors(
    h: *mut FileHandle,
    buffers: *const VecVal,
    offset: i64,
) -> u8 {
    // SAFETY: `h` is a live file handle; `buffers` is a list of byte lists.
    let r = unsafe {
        let parts: Vec<&[u8]> = ms_std_rt::list_slice::<VecVal>(buffers)
            .iter()
            .map(|v| ms_std_rt::vec_bytes(v))
            .collect();
        (*h).value.write_vectors(&parts, offset)
    };
    finish(r, |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_seek(
    h: *mut FileHandle,
    offset: i64,
    origin: i64,
    out: *mut i64,
) -> u8 {
    // SAFETY: `h` is a live file handle; `out` is writable.
    let r = unsafe { (*h).value.seek(offset, origin) };
    // SAFETY: handles and output pointers follow the ABI contract.
    finish(r, |p| unsafe { *out = p })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_stat(h: *mut FileHandle, out: *mut InfoOut) -> u8 {
    // SAFETY: `h` is a live file handle.
    let r = unsafe { (*h).value.stat() };
    finish(r, |i| info_out(i, out))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_truncate(h: *mut FileHandle, size: i64) -> u8 {
    // SAFETY: `h` is a live file handle.
    finish(unsafe { (*h).value.truncate(size) }, |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_sync(h: *mut FileHandle) -> u8 {
    // SAFETY: `h` is a live file handle.
    finish(unsafe { (*h).value.sync() }, |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_data_sync(h: *mut FileHandle) -> u8 {
    // SAFETY: `h` is a live file handle.
    finish(unsafe { (*h).value.data_sync() }, |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_chmod(h: *mut FileHandle, mode: i64) -> u8 {
    // SAFETY: `h` is a live file handle.
    finish(unsafe { (*h).value.chmod(mode) }, |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_chown(h: *mut FileHandle, uid: i64, gid: i64) -> u8 {
    // SAFETY: `h` is a live file handle.
    finish(unsafe { (*h).value.chown(uid, gid) }, |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_set_times(
    h: *mut FileHandle,
    accessed_seconds: i64,
    accessed_nanos: i64,
    modified_seconds: i64,
    modified_nanos: i64,
) -> u8 {
    // SAFETY: `h` is a live file handle.
    let r = unsafe {
        (*h).value.set_times(
            (accessed_seconds, accessed_nanos),
            (modified_seconds, modified_nanos),
        )
    };
    finish(r, |()| ())
}

/// The remaining lines as a `List[String]`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_read_lines(
    h: *mut FileHandle,
    max_bytes: i64,
    max_lines: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `h` is a live file handle; `out` is writable.
    let r = unsafe { (*h).value.read_lines(max_bytes, max_lines) };
    finish(r, |lines| {
        let strs: Vec<*mut StrObj> = lines.iter().map(|l| new_string(l)).collect();
        // SAFETY: handles and output pointers follow the ABI contract.
        unsafe { write_string_list(&strs, out) }
    })
}

/// The path a file handle was opened with.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_file_path(h: *mut FileHandle) -> *mut StrObj {
    // SAFETY: `h` is a live file handle.
    new_string(unsafe { &(*h).value.name })
}

type DirHandle = Handle<dir::Directory>;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_directory_open(
    path: *const StrObj,
    out: *mut *mut DirHandle,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = dir::Directory::open(unsafe { str_bytes(path) });
    // SAFETY: handles and output pointers follow the ABI contract.
    finish(r, |d| unsafe { *out = new_handle(d) })
}

/// The next entry in native order; `STATUS_NONE` at the end.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_directory_read(h: *mut DirHandle, out: *mut EntryOut) -> u8 {
    // SAFETY: `h` is a live directory handle; `out` is writable.
    match unsafe { (*h).value.read() } {
        Ok(None) => ms_rt_abi::STATUS_NONE,
        other => finish(other, |item| {
            let item = item.expect("entry present");
            // SAFETY: `out` is writable.
            unsafe {
                out.write(EntryOut {
                    name: new_string(&item.name),
                    directory: item.directory as u8,
                    symlink: item.symlink as u8,
                })
            }
        }),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_directory_close(h: *mut DirHandle) {
    // SAFETY: `h` is a live directory handle.
    unsafe { (*h).value.close() }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_directory_path(h: *mut DirHandle) -> *mut StrObj {
    // SAFETY: `h` is a live directory handle.
    new_string(unsafe { (*h).value.path() })
}

type TempHandle = Handle<dir::Temporary>;

/// Creates a temporary directory scoped to the handle (`close` removes the tree).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_temporary_open(
    prefix: *const StrObj,
    out: *mut *mut TempHandle,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = dir::Temporary::create(unsafe { str_bytes(prefix) });
    // SAFETY: handles and output pointers follow the ABI contract.
    finish(r, |t| unsafe { *out = new_handle(t) })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_temporary_path(h: *mut TempHandle) -> *mut StrObj {
    // SAFETY: `h` is a live temporary handle.
    new_string(unsafe { (*h).value.path() })
}

/// Removes the tree; a failure carries its text for `msstd_fs_failure_message`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_temporary_close(h: *mut TempHandle) -> u8 {
    // SAFETY: `h` is a live temporary handle.
    finish(unsafe { (*h).value.close() }, |()| ())
}

/// `glob`: sorted relative matches as a `List[String]`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_glob(
    path: *const StrObj,
    pattern: *const StrObj,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = lim(has_max, max)
        .and_then(|m| unsafe { walk::glob(str_bytes(path), str_bytes(pattern), m) });
    finish(r, |items| {
        let strs: Vec<*mut StrObj> = items.iter().map(|i| new_string(i)).collect();
        // SAFETY: handles and output pointers follow the ABI contract.
        unsafe { write_string_list(&strs, out) }
    })
}

/// The `code` of a closure the compiler built for a caller predicate: it is called as
/// `code(closure, source, destination)` with borrowed strings, and zero skips the entry.
type CopyFilter = unsafe extern "C-unwind" fn(*mut Closure, *const StrObj, *const StrObj) -> u8;

/// The `code` of a glob exclusion predicate over `(path, name, directory, symlink)`; non-zero
/// excludes the entry.
type EntryFilter =
    unsafe extern "C-unwind" fn(*mut Closure, *const StrObj, *const StrObj, u8, u8) -> u8;

/// The code pointer of a nullable closure.
///
/// # Safety
/// `filter` is null or a live closure whose code has the signature `F`.
unsafe fn closure_code<F: Copy>(filter: *mut Closure) -> Option<F> {
    if filter.is_null() {
        return None;
    }
    // SAFETY: per the contract, the code pointer has the signature `F`.
    Some(unsafe { core::mem::transmute_copy::<*const u8, F>(&(*filter).code) })
}

fn borrowed(bytes: &[u8]) -> *mut StrObj {
    new_string(bytes)
}

/// `copy_tree`: `entries` and `bytes` are budgets (pass `i64::MAX` for unlimited).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_copy_tree(
    source: *const StrObj,
    destination: *const StrObj,
    replace: u8,
    entries: i64,
    bytes: i64,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let (s, d) = unsafe { (str_bytes(source), str_bytes(destination)) };
    finish(walk::copy_tree(s, d, replace != 0, entries, bytes), |()| ())
}

/// `copy`. `clone` is `"none"`, `"try"` or `"force"`; `filter` is null or a closure.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_copy(
    source: *const StrObj,
    destination: *const StrObj,
    flags: i64,
    clone: *const StrObj,
    has_entries: u8,
    entries: i64,
    has_bytes: u8,
    bytes: i64,
    filter: *mut Closure,
) -> u8 {
    // SAFETY: handles and output pointers follow the ABI contract.
    let Some(clone) = walk::Clone::parse(unsafe { str_bytes(clone) }) else {
        ms_std_rt::record_failure(Vec::new());
        return ms_rt_abi::STATUS_INVALID_INPUT;
    };
    let (entries, bytes) = match (lim(has_entries, entries), lim(has_bytes, bytes)) {
        (Ok(e), Ok(b)) => (e, b),
        (Err(f), _) | (_, Err(f)) => return finish(Err::<(), _>(f), |()| ()),
    };
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
    // SAFETY: the compiler passes a closure with this signature or null.
    let code = unsafe { closure_code::<CopyFilter>(filter) };
    let mut call = |s: &[u8], d: &[u8]| -> bool {
        let f = code.expect("filter present");
        let (a, b) = (borrowed(s), borrowed(d));
        // SAFETY: the thunk takes borrowed strings; they are released after the call.
        let keep = unsafe { f(filter, a, b) } != 0;
        // SAFETY: handles and output pointers follow the ABI contract.
        unsafe {
            ms_std_rt::release(a.cast());
            ms_std_rt::release(b.cast());
        }
        keep
    };
    let f: Option<walk::Filter<'_>> = if code.is_some() {
        Some(&mut call)
    } else {
        None
    };
    // SAFETY: arguments follow the ABI contract.
    let r = unsafe { walk::copy(str_bytes(source), str_bytes(destination), options, f) };
    finish(r, |()| ())
}

/// One `PathEntry` as compiled code lays the record out: the path, the nested
/// `DirectoryEntry`'s name, then its two flag bytes.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct PathEntryOut {
    pub path: *mut StrObj,
    pub name: *mut StrObj,
    pub directory: u8,
    pub symlink: u8,
}

/// `glob_entries`: `patterns` and `exclude` are `List[String]`; matches come back as a
/// `List[PathEntry]`. `filter` is null or a closure over `(path, name, directory, symlink)`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_glob_entries(
    path: *const StrObj,
    patterns: *const VecVal,
    exclude: *const VecVal,
    follow_links: u8,
    has_max_entries: u8,
    max_entries: i64,
    has_max_results: u8,
    max_results: i64,
    filter: *mut Closure,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: the lists hold live strings for the duration of the call.
    let (patterns, exclude): (Vec<&[u8]>, Vec<&[u8]>) = unsafe {
        let each = |v: *const VecVal| {
            ms_std_rt::list_slice::<*const StrObj>(v)
                .iter()
                .map(|s| str_bytes(*s))
                .collect::<Vec<_>>()
        };
        (each(patterns), each(exclude))
    };
    let (max_entries, max_results) = match (
        lim(has_max_entries, max_entries),
        lim(has_max_results, max_results),
    ) {
        (Ok(e), Ok(r)) => (e, r),
        (Err(f), _) | (_, Err(f)) => return finish(Err::<(), _>(f), |()| ()),
    };
    let options = walk::GlobOptions {
        patterns: &patterns,
        exclude: &exclude,
        follow_links: follow_links != 0,
        max_entries,
        max_results,
    };
    // SAFETY: the compiler passes a closure with this signature or null.
    let code = unsafe { closure_code::<EntryFilter>(filter) };
    let mut call = |e: &walk::PathEntry| -> bool {
        let f = code.expect("callback present");
        let (p, n) = (borrowed(&e.path), borrowed(&e.name));
        // SAFETY: the thunk takes borrowed strings; they are released after the call.
        let skip = unsafe { f(filter, p, n, e.directory as u8, e.symlink as u8) } != 0;
        // SAFETY: handles and output pointers follow the ABI contract.
        unsafe {
            ms_std_rt::release(p.cast());
            ms_std_rt::release(n.cast());
        }
        skip
    };
    let cb: Option<&mut dyn FnMut(&walk::PathEntry) -> bool> = if code.is_some() {
        Some(&mut call)
    } else {
        None
    };
    // SAFETY: arguments follow the ABI contract.
    let r = walk::glob_entries(unsafe { str_bytes(path) }, &options, cb);
    finish(r, |items| {
        let rows: Vec<PathEntryOut> = items
            .iter()
            .map(|e| PathEntryOut {
                path: new_string(&e.path),
                name: new_string(&e.name),
                directory: e.directory as u8,
                symlink: e.symlink as u8,
            })
            .collect();
        // SAFETY: `out` is writable.
        unsafe { ms_std_rt::write_list(&rows, out) }
    })
}

/// The `FileMode`/open-flag constants as parallel `names` (`List[String]`) and `values`
/// (`List[Int]`) lists.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_constants(names: *mut VecVal, values: *mut VecVal) {
    let table = consts::file_constants();
    let n: Vec<*mut StrObj> = table
        .iter()
        .map(|(k, _)| new_string(k.as_bytes()))
        .collect();
    let v: Vec<i64> = table.iter().map(|(_, v)| *v).collect();
    // SAFETY: the outputs are writable.
    unsafe {
        write_string_list(&n, names);
        ms_std_rt::write_list(&v, values);
    }
}

type WatchHandle = Handle<watch::Watcher>;

/// A polling watcher (`interval_ns` > 0); `max` bounds tracked paths.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_watch(
    path: *const StrObj,
    recursive: u8,
    interval_ns: i64,
    has_max: u8,
    max: i64,
    out: *mut *mut WatchHandle,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = lim(has_max, max)
        .and_then(|m| watch::Poll::new(unsafe { str_bytes(path) }, recursive != 0, interval_ns, m));
    // SAFETY: `out` is writable.
    finish(r, |p| unsafe { *out = new_handle(watch::Watcher::poll(p)) })
}

/// A native (inotify) watcher; `overflow` is `error` or `ignore`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_watch_native(
    path: *const StrObj,
    recursive: u8,
    has_max: u8,
    max: i64,
    has_events: u8,
    events: i64,
    overflow: *const StrObj,
    out: *mut *mut WatchHandle,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let (path, overflow) = unsafe { (str_bytes(path), str_bytes(overflow)) };
    let r = lim(has_max, max).and_then(|m| {
        let e = if has_events != 0 { events } else { 128 };
        watch::Native::new(
            path,
            recursive != 0,
            if has_max != 0 { m } else { i64::MAX },
            e,
            overflow,
        )
    });
    // SAFETY: `out` is writable.
    finish(r, |n| unsafe {
        *out = new_handle(watch::Watcher::native(n))
    })
}

/// Waits for activity. `paths` receives a `List[String]` and `kinds` one byte per event
/// (1 `rename`, 0 `change`). `STATUS_CLOSED` after close, `STATUS_LIMIT_EXCEEDED` on overflow.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_watch_next(
    h: *mut WatchHandle,
    paths: *mut VecVal,
    kinds: *mut VecVal,
) -> u8 {
    // SAFETY: `h` is a live watcher handle.
    let r = unsafe { (*h).value.wait() };
    finish(r, |events| {
        let strs: Vec<*mut StrObj> = events.iter().map(|e| new_string(&e.path)).collect();
        let bits: Vec<u8> = events.iter().map(|e| e.rename as u8).collect();
        // SAFETY: `paths` and `kinds` are writable.
        unsafe {
            write_string_list(&strs, paths);
            write_bytes(&bits, kinds);
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_watch_close(h: *mut WatchHandle) {
    // SAFETY: `h` is a live watcher handle.
    unsafe { (*h).value.close() }
}

/// Stand-ins for the runtime symbols `ms-std-rt` links against, so the crate's unit tests link alone.
#[cfg(test)]
mod runtime_stubs {
    #[unsafe(no_mangle)]
    pub static msrt_cancel_flag: u8 = 0;

    #[unsafe(no_mangle)]
    pub extern "C" fn msrt_cancelled() -> ! {
        panic!("cancelled")
    }

    #[unsafe(no_mangle)]
    pub extern "C-unwind" fn msrt_io_flush() {}
}
