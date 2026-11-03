//! C ABI shims for `@std/os/random.ms` (`msstd_random_*`): the operating-system `Entropy` source.
use super::{Draw, Kind, RandomFail};
use alloc::string::String;
use alloc::vec::Vec;
use ms_rt::ffi::{ErrOut, Has, Mut, Own, Ref, StatusCode, abi_handle, native};

abi_handle!(Draw);

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

fn kind_of(kind: i64) -> Kind {
    match kind {
        0 => Kind::Int,
        1 => Kind::Uuid,
        2 => Kind::Float,
        3 => Kind::Shuffle,
        _ => Kind::Choice,
    }
}

native! {
    /// `Entropy.bytes` of the operating-system source.
    fn msstd_random_os_bytes(count: i64; err: ErrOut) -> Result<Vec<u8>, StatusCode> {
        super::os_bytes(count).map_err(|f| fail_status(f, &err))
    }

    /// Starts a [`Draw`]; `kind` is 0 `secure_int` (`a` min, `b` optional max), 1 `uuid_v4`,
    /// 2 `float`, 3 `shuffle` of `a` items, 4 `choice` over `a` items. Freed by
    /// `msstd_random_draw_free`.
    safe fn msstd_random_draw_new(kind: i64, a: i64, has_b: Has, b: i64) -> Own<Draw> {
        Own(alloc::boxed::Box::new(Draw::new(kind_of(kind), a, has_b.then_some(b))))
    }

    /// The next byte count to fetch, or `0` when the operation is over.
    fn msstd_random_draw_want(d: Ref<Draw>) -> i64 {
        d.want()
    }

    /// Feeds fetched bytes; `1` when a shuffle swap is ready.
    fn msstd_random_draw_push(d: Mut<Draw>, data: &[u8]) -> bool {
        let mut d = d;
        d.push(data)
    }

    /// The swapped positions: `which` 0 the first, 1 the second.
    fn msstd_random_draw_swap(d: Ref<Draw>, which: i64) -> i64 {
        let (i, j) = d.swap();
        if which == 0 { i } else { j }
    }

    /// The outcome: `0` on success, otherwise the `RandomError` status (`Failed` writes `err`).
    fn msstd_random_draw_status(d: Ref<Draw>; err: ErrOut) -> Result<(), StatusCode> {
        let status = d.status();
        if status == ms_rt_abi::STATUS_FAILED {
            err.set(super::SHORT_ENTROPY);
        }
        if status == 0 { Ok(()) } else { Err(StatusCode(status)) }
    }

    fn msstd_random_draw_int(d: Ref<Draw>) -> i64 {
        d.int()
    }

    fn msstd_random_draw_float(d: Ref<Draw>) -> f64 {
        d.float()
    }

    fn msstd_random_draw_text(d: Ref<Draw>) -> String {
        String::from(d.text())
    }

    fn msstd_random_draw_free(d: Own<Draw>) -> () {
        drop(d);
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
