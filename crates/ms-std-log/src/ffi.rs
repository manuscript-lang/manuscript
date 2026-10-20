//! C ABI shims for `@std/log.ms` (`msrt_log_*`).
//!
//! A `Logger` native is a refcounted [`LoggerObj`] handle. `msrt_log_logger_encode` produces the
//! line to write; the generated code owns the transport and the clock.

use crate::{LogFail, Logger};
use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::{ObjRef, Object, Out, Status, abi_handle, native};

abi_handle!(Logger);

impl Status for LogFail {
    fn status(self) -> u8 {
        LogFail::status(self)
    }
}

fn level_index(level: i64) -> Option<usize> {
    usize::try_from(level).ok().filter(|l| *l <= crate::SILENT)
}

native! {
    fn msrt_log_logger_new(
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

    fn msrt_log_logger_child(l: ObjRef<Logger>, fields: &str) -> Result<Object<Logger>, LogFail> {
        l.child(fields).map(Object)
    }

    fn msrt_log_logger_enabled(l: ObjRef<Logger>, level: i64) -> bool {
        l.enabled(level)
    }

    fn msrt_log_logger_level(l: ObjRef<Logger>) -> i64 {
        l.level() as i64
    }

    fn msrt_log_logger_set_level(l: ObjRef<Logger>, level: i64) -> () {
        let Some(level) = level_index(level) else {
            ms_std_core::fault("invalid LogLevel");
        };
        l.set_level(level);
    }

    /// `fields` is null for a plain message; `written` says whether a line was produced.
    fn msrt_log_logger_encode(
        l: ObjRef<Logger>,
        level: i64,
        message: &str,
        fields: Option<&str>,
        now_ms: i64,
        out: Out<Vec<u8>>,
        written: Out<bool>,
    ) -> Result<(), LogFail> {
        let line = match fields {
            None => l.log(level, message, now_ms)?,
            Some(f) => l.log_json(level, message, f, now_ms)?,
        };
        written.write(line.is_some());
        if let Some(b) = line {
            out.write(b);
        }
        Ok(())
    }

    fn msrt_log_object_text(text: &str) -> String {
        crate::object_text(text)
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _; // links the msrt_* runtime symbols
    use ms_std_core::{ObjCell, VecVal, new_string};

    #[test]
    fn encode_roundtrip() {
        let mut l = MaybeUninit::<*mut ObjCell<Logger>>::uninit();
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
