//! Process arguments and start time, from the C entry (`runtime/entry/start.c`).
#![allow(unsafe_code)]

use ms_rt_abi::VecVal;

unsafe extern "C-unwind" {
    pub fn msrt_argv(out: *mut VecVal);
    pub safe fn msrt_start_nanos() -> i64;
}
