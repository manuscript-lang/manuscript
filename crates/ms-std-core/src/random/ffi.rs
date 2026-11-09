//! C ABI shims for `@std/random.ms` (`msstd_random_*`): the operating-system `Entropy` source.
//! ms: domain random
use super::RandomFail;
use alloc::vec::Vec;
use ms_rt::ffi::{ErrOut, StatusCode, native};

/// The status of `fail`; a `Failed` one stores its text in `err`.
fn fail_status(fail: RandomFail, err: &ErrOut) -> StatusCode {
    StatusCode(match fail {
        RandomFail::InvalidInput => ms_rt_abi::STATUS_INVALID_INPUT,
        RandomFail::LimitExceeded => ms_rt_abi::STATUS_LIMIT_EXCEEDED,
        RandomFail::Failed(m) => {
            err.set(&m);
            ms_rt_abi::STATUS_FAILED
        }
    })
}

native! {
    /// `Entropy.bytes` of the operating-system source.
    fn msstd_random_os_bytes(count: i64; err: ErrOut) -> Result<Vec<u8>, StatusCode> {
        super::os_bytes(count).map_err(|f| fail_status(f, &err))
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _;
    use ms_rt::ffi::VecVal; // links the msrt_* runtime symbols

    const NO_ERR: ms_rt::ffi::ErrSlot = ms_rt::ffi::ErrSlot(core::ptr::null_mut());

    #[test]
    fn os_bytes_bounds() {
        let mut out = MaybeUninit::<VecVal>::uninit();
        // SAFETY: pointers are writable.
        unsafe {
            assert_eq!(msstd_random_os_bytes(-1, out.as_mut_ptr(), NO_ERR), 1);
            assert_eq!(
                msstd_random_os_bytes(crate::random::MAX_BYTES + 1, out.as_mut_ptr(), NO_ERR),
                1
            );
            assert_eq!(msstd_random_os_bytes(32, out.as_mut_ptr(), NO_ERR), 0);
            assert_eq!(out.assume_init().len, 32);
        }
    }
}
