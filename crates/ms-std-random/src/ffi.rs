//! C ABI shims for `@std/random.ms` (`msstd_random_*`): the operating-system `Entropy` source.
use crate::{Draw, Kind, RandomFail};
use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::{Mut, Own, Ref, Status, StrObj, abi_handle, native};

abi_handle!(Draw);

/// `RandomFail::Failed` also records its text for `msstd_random_failure_message`.
impl Status for RandomFail {
    fn status(self) -> u8 {
        match self {
            RandomFail::InvalidInput => ms_rt_abi::STATUS_INVALID_INPUT,
            RandomFail::LimitExceeded => ms_rt_abi::STATUS_LIMIT_EXCEEDED,
            RandomFail::Failed(m) => {
                ms_std_rt::record_failure(m.into_bytes());
                ms_rt_abi::STATUS_FAILED
            }
        }
    }
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
    /// The text of the last `Failed` status (a fresh string).
    safe fn msstd_random_failure_message() -> *mut StrObj {
        ms_std_rt::failure_message()
    }

    /// `Entropy.bytes` of the operating-system source.
    fn msstd_random_os_bytes(count: i64) -> Result<Vec<u8>, RandomFail> {
        crate::os_bytes(count)
    }

    /// Starts a [`Draw`]; `kind` is 0 `secure_int` (`a` min, `b` optional max), 1 `uuid_v4`,
    /// 2 `float`, 3 `shuffle` of `a` items, 4 `choice` over `a` items. Freed by
    /// `msstd_random_draw_free`.
    safe fn msstd_random_draw_new(kind: i64, a: i64, has_b: bool, b: i64) -> Own<Draw> {
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

    /// The outcome: `0` on success, otherwise the `RandomError` status.
    fn msstd_random_draw_status(d: Ref<Draw>) -> u8 {
        d.status()
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
    use ms_std_core::VecVal; // links the msrt_* runtime symbols

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
