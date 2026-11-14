//! Freeing deeply nested data in constant stack.
//!
//! The drop glue of a type that can contain itself (a tree, a JSON or TOML value) enters here:
//! below [`LIMIT`] nested drops it runs as before; at the limit it parks the value in a heap
//! block on a worklist (`msrt_drop_defer`) and returns, and the drop that started the nest
//! drains the worklist when it finishes (`msrt_drop_leave`). Each drained value starts a fresh
//! nest, so the stack never holds more than `LIMIT` levels however deep the data is, on the
//! main task and on a 512 KiB task slot alike.
//!
//! Only data deeper than `LIMIT` is reordered: its deepest parts are freed after their
//! siblings instead of before.
use crate::alloc;

/// Nested drops of one type family run recursively before the next one is deferred.
const LIMIT: u32 = 256;

type RunDrop = unsafe extern "C-unwind" fn(*mut u8);

struct State {
    depth: u32,
    draining: bool,
    /// Values waiting to be dropped: the drop function over a heap block holding the value.
    pending: Vec<(RunDrop, *mut u8)>,
}

crate::isolate_static! {
    static STATE: State = State { depth: 0, draining: false, pending: Vec::new() };
}

/// Starts a drop of recursive data: true when the caller must hand the value to
/// [`msrt_drop_defer`] and return without calling [`msrt_drop_leave`].
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C" fn msrt_drop_enter() -> u64 {
    // SAFETY: the state belongs to this thread.
    let s = unsafe { &mut *STATE.ptr() };
    if s.depth >= LIMIT {
        return 1;
    }
    s.depth += 1;
    0
}

/// Parks the heap block `block` holding a value that `run` drops and frees the block of.
///
/// # Safety
/// `run(block)` drops the value in `block`; the runtime frees `block` after it.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_drop_defer(run: RunDrop, block: *mut u8) {
    // SAFETY: the state belongs to this thread.
    unsafe { (*STATE.ptr()).pending.push((run, block)) }
}

/// Ends a drop [`msrt_drop_enter`] let run; the outermost one drops what was deferred.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_drop_leave() {
    let s = STATE.ptr();
    // SAFETY: the state belongs to this thread; a drop run below may enter again, so no borrow
    // of it lives across a call.
    unsafe {
        (*s).depth = (*s).depth.saturating_sub(1);
        if (*s).depth != 0 || (*s).draining {
            return;
        }
        (*s).draining = true;
        while let Some((run, block)) = (*s).pending.pop() {
            run(block);
            alloc::free(block);
        }
        (*s).draining = false;
    }
}

/// Forgets the nesting of drops a guard jump skipped the leaves of.
#[cfg(not(test))]
pub(crate) fn reset() {
    // SAFETY: the state belongs to this thread.
    unsafe {
        let s = STATE.ptr();
        (*s).depth = 0;
        (*s).draining = false;
    }
}
