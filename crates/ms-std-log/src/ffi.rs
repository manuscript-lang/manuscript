//! C ABI shims for `@std/log.ms` (`msrt_logcore_*`).
//!
//! A `Logger` native is a refcounted [`LoggerObj`] handle. `msrt_logcore_logger_encode` produces the
//! line to write; the generated code owns the transport and the clock.

use crate::{LogFail, Logger};
use alloc::string::String;
use alloc::vec::Vec;
use core::sync::atomic::{AtomicBool, Ordering};
use ms_rt::ffi::{ObjRef, Object, Status, abi_handle, native};

abi_handle!(Logger);

/// A flag shared by every copy of a transport: set once when the transport closes.
pub struct Gate(AtomicBool);
abi_handle!(Gate);

impl Status for LogFail {
    fn status(self) -> u8 {
        LogFail::status(self)
    }
}

/// A record line is UTF-8 JSON; `None` (filtered) is the empty string, which no record can be.
fn line_text(line: Option<Vec<u8>>) -> Result<String, LogFail> {
    match line {
        None => Ok(String::new()),
        Some(bytes) => String::from_utf8(bytes).map_err(|_| LogFail::InvalidData),
    }
}

fn level_index(level: i64) -> Option<usize> {
    usize::try_from(level).ok().filter(|l| *l <= crate::SILENT)
}

native! {
    fn msrt_logcore_new_state(
        has_level: bool,
        level: i64,
        has_timestamp: bool,
        timestamp: bool,
        has_max: bool,
        max: i64,
    ) -> Result<Object<Logger>, LogFail> {
        let level = if has_level {
            Some(level_index(level).ok_or(LogFail::InvalidInput)?)
        } else {
            None
        };
        Logger::new(level, has_timestamp.then_some(timestamp), has_max.then_some(max)).map(Object)
    }

    fn msrt_logcore_child(l: ObjRef<Logger>, fields: &str) -> Result<Object<Logger>, LogFail> {
        l.child(fields).map(Object)
    }

    fn msrt_logcore_enabled(l: ObjRef<Logger>, level: i64) -> bool {
        l.enabled(level)
    }

    fn msrt_logcore_level(l: ObjRef<Logger>) -> i64 {
        l.level() as i64
    }

    fn msrt_logcore_set_level(l: ObjRef<Logger>, level: i64) -> () {
        let Some(level) = level_index(level) else {
            ms_rt::ffi::fault("invalid LogLevel");
        };
        l.set_level(level);
    }

    /// The line for a plain message; empty when the level is below the threshold.
    fn msrt_logcore_line(
        l: ObjRef<Logger>,
        level: i64,
        message: &str,
        now_ms: i64,
    ) -> Result<String, LogFail> {
        line_text(l.log(level, message, now_ms)?)
    }

    /// The line for a message with the members of the object text `fields` added.
    fn msrt_logcore_line_json(
        l: ObjRef<Logger>,
        level: i64,
        message: &str,
        fields: &str,
        now_ms: i64,
    ) -> Result<String, LogFail> {
        line_text(l.log_json(level, message, fields, now_ms)?)
    }

    fn msrt_logcore_new_gate() -> Object<Gate> {
        Object(Gate(AtomicBool::new(false)))
    }

    fn msrt_logcore_shut(g: ObjRef<Gate>) -> () {
        g.0.0.store(true, Ordering::Release);
    }

    fn msrt_logcore_is_shut(g: ObjRef<Gate>) -> bool {
        g.0.0.load(Ordering::Acquire)
    }

    fn msrt_logcore_object_text(text: &str) -> String {
        crate::object_text(text)
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _; // links the msrt_* runtime symbols
    use ms_rt::ffi::{ObjCell, StrVal, new_string};

    #[test]
    fn line_roundtrip() {
        let mut l = MaybeUninit::<*mut ObjCell<Logger>>::uninit();
        let msg = new_string("hi");
        // SAFETY: pointers are live; outputs are initialised by the calls that fill them.
        unsafe {
            assert_eq!(msrt_logcore_new_state(0, 0, 1, 0, 0, 0, l.as_mut_ptr()), 0);
            let l = l.assume_init();
            let mut out = MaybeUninit::<StrVal>::uninit();
            assert_eq!(msrt_logcore_line(l, 2, &msg, 5, out.as_mut_ptr()), 0);
            assert_eq!(
                ms_rt::ffi::str_ref(out.assume_init_ref()),
                "{\"level\":30,\"msg\":\"hi\"}\n"
            );
            assert_eq!(msrt_logcore_line(l, 0, &msg, 5, out.as_mut_ptr()), 0);
            assert_eq!(ms_rt::ffi::str_ref(out.assume_init_ref()), "");
            assert_eq!(msrt_logcore_line(l, 6, &msg, 5, out.as_mut_ptr()), 1);
        }
    }
}
