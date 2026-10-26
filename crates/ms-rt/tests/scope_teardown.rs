//! Count Rust heap allocations: program-allocation counters deliberately exclude these buffers.
#![allow(unsafe_code)]

use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;

thread_local! {
    static TRACK: Cell<bool> = const { Cell::new(false) };
    static LIVE_BYTES: Cell<isize> = const { Cell::new(0) };
}

struct CountingHeap;

fn note(delta: isize) {
    // Count only this test's thread, excluding concurrent test-harness allocations.
    if TRACK.try_with(Cell::get).unwrap_or(false) {
        let _ = LIVE_BYTES.try_with(|bytes| bytes.set(bytes.get() + delta));
    }
}

// SAFETY: every allocation is delegated to System with its original layout.
unsafe impl GlobalAlloc for CountingHeap {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        // SAFETY: forwarded allocator contract.
        let ptr = unsafe { System.alloc(layout) };
        if !ptr.is_null() {
            note(layout.size() as isize);
        }
        ptr
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        note(-(layout.size() as isize));
        // SAFETY: forwarded allocator contract.
        unsafe { System.dealloc(ptr, layout) };
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        // SAFETY: forwarded allocator contract.
        let ptr = unsafe { System.realloc(ptr, layout, size) };
        if !ptr.is_null() {
            note(size as isize - layout.size() as isize);
        }
        ptr
    }
}

#[global_allocator]
static HEAP: CountingHeap = CountingHeap;

#[test]
fn scheduler_teardown_releases_closed_scope_tables() {
    ms_rt::isolate::set_main();
    let warmup = ms_rt::scope::msrt_scope_new();
    ms_rt::scope::msrt_scope_close(warmup);
    ms_rt::task::teardown();

    LIVE_BYTES.with(|bytes| bytes.set(0));
    TRACK.with(|track| track.set(true));
    let scopes: Vec<_> = (0..1000).map(|_| ms_rt::scope::msrt_scope_new()).collect();
    for scope in &scopes {
        ms_rt::scope::msrt_scope_close(*scope);
    }
    drop(scopes);
    ms_rt::task::teardown();
    let retained = LIVE_BYTES.with(Cell::get);
    TRACK.with(|track| track.set(false));

    assert_eq!(
        retained, 0,
        "closed scope tables survived scheduler teardown"
    );
}
