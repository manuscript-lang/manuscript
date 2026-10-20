//! C ABI shims for `@std/random.ms` (`msstd_random_*`): the operating-system `Entropy` source.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::{Draw, Kind, RandomFail};
use alloc::boxed::Box;
use ms_std_core::{StrObj, VecVal, new_string, write_bytes};

/// The text of the last `Failed` status (a fresh string).
#[unsafe(no_mangle)]
pub extern "C" fn msstd_random_failure_message() -> *mut StrObj {
    ms_std_rt::failure_message()
}

/// `Entropy.bytes` of the operating-system source.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_random_os_bytes(count: i64, out: *mut VecVal) -> u8 {
    match crate::os_bytes(count) {
        Ok(b) => {
            // SAFETY: `out` is writable.
            unsafe { write_bytes(out, &b) };
            0
        }
        Err(RandomFail::InvalidInput) => ms_rt_abi::STATUS_INVALID_INPUT,
        Err(RandomFail::LimitExceeded) => ms_rt_abi::STATUS_LIMIT_EXCEEDED,
        Err(RandomFail::Failed(m)) => {
            ms_std_rt::record_failure(m.into_bytes());
            ms_rt_abi::STATUS_FAILED
        }
    }
}

/// Starts a [`Draw`]; `kind` is 0 `secure_int` (`a` min, `b` optional max), 1 `uuid_v4`, 2 `float`,
/// 3 `shuffle` of `a` items, 4 `choice` over `a` items. Freed by `msstd_random_draw_free`.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_random_draw_new(kind: i64, a: i64, has_b: u8, b: i64) -> *mut Draw {
    let kind = match kind {
        0 => Kind::Int,
        1 => Kind::Uuid,
        2 => Kind::Float,
        3 => Kind::Shuffle,
        _ => Kind::Choice,
    };
    Box::into_raw(Box::new(Draw::new(kind, a, (has_b != 0).then_some(b))))
}

/// The next byte count to fetch, or `0` when the operation is over.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_random_draw_want(d: *const Draw) -> i64 {
    // SAFETY: `d` is live.
    unsafe { (*d).want() }
}

/// Feeds fetched bytes; `1` when a shuffle swap is ready.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_random_draw_push(d: *mut Draw, data: *const VecVal) -> u8 {
    // SAFETY: `d` is live and `data` a live byte vector.
    u8::from(unsafe { (*d).push(ms_std_rt::vec_bytes(data)) })
}

/// The swapped positions: `which` 0 the first, 1 the second.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_random_draw_swap(d: *const Draw, which: i64) -> i64 {
    // SAFETY: `d` is live.
    let (i, j) = unsafe { (*d).swap() };
    if which == 0 { i } else { j }
}

/// The outcome: `0` on success, otherwise the `RandomError` status.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_random_draw_status(d: *const Draw) -> u8 {
    // SAFETY: `d` is live.
    unsafe { (*d).status() }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_random_draw_int(d: *const Draw) -> i64 {
    // SAFETY: `d` is live.
    unsafe { (*d).int() }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_random_draw_float(d: *const Draw) -> f64 {
    // SAFETY: `d` is live.
    unsafe { (*d).float() }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_random_draw_text(d: *const Draw) -> *mut StrObj {
    // SAFETY: `d` is live.
    new_string(unsafe { (*d).text() })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_random_draw_free(d: *mut Draw) {
    // SAFETY: `d` came from `msstd_random_draw_new` and is freed once.
    drop(unsafe { Box::from_raw(d) });
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _; // links the msrt_* runtime symbols

    #[test]
    fn os_bytes_bounds() {
        let mut out = MaybeUninit::<VecVal>::uninit();
        // SAFETY: pointers are writable.
        unsafe {
            assert_eq!(msstd_random_os_bytes(-1, out.as_mut_ptr()), 1);
            assert_eq!(
                msstd_random_os_bytes(crate::MAX_BYTES + 1, out.as_mut_ptr()),
                1
            );
            assert_eq!(msstd_random_os_bytes(32, out.as_mut_ptr()), 0);
            assert_eq!(out.assume_init().len, 32);
        }
    }
}
