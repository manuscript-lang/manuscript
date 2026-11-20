//! Forwards of the operating-system functions that `runtime/sys` defines in C (`runtime/symbols/sys.txt`).
//! Each one stands in for the Rust definition in `sys.rs` / `sys_windows.rs`, which is compiled out of the
//! archive; plain `cargo test` keeps the Rust definitions. Contracts are in `runtime/include/ms_rt/sys.h`.

#[cfg(ms_c = "ms_sys_map_anon")]
pub fn map_anon(len: usize) -> *mut u8 {
    unsafe extern "C" {
        fn ms_sys_map_anon(len: usize) -> *mut u8;
    }
    // SAFETY: a fresh reservation; failure is null.
    unsafe { ms_sys_map_anon(len) }
}

#[cfg(ms_c = "ms_sys_prefer_huge_pages")]
pub fn prefer_huge_pages(p: *mut u8, len: usize) {
    unsafe extern "C" {
        fn ms_sys_prefer_huge_pages(p: *mut u8, len: usize);
    }
    // SAFETY: advice only; `p..p+len` is a mapping of this process.
    unsafe { ms_sys_prefer_huge_pages(p, len) }
}

#[cfg(ms_c = "ms_sys_map_region")]
pub fn map_region(len: usize) -> *mut u8 {
    unsafe extern "C" {
        fn ms_sys_map_region(len: usize) -> *mut u8;
    }
    // SAFETY: a fresh reservation; failure is null.
    unsafe { ms_sys_map_region(len) }
}

#[cfg(ms_c = "ms_sys_commit")]
pub fn commit(p: *mut u8, len: usize) -> bool {
    unsafe extern "C" {
        fn ms_sys_commit(p: *mut u8, len: usize) -> bool;
    }
    // SAFETY: the range lies inside a reservation of this process.
    unsafe { ms_sys_commit(p, len) }
}

#[cfg(ms_c = "ms_sys_commit_guard")]
pub fn commit_guard(p: *mut u8) -> bool {
    unsafe extern "C" {
        fn ms_sys_commit_guard(p: *mut u8) -> bool;
    }
    // SAFETY: the page lies inside a reservation of this process.
    unsafe { ms_sys_commit_guard(p) }
}

/// # Safety
/// The range lies inside a live reservation and holds nothing in use.
#[cfg(ms_c = "ms_sys_release")]
pub unsafe fn release(p: *mut u8, len: usize) {
    unsafe extern "C" {
        fn ms_sys_release(p: *mut u8, len: usize);
    }
    // SAFETY: forwarded; the caller guarantees the range.
    unsafe { ms_sys_release(p, len) }
}

/// # Safety
/// The range lies inside a live mapping that nothing is using.
#[cfg(ms_c = "ms_sys_guard")]
pub unsafe fn guard(p: *mut u8, len: usize) -> bool {
    unsafe extern "C" {
        fn ms_sys_guard(p: *mut u8, len: usize) -> bool;
    }
    // SAFETY: forwarded; the caller guarantees the range.
    unsafe { ms_sys_guard(p, len) }
}

/// # Safety
/// The reservation is live and unused.
#[cfg(ms_c = "ms_sys_unmap")]
pub unsafe fn unmap(p: *mut u8, len: usize) {
    unsafe extern "C" {
        fn ms_sys_unmap(p: *mut u8, len: usize);
    }
    // SAFETY: forwarded; the caller guarantees the range.
    unsafe { ms_sys_unmap(p, len) }
}

#[cfg(ms_c = "ms_sys_monotonic_ns")]
pub fn monotonic_ns() -> i64 {
    unsafe extern "C" {
        fn ms_sys_monotonic_ns() -> i64;
    }
    // SAFETY: no arguments.
    unsafe { ms_sys_monotonic_ns() }
}

/// # Safety
/// `start` is a valid entry that ends the thread by returning.
#[cfg(ms_c = "ms_sys_thread_spawn")]
pub unsafe fn thread_spawn(
    stack: usize,
    start: extern "C" fn(*mut core::ffi::c_void),
    arg: *mut core::ffi::c_void,
) -> usize {
    unsafe extern "C" {
        fn ms_sys_thread_spawn(
            stack: usize,
            start: extern "C" fn(*mut core::ffi::c_void),
            arg: *mut core::ffi::c_void,
        ) -> usize;
    }
    // SAFETY: forwarded; the caller guarantees the entry.
    unsafe { ms_sys_thread_spawn(stack, start, arg) }
}

/// # Safety
/// `thread` is a live handle from `thread_spawn`, joined once.
#[cfg(ms_c = "ms_sys_thread_join")]
pub unsafe fn thread_join(thread: usize) {
    unsafe extern "C" {
        fn ms_sys_thread_join(thread: usize);
    }
    // SAFETY: forwarded; the caller guarantees the handle.
    unsafe { ms_sys_thread_join(thread) }
}

#[cfg(ms_c = "ms_sys_sleep_ms")]
pub fn sleep_ms(ms: u32) {
    unsafe extern "C" {
        fn ms_sys_sleep_ms(ms: u32);
    }
    // SAFETY: no pointers.
    unsafe { ms_sys_sleep_ms(ms) }
}
