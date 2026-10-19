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

pub mod err;
pub mod ops;
pub mod path;
pub mod sys;

use alloc::vec::Vec;
use err::{Fail, Res};
use ms_rt_abi::{STATUS_OK, StrObj, VecVal};
use ms_std_rt::{new_string, str_bytes, write_bytes, write_string_list};

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

/// Flattened `FileInfo`. Times are `(seconds, nanoseconds)`; `created_present` says whether the
/// creation time exists on this host. `kinds` is the `KIND_*` bit set from `ops`.
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
    pub created_present: u8,
    pub kinds: u32,
    pub block_size: u64,
    pub blocks: u64,
    pub rdev: u64,
    pub device: u64,
    pub inode: u64,
    pub links: u64,
    pub uid: u64,
    pub gid: u64,
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
            created_present: i.created.is_some() as u8,
            kinds: i.kinds(),
            block_size: i.block_size,
            blocks: i.blocks,
            rdev: i.rdev,
            device: i.device,
            inode: i.inode,
            links: i.links,
            uid: i.uid,
            gid: i.gid,
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

/// Lists a directory sorted by name: `names` receives a `List[String]`, `flags` one byte per entry
/// (bit 0 directory, bit 1 symlink).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_fs_list(
    path: *const StrObj,
    has_limit: u8,
    limit: i64,
    names: *mut VecVal,
    flags: *mut VecVal,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = lim(has_limit, limit).and_then(|m| ops::list(unsafe { str_bytes(path) }, m));
    finish(r, |entries| {
        let strs: Vec<*mut StrObj> = entries.iter().map(|e| new_string(&e.name)).collect();
        let bits: Vec<u8> = entries
            .iter()
            .map(|e| e.directory as u8 | (e.symlink as u8) << 1)
            .collect();
        // SAFETY: `names` and `flags` are writable.
        unsafe {
            write_string_list(&strs, names);
            write_bytes(&bits, flags);
        }
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

/// Stand-ins for the runtime symbols `ms-std-rt` links against, so the crate's unit tests link alone.
#[cfg(test)]
mod runtime_stubs {
    #[unsafe(no_mangle)]
    pub static msrt_cancel_flag: u8 = 0;

    #[unsafe(no_mangle)]
    pub extern "C" fn msrt_cancelled() -> ! {
        panic!("cancelled")
    }
}
