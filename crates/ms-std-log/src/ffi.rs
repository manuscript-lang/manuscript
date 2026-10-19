//! C ABI shims for `@std/log.ms` (`msrt_log_*`).
//!
//! A `Logger` native is a refcounted [`LoggerObj`] handle. `msrt_log_logger_encode` produces the
//! line to write; the generated code owns the transport and the clock.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::{LogFail, Logger};
use alloc::boxed::Box;
use ms_rt_abi::Obj;
use ms_std_core::{StrObj, VecVal, new_string, opt, str_ref, write_bytes};

unsafe extern "C" {
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_free(p: *mut u8);
}

#[repr(C)]
pub struct LoggerObj {
    header: Obj,
    logger: *mut Logger,
}

unsafe extern "C" fn logger_drop(o: *mut Obj) {
    let l = o.cast::<LoggerObj>();
    // SAFETY: `o` was built by `new_handle`; `logger` came from `Box::into_raw`.
    unsafe {
        drop(Box::from_raw((*l).logger));
        msrt_free(o.cast());
    }
}

unsafe fn new_handle(logger: Logger) -> *mut LoggerObj {
    // SAFETY: allocation sized for `LoggerObj`, fully initialised before it is returned.
    unsafe {
        let p = msrt_alloc(core::mem::size_of::<LoggerObj>()).cast::<LoggerObj>();
        p.write(LoggerObj {
            header: Obj {
                rc: 1,
                drop: Some(logger_drop),
            },
            logger: Box::into_raw(Box::new(logger)),
        });
        p
    }
}

unsafe fn logger<'a>(l: *const LoggerObj) -> &'a Logger {
    // SAFETY: `l` is a live handle.
    unsafe { &*(*l).logger }
}

fn level_index(level: i64) -> Option<usize> {
    usize::try_from(level).ok().filter(|l| *l <= crate::SILENT)
}

fn status(r: &Result<impl Sized, LogFail>) -> u8 {
    r.as_ref().err().map_or(0, |e| e.status())
}

/// `create`: `level` is the `LogLevel` case index.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_log_logger_new(
    has_level: u8,
    level: i64,
    has_timestamp: u8,
    timestamp: u8,
    has_max: u8,
    max: i64,
    out: *mut *mut LoggerObj,
) -> u8 {
    let level = match opt(has_level, level) {
        None => Ok(None),
        Some(l) => level_index(l).map(Some).ok_or(LogFail::InvalidInput),
    };
    let r = level.and_then(|level| {
        Logger::new(
            level,
            (has_timestamp != 0).then_some(timestamp != 0),
            opt(has_max, max),
        )
    });
    if let Ok(l) = r {
        // SAFETY: `out` is writable.
        unsafe { out.write(new_handle(l)) };
        return 0;
    }
    status(&r)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_log_logger_child(
    l: *const LoggerObj,
    fields: *const StrObj,
    out: *mut *mut LoggerObj,
) -> u8 {
    // SAFETY: `l` and `fields` are live; `out` is writable.
    unsafe {
        let r = logger(l).child(str_ref(fields));
        if let Ok(c) = r {
            out.write(new_handle(c));
            return 0;
        }
        status(&r)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_log_logger_enabled(l: *const LoggerObj, level: i64) -> u8 {
    // SAFETY: `l` is live.
    u8::from(unsafe { logger(l) }.enabled(level))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_log_logger_level(l: *const LoggerObj) -> i64 {
    // SAFETY: `l` is live.
    unsafe { logger(l) }.level() as i64
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_log_logger_set_level(l: *const LoggerObj, level: i64) {
    let Some(level) = level_index(level) else {
        ms_std_core::fault("invalid LogLevel");
    };
    // SAFETY: `l` is live.
    unsafe { logger(l) }.set_level(level);
}

/// Encodes one record. `fields` is null for `log` and the object text for `log_json`; `written`
/// is 0 when the record is below the threshold (nothing to write, `out` untouched).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_log_logger_encode(
    l: *const LoggerObj,
    level: i64,
    message: *const StrObj,
    fields: *const StrObj,
    now_ms: i64,
    out: *mut VecVal,
    written: *mut u8,
) -> u8 {
    // SAFETY: `l`, `message` and non-null `fields` are live; `out` and `written` are writable.
    unsafe {
        let l = logger(l);
        let r = if fields.is_null() {
            l.log(level, str_ref(message), now_ms)
        } else {
            l.log_json(level, str_ref(message), str_ref(fields), now_ms)
        };
        let line = match &r {
            Ok(line) => line,
            Err(e) => return e.status(),
        };
        written.write(u8::from(line.is_some()));
        if let Some(b) = line {
            write_bytes(out, b);
        }
        0
    }
}

/// `object_text`: wraps non-object JSON text under the key `data`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_log_object_text(text: *const StrObj) -> *mut StrObj {
    // SAFETY: `text` is live.
    new_string(&crate::object_text(unsafe { str_ref(text) }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _; // links the msrt_* runtime symbols

    #[test]
    fn encode_roundtrip() {
        let mut l = MaybeUninit::<*mut LoggerObj>::uninit();
        let mut out = MaybeUninit::<VecVal>::uninit();
        let mut written = 0u8;
        let msg = new_string("hi");
        // SAFETY: pointers are live; outputs are initialised by the calls that fill them.
        unsafe {
            assert_eq!(msrt_log_logger_new(0, 0, 1, 0, 0, 0, l.as_mut_ptr()), 0);
            let l = l.assume_init();
            assert_eq!(
                msrt_log_logger_encode(
                    l,
                    2,
                    msg,
                    core::ptr::null(),
                    5,
                    out.as_mut_ptr(),
                    &mut written
                ),
                0
            );
            assert_eq!(written, 1);
            assert_eq!(
                ms_std_core::bytes_ref(out.as_ptr()),
                b"{\"level\":30,\"msg\":\"hi\"}\n"
            );
            assert_eq!(
                msrt_log_logger_encode(
                    l,
                    0,
                    msg,
                    core::ptr::null(),
                    5,
                    out.as_mut_ptr(),
                    &mut written
                ),
                0
            );
            assert_eq!(written, 0);
            assert_eq!(
                msrt_log_logger_encode(
                    l,
                    6,
                    msg,
                    core::ptr::null(),
                    5,
                    out.as_mut_ptr(),
                    &mut written
                ),
                1
            );
        }
    }
}
