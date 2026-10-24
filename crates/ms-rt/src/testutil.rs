//! Helpers for unit tests: global-state lock and fault capture.
use std::sync::{Mutex, MutexGuard};

static LOCK: Mutex<()> = Mutex::new(());

/// Serializes tests that touch runtime globals (allocator, cleanup stack...).
pub fn lock() -> MutexGuard<'static, ()> {
    // The test thread plays the main isolate: stop signals and the process-wide flags are its.
    crate::isolate::set_main();
    LOCK.lock().unwrap_or_else(|e| e.into_inner())
}

/// Panic payload carrying the stderr text a fault would print.
pub struct FaultPayload(pub std::string::String);

/// Runs `f` and returns the fault text it raised, or `None` when it returned.
pub fn fault_of<R>(f: impl FnOnce() -> R) -> Option<std::string::String> {
    let hook = std::panic::take_hook();
    std::panic::set_hook(std::boxed::Box::new(|_| {}));
    let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(f));
    std::panic::set_hook(hook);
    match r {
        Ok(_) => None,
        Err(e) => match e.downcast::<FaultPayload>() {
            Ok(p) => Some(p.0),
            Err(e) => std::panic::resume_unwind(e),
        },
    }
}

/// Asserts the closure faults with exactly this first line (frames ignored).
#[track_caller]
pub fn assert_fault<R>(message: &str, f: impl FnOnce() -> R) {
    let got = fault_of(f).expect("expected a fault");
    assert_eq!(got.lines().next().unwrap_or(""), message);
}

/// Pointer-typed calls to the integer-typed `ms-rt-hot` entry points, so tests read like the C ABI.
pub mod hot {
    use ms_rt_abi::{MapVal, StrVal, TypeDesc};

    pub unsafe fn msrt_map_length(m: *const MapVal) -> i64 {
        // SAFETY: caller contract.
        unsafe { ms_rt_hot::msrt_map_length(m as usize) }
    }

    pub unsafe fn msrt_string_byte_length(s: *const StrVal) -> i64 {
        // SAFETY: caller contract.
        unsafe { ms_rt_hot::msrt_string_byte_length(s as usize) }
    }

    macro_rules! get_ptr {
        ($($name:ident),*) => {$(
            pub unsafe fn $name(
                m: *const MapVal,
                kd: *const TypeDesc,
                vd: *const TypeDesc,
                key: *const u8,
            ) -> *const u8 {
                // SAFETY: caller contract.
                unsafe { ms_rt_hot::$name(m as usize, kd as usize, vd as usize, key as usize) as *const u8 }
            }
        )*};
    }
    get_ptr!(msrt_map_get_ptr_sw8, msrt_map_get_ptr_w8);

    macro_rules! contains {
        ($($name:ident),*) => {$(
            pub unsafe fn $name(
                m: *const MapVal,
                kd: *const TypeDesc,
                vd: *const TypeDesc,
                key: *const u8,
            ) -> u8 {
                // SAFETY: caller contract.
                unsafe { ms_rt_hot::$name(m as usize, kd as usize, vd as usize, key as usize) }
            }
        )*};
    }
    contains!(msrt_map_contains_sw8, msrt_map_contains_w8);

    macro_rules! get {
        ($($name:ident),*) => {$(
            pub unsafe fn $name(
                m: *const MapVal,
                kd: *const TypeDesc,
                vd: *const TypeDesc,
                key: *const u8,
                out: *mut u8,
            ) -> u8 {
                // SAFETY: caller contract.
                unsafe {
                    ms_rt_hot::$name(m as usize, kd as usize, vd as usize, key as usize, out as usize)
                }
            }
        )*};
    }
    get!(msrt_map_get_sw8, msrt_map_get_w8);
}
