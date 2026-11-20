//! Forwards of the operating-system functions that `runtime/sys` defines in C (`runtime/symbols/sys.txt`).
//! Each one stands in for the Rust definition in `sys.rs` / `sys_windows.rs`, which is compiled out of the
//! archive; plain `cargo test` keeps the Rust definitions. Contracts are in `runtime/include/ms_rt/sys.h`.

#[cfg(ms_c = "mssys_map_anon")]
pub fn map_anon(len: usize) -> *mut u8 {
    unsafe extern "C" {
        fn mssys_map_anon(len: usize) -> *mut u8;
    }
    // SAFETY: a fresh reservation; failure is null.
    unsafe { mssys_map_anon(len) }
}

#[cfg(ms_c = "mssys_prefer_huge_pages")]
pub fn prefer_huge_pages(p: *mut u8, len: usize) {
    unsafe extern "C" {
        fn mssys_prefer_huge_pages(p: *mut u8, len: usize);
    }
    // SAFETY: advice only; `p..p+len` is a mapping of this process.
    unsafe { mssys_prefer_huge_pages(p, len) }
}

#[cfg(ms_c = "mssys_map_region")]
pub fn map_region(len: usize) -> *mut u8 {
    unsafe extern "C" {
        fn mssys_map_region(len: usize) -> *mut u8;
    }
    // SAFETY: a fresh reservation; failure is null.
    unsafe { mssys_map_region(len) }
}

#[cfg(ms_c = "mssys_commit")]
pub fn commit(p: *mut u8, len: usize) -> bool {
    unsafe extern "C" {
        fn mssys_commit(p: *mut u8, len: usize) -> bool;
    }
    // SAFETY: the range lies inside a reservation of this process.
    unsafe { mssys_commit(p, len) }
}

#[cfg(ms_c = "mssys_commit_guard")]
pub fn commit_guard(p: *mut u8) -> bool {
    unsafe extern "C" {
        fn mssys_commit_guard(p: *mut u8) -> bool;
    }
    // SAFETY: the page lies inside a reservation of this process.
    unsafe { mssys_commit_guard(p) }
}

/// # Safety
/// The range lies inside a live reservation and holds nothing in use.
#[cfg(ms_c = "mssys_release")]
pub unsafe fn release(p: *mut u8, len: usize) {
    unsafe extern "C" {
        fn mssys_release(p: *mut u8, len: usize);
    }
    // SAFETY: forwarded; the caller guarantees the range.
    unsafe { mssys_release(p, len) }
}

/// # Safety
/// The range lies inside a live mapping that nothing is using.
#[cfg(ms_c = "mssys_guard")]
pub unsafe fn guard(p: *mut u8, len: usize) -> bool {
    unsafe extern "C" {
        fn mssys_guard(p: *mut u8, len: usize) -> bool;
    }
    // SAFETY: forwarded; the caller guarantees the range.
    unsafe { mssys_guard(p, len) }
}

/// # Safety
/// The reservation is live and unused.
#[cfg(ms_c = "mssys_unmap")]
pub unsafe fn unmap(p: *mut u8, len: usize) {
    unsafe extern "C" {
        fn mssys_unmap(p: *mut u8, len: usize);
    }
    // SAFETY: forwarded; the caller guarantees the range.
    unsafe { mssys_unmap(p, len) }
}

#[cfg(ms_c = "mssys_monotonic_ns")]
pub fn monotonic_ns() -> i64 {
    unsafe extern "C" {
        fn mssys_monotonic_ns() -> i64;
    }
    // SAFETY: no arguments.
    unsafe { mssys_monotonic_ns() }
}

/// # Safety
/// `start` is a valid entry that ends the thread by returning.
#[cfg(ms_c = "mssys_thread_spawn")]
pub unsafe fn thread_spawn(
    stack: usize,
    start: extern "C" fn(*mut core::ffi::c_void),
    arg: *mut core::ffi::c_void,
) -> usize {
    unsafe extern "C" {
        fn mssys_thread_spawn(
            stack: usize,
            start: extern "C" fn(*mut core::ffi::c_void),
            arg: *mut core::ffi::c_void,
        ) -> usize;
    }
    // SAFETY: forwarded; the caller guarantees the entry.
    unsafe { mssys_thread_spawn(stack, start, arg) }
}

/// # Safety
/// `thread` is a live handle from `thread_spawn`, joined once.
#[cfg(ms_c = "mssys_thread_join")]
pub unsafe fn thread_join(thread: usize) {
    unsafe extern "C" {
        fn mssys_thread_join(thread: usize);
    }
    // SAFETY: forwarded; the caller guarantees the handle.
    unsafe { mssys_thread_join(thread) }
}

#[cfg(ms_c = "mssys_sleep_ms")]
pub fn sleep_ms(ms: u32) {
    unsafe extern "C" {
        fn mssys_sleep_ms(ms: u32);
    }
    // SAFETY: no pointers.
    unsafe { mssys_sleep_ms(ms) }
}
