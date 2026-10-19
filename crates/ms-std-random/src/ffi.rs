//! C ABI shims for `@std/random.ms` (`msrt_random_*`).
//!
//! Only the operating-system source is native here. Operations taking an `Entropy` interface
//! value are exposed as Rust functions over a fetch closure ([`crate::secure_int`] and friends)
//! because calling a user-defined interface method is the generated code's job.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::RandomFail;
use ms_std_core::{StrObj, VecVal, new_string, write_bytes};

/// `RandomError.Failed`: the message is written through `message`.
pub const STATUS_FAILED: u8 = 7;

/// `Entropy.bytes` of the operating-system source.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_random_os_bytes(
    count: i64,
    out: *mut VecVal,
    message: *mut *mut StrObj,
) -> u8 {
    match crate::os_bytes(count) {
        Ok(b) => {
            // SAFETY: `out` is writable.
            unsafe { write_bytes(out, &b) };
            0
        }
        Err(RandomFail::InvalidInput) => ms_rt_abi::STATUS_INVALID_INPUT,
        Err(RandomFail::LimitExceeded) => ms_rt_abi::STATUS_LIMIT_EXCEEDED,
        Err(RandomFail::Failed(m)) => {
            // SAFETY: `message` is writable.
            unsafe { message.write(new_string(&m)) };
            STATUS_FAILED
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _; // links the msrt_* runtime symbols

    #[test]
    fn os_bytes_bounds() {
        let mut out = MaybeUninit::<VecVal>::uninit();
        let mut m = MaybeUninit::<*mut StrObj>::uninit();
        // SAFETY: pointers are writable.
        unsafe {
            assert_eq!(
                msrt_random_os_bytes(-1, out.as_mut_ptr(), m.as_mut_ptr()),
                1
            );
            assert_eq!(
                msrt_random_os_bytes(crate::MAX_BYTES + 1, out.as_mut_ptr(), m.as_mut_ptr()),
                1
            );
            assert_eq!(
                msrt_random_os_bytes(32, out.as_mut_ptr(), m.as_mut_ptr()),
                0
            );
            assert_eq!(out.assume_init().len, 32);
        }
    }
}
