//! C ABI shims for `@std/path.ms` (`msrt_path_*`). Every function takes `windows: u8` first,
//! selecting POSIX (0) or Windows (1) rules; the host-rule functions pass the host's flag.
//! `PathParts` is a record of five strings (`root, directory, base, extension, name`) at its
//! natural layout; the runtime writes owned strings into it.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::{Parts, Rules};
use ms_std_core::{StrObj, VecVal, new_string, read_string_list, str_ref};

/// `PathParts` record.
#[repr(C)]
pub struct PartsRec {
    pub root: *mut StrObj,
    pub directory: *mut StrObj,
    pub base: *mut StrObj,
    pub extension: *mut StrObj,
    pub name: *mut StrObj,
}

fn rules(windows: u8) -> Rules {
    Rules {
        windows: windows != 0,
    }
}

/// Status of the only path error: `PathError.InvalidInput`.
const INVALID_INPUT: u8 = ms_std_core::STATUS_INVALID_INPUT;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_basename(windows: u8, path: *const StrObj) -> *mut StrObj {
    // SAFETY: `path` is live.
    new_string(&rules(windows).basename(unsafe { str_ref(path) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_basename_without(
    windows: u8,
    path: *const StrObj,
    suffix: *const StrObj,
) -> *mut StrObj {
    // SAFETY: both strings are live.
    new_string(
        &rules(windows).basename_without(unsafe { str_ref(path) }, unsafe { str_ref(suffix) }),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_dirname(windows: u8, path: *const StrObj) -> *mut StrObj {
    // SAFETY: `path` is live.
    new_string(&rules(windows).dirname(unsafe { str_ref(path) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_extension(windows: u8, path: *const StrObj) -> *mut StrObj {
    // SAFETY: `path` is live.
    new_string(&rules(windows).extension(unsafe { str_ref(path) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_is_absolute(windows: u8, path: *const StrObj) -> u8 {
    // SAFETY: `path` is live.
    u8::from(rules(windows).is_absolute(unsafe { str_ref(path) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_join(windows: u8, parts: *const VecVal) -> *mut StrObj {
    // SAFETY: `parts` is a live `List[String]`.
    new_string(&rules(windows).join(&unsafe { read_string_list(parts) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_normalize(windows: u8, path: *const StrObj) -> *mut StrObj {
    // SAFETY: `path` is live.
    new_string(&rules(windows).normalize(unsafe { str_ref(path) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_relative(
    windows: u8,
    base: *const StrObj,
    target: *const StrObj,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: strings are live; `out` is writable.
    unsafe { string_status(rules(windows).relative(str_ref(base), str_ref(target)), out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_resolve(
    windows: u8,
    base: *const StrObj,
    parts: *const VecVal,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: `base` is live; `parts` is a live `List[String]`; `out` is writable.
    unsafe {
        string_status(
            rules(windows).resolve(str_ref(base), &read_string_list(parts)),
            out,
        )
    }
}

unsafe fn string_status(
    r: Result<alloc::string::String, crate::InvalidInput>,
    out: *mut *mut StrObj,
) -> u8 {
    match r {
        Ok(s) => {
            // SAFETY: `out` is writable by the caller contract.
            unsafe { out.write(new_string(&s)) };
            ms_std_core::STATUS_OK
        }
        Err(_) => INVALID_INPUT,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_parse(windows: u8, path: *const StrObj, out: *mut PartsRec) {
    // SAFETY: `path` is live; `out` is writable.
    unsafe {
        let p = rules(windows).parse(str_ref(path));
        out.write(PartsRec {
            root: new_string(&p.root),
            directory: new_string(&p.directory),
            base: new_string(&p.base),
            extension: new_string(&p.extension),
            name: new_string(&p.name),
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_format(windows: u8, parts: *const PartsRec) -> *mut StrObj {
    // SAFETY: `parts` is a live PathParts record.
    unsafe {
        let r = &*parts;
        new_string(&rules(windows).format(&Parts {
            root: str_ref(r.root).into(),
            directory: str_ref(r.directory).into(),
            base: str_ref(r.base).into(),
            extension: str_ref(r.extension).into(),
            name: str_ref(r.name).into(),
        }))
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_path_separator(windows: u8) -> *mut StrObj {
    new_string(rules(windows).separator())
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_path_delimiter(windows: u8) -> *mut StrObj {
    new_string(rules(windows).delimiter())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_to_namespaced_path(
    windows: u8,
    path: *const StrObj,
) -> *mut StrObj {
    // SAFETY: `path` is live.
    new_string(&rules(windows).to_namespaced_path(unsafe { str_ref(path) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_path_matches_glob(
    windows: u8,
    value: *const StrObj,
    pattern: *const StrObj,
    out: *mut u8,
) -> u8 {
    // SAFETY: strings are live; `out` is writable.
    unsafe {
        match rules(windows).matches_glob(str_ref(value), str_ref(pattern)) {
            Ok(b) => {
                out.write(u8::from(b));
                ms_std_core::STATUS_OK
            }
            Err(_) => INVALID_INPUT,
        }
    }
}
