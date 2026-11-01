//! Park and wake for the task channels of `@std/concurrency/tasks.ms`. The queues live in Manuscript; a task
//! that finds its queue empty (or full) makes a token, records it beside the queue, and parks on
//! it until the other end posts it. A token lasts for one wait, so a post that arrives after the
//! wait ended, or a second post, finds no token and is dropped.
use crate::task;
use std::collections::{HashMap, VecDeque};

use core::ptr::null_mut;
use ms_rt_abi::{Closure, Obj};

/// A group's weak list of live channel leases. Leases retain this tracker, never the reverse.
#[repr(C)]
pub struct ChannelGroup {
    hdr: Obj,
    first: *mut ChannelLease,
    closed: bool,
}

/// Keeps a channel's close callback alive only while a group-end handle still exists.
#[repr(C)]
pub struct ChannelLease {
    hdr: Obj,
    group: *mut ChannelGroup,
    previous: *mut ChannelLease,
    next: *mut ChannelLease,
    linked: bool,
    close: *mut Closure,
}

unsafe fn unlink(lease: *mut ChannelLease) {
    // SAFETY: the isolate owns this live or deferred-drop node and its retained group.
    unsafe {
        if !(*lease).linked {
            return;
        }
        let (previous, next) = ((*lease).previous, (*lease).next);
        if previous.is_null() {
            (*(*lease).group).first = next;
        } else {
            (*previous).next = next;
        }
        if !next.is_null() {
            (*next).previous = previous;
        }
        (*lease).linked = false;
        (*lease).previous = null_mut();
        (*lease).next = null_mut();
    }
}

unsafe extern "C" fn drop_group(obj: *mut Obj) {
    let group = obj.cast::<ChannelGroup>();
    // SAFETY: every linked lease retains the group, so its final release has no children.
    unsafe {
        debug_assert!((*group).first.is_null());
        crate::alloc::free(group.cast());
    }
}

unsafe extern "C" fn drop_lease(obj: *mut Obj) {
    let lease = obj.cast::<ChannelLease>();
    // SAFETY: the final release owns this node; unlink before dropping anything reentrant.
    unsafe {
        unlink(lease);
        crate::obj::release((*lease).close.cast());
        crate::obj::release((*lease).group.cast());
        crate::alloc::free(lease.cast());
    }
}

unsafe fn close_channel(close: *mut Closure) {
    if close.is_null() {
        return;
    }
    // SAFETY: this owns the capture-free-argument closure; the private callback cannot suspend
    // or unwind. It only closes private lanes after their tasks have completed cleanup.
    unsafe {
        let call: unsafe extern "C-unwind" fn(*mut Closure) = core::mem::transmute((*close).code);
        call(close);
        crate::obj::release(close.cast());
    }
}

/// Creates the private channel tracker of a TaskGroup.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_channel_group_new() -> *mut ChannelGroup {
    // SAFETY: a fresh object, initialized before being returned.
    unsafe {
        let group =
            crate::obj::new_obj(size_of::<ChannelGroup>(), drop_group).cast::<ChannelGroup>();
        (*group).first = null_mut();
        (*group).closed = false;
        group
    }
}

/// Tracks a channel without retaining its lease from the group. Returns one owned lease.
///
/// # Safety
/// Both arguments must be live on this isolate. `close` is the private, non-suspending,
/// non-unwinding lane-close callback; it is retained until group close or final lease release.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_channel_group_add(
    group: *mut ChannelGroup,
    close: *mut Closure,
) -> *mut ChannelLease {
    // SAFETY: the caller lends live objects; the lease owns its new references.
    unsafe {
        crate::obj::retain(group.cast());
        crate::obj::retain(close.cast());
        let lease =
            crate::obj::new_obj(size_of::<ChannelLease>(), drop_lease).cast::<ChannelLease>();
        (*lease).group = group;
        (*lease).previous = null_mut();
        (*lease).next = null_mut();
        (*lease).linked = false;
        (*lease).close = close;
        if (*group).closed {
            (*lease).close = null_mut();
            close_channel(close);
            return lease;
        }
        let first = (*group).first;
        (*lease).next = first;
        (*lease).linked = true;
        if !first.is_null() {
            (*first).previous = lease;
        }
        (*group).first = lease;
        lease
    }
}

/// Closes every channel still handed out by the group, including collected task handles.
///
/// # Safety
/// `group` must be live on this isolate. Its tasks have finished cleanup before this call.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_channel_group_close(group: *mut ChannelGroup) {
    // SAFETY: the tracker and its callbacks belong to this isolate.
    unsafe {
        if (*group).closed {
            return;
        }
        crate::obj::retain(group.cast());
        (*group).closed = true;
        while !(*group).first.is_null() {
            let lease = (*group).first;
            unlink(lease);
            let close = core::mem::replace(&mut (*lease).close, null_mut());
            // Do not retain or touch the lease again: its callback can drop it, and a deferred
            // zero-count lease may already have its count word repurposed by Obj::drop_slow.
            close_channel(close);
        }
        crate::obj::release(group.cast());
    }
}

crate::isolate_static! {
    /// Tokens of tasks waiting on a key (the identity of something they wait for), oldest first.
    static WAIT_QUEUES: Option<HashMap<usize, VecDeque<i64>>> = None;
}

crate::isolate_static! {
    /// The `Shared` boxes held for calls, by box identity, in the order the holds began. Calls
    /// nest, so a release usually ends the last entry.
    static HOLDERS: Vec<(usize, Hold)> = Vec::new();
}

/// A call's hold of a `Shared` box.
#[derive(Clone, Copy)]
struct Hold {
    /// The task that holds the box.
    task: u64,
    /// The box's in-use flag.
    taken: usize,
    /// The depth of guarded calls the task was in when it took the hold.
    depth: usize,
}

fn holders() -> &'static mut Vec<(usize, Hold)> {
    // SAFETY: only the scheduler thread of an isolate reaches its holders.
    unsafe { &mut *HOLDERS.ptr() }
}

fn hold_of(key: usize) -> Option<usize> {
    holders().iter().rposition(|(k, _)| *k == key)
}

/// Marks the box `key` in use by the running task for a call, through its flag `taken`, until
/// `msrt_shared_release`, or until the task is cancelled or faults inside the call.
///
/// # Safety
/// `taken` is the in-use flag of the live box `key`, and the box outlives the hold.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_shared_hold(key: i64, taken: *mut u8) {
    // SAFETY: the caller passes the flag of a live box.
    unsafe { *taken = 1 };
    let hold = Hold {
        task: task::current_handle(),
        taken: taken as usize,
        depth: crate::fault::guard_depth(),
    };
    holders().push((key as usize, hold));
}

/// Ends the running task's hold of the box `key` when its call returns, and wakes the oldest task
/// waiting for the box.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_shared_release(key: i64) {
    end_hold(key as usize);
}

/// Ends the holds of the running task's calls that a cancellation or fault leaving guard depth
/// `depth` abandons.
pub(crate) fn end_abandoned_holds(depth: usize) {
    if holders().is_empty() {
        return;
    }
    let me = task::current_handle();
    let abandoned: Vec<usize> = holders()
        .iter()
        .filter(|(_, h)| h.task == me && h.depth >= depth)
        .map(|(key, _)| *key)
        .rev()
        .collect();
    for key in abandoned {
        end_hold(key);
    }
}

/// Clears the hold of the box whose identity is `key` and wakes the oldest task waiting for it.
fn end_hold(key: usize) {
    if let Some(at) = hold_of(key) {
        let (_, hold) = holders().remove(at);
        // SAFETY: the box outlives its hold (`msrt_shared_hold`).
        unsafe { *(hold.taken as *mut u8) = 0 };
    }
    if !queues().is_empty() {
        msrt_waitq_wake(key as i64);
    }
}

/// Called when the box `key` is in use. Another task's hold: waits until it is released (the
/// caller checks again). A hold of the running task, or an update without a hold (which only
/// the running task can be in), would wait on itself: faults.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_shared_wait(key: i64) {
    let me = task::current_handle();
    match hold_of(key as usize).map(|at| holders()[at].1) {
        Some(hold) if hold.task != me => {}
        _ => crate::fault::fault(
            b"a Shared value was used again inside a call on it from the same task; finish the call first, or change the value inside that call",
        ),
    }
    let token = msrt_channel_token();
    msrt_waitq_push(key, token);
    // A task cancelled while it waits leaves the queue, or passes on a wake already chosen for it.
    // Cancellation leaves by a jump, so this is a cleanup entry rather than a destructor.
    let mut leave = || {
        if msrt_waitq_remove(key, token) == 0 {
            msrt_waitq_wake(key);
        }
    };
    crate::fault::with_cleanup(&mut leave, || msrt_channel_park(token));
}

fn queues() -> &'static mut HashMap<usize, VecDeque<i64>> {
    // SAFETY: only the scheduler thread of an isolate reaches its queues.
    unsafe { (*WAIT_QUEUES.ptr()).get_or_insert_with(HashMap::new) }
}

/// Drops every queue; part of the scheduler teardown.
pub(crate) fn reset_wait_queues() {
    // SAFETY: as in `queues`.
    unsafe { *WAIT_QUEUES.ptr() = None };
    // SAFETY: as in `holders`.
    unsafe { (*HOLDERS.ptr()).clear() };
}

/// The address as an integer: the identity of a box for the wait queues below.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_addr_id(addr: *const u8) -> i64 {
    addr as usize as i64
}

/// Queues `token` (from `msrt_channel_token`) behind the tasks already waiting on `key`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_waitq_push(key: i64, token: i64) {
    queues().entry(key as usize).or_default().push_back(token);
}

/// Posts the oldest token queued on `key` and drops it from the queue. Returns 1 when there was
/// one, 0 when nobody waits.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_waitq_wake(key: i64) -> i64 {
    let q = queues();
    let Some(waiting) = q.get_mut(&(key as usize)) else {
        return 0;
    };
    let token = waiting.pop_front();
    if waiting.is_empty() {
        q.remove(&(key as usize));
    }
    match token {
        Some(token) => {
            msrt_channel_post(token);
            1
        }
        None => 0,
    }
}

/// Takes `token` out of the queue on `key`. Returns 1 when it was still queued, 0 when a wake
/// already took it.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_waitq_remove(key: i64, token: i64) -> i64 {
    let q = queues();
    let Some(waiting) = q.get_mut(&(key as usize)) else {
        return 0;
    };
    let found = waiting.iter().position(|t| *t == token);
    if let Some(at) = found {
        waiting.remove(at);
    }
    if waiting.is_empty() {
        q.remove(&(key as usize));
    }
    found.is_some() as i64
}

/// Makes a token for one wait and returns its id, never 0.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_channel_token() -> i64 {
    // SAFETY: single threaded scheduler.
    unsafe { task::msrt_token_new(0) as i64 }
}

/// Parks the current task until `token` is posted, then frees it. A post made before the park
/// returns at once. If the task is cancelled while it waits, the token is freed and the
/// cancellation unwinds the task.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_channel_park(token: i64) {
    // SAFETY: single threaded scheduler; a null `value_out` is allowed.
    let woke = unsafe { task::msrt_token_park(token as u64, -1, core::ptr::null_mut()) };
    // SAFETY: the park ended, so no task waits on the token.
    unsafe { task::msrt_token_free(token as u64) };
    if woke != 0 {
        crate::fault::msrt_cancelled();
    }
}

/// Wakes the task parked on `token`, or keeps the post for its park. A token that has already
/// been posted or freed is left alone.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_channel_post(token: i64) {
    // SAFETY: single threaded scheduler.
    unsafe { task::msrt_token_post(token as u64, 0) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::lock;

    #[repr(C)]
    struct TestClose {
        closure: Closure,
        called: *mut usize,
        dropped: *mut usize,
        release: [*mut Obj; 3],
        reenter: *mut ChannelGroup,
    }

    unsafe extern "C" fn drop_test_close(obj: *mut Obj) {
        // SAFETY: each test keeps the counter alive until its closures are released.
        unsafe {
            *(*obj.cast::<TestClose>()).dropped += 1;
            crate::alloc::free(obj.cast());
        }
    }

    unsafe extern "C-unwind" fn test_close(closure: *mut Closure) {
        // SAFETY: a TestClose's callback owns these designated references and runs once.
        unsafe {
            let close = closure.cast::<TestClose>();
            *(*close).called += 1;
            for obj in (*close).release {
                crate::obj::release(obj);
            }
            if !(*close).reenter.is_null() {
                msrt_channel_group_close((*close).reenter);
            }
        }
    }

    fn callback(called: &mut usize, dropped: &mut usize) -> *mut Closure {
        // SAFETY: a fresh test closure, initialized before it escapes.
        unsafe {
            let close =
                crate::obj::new_obj(size_of::<TestClose>(), drop_test_close).cast::<TestClose>();
            (*close).closure.code = test_close as *const u8;
            (*close).called = called;
            (*close).dropped = dropped;
            (*close).release = [null_mut(); 3];
            (*close).reenter = null_mut();
            close.cast()
        }
    }

    #[test]
    fn last_channel_drop_releases_tracking_without_another_spawn() {
        let _g = lock();
        let (mut called, mut dropped) = (0, 0);
        let group = msrt_channel_group_new();
        // SAFETY: all objects belong to this test's isolate and all owned references are released.
        unsafe {
            for _ in 0..10_000 {
                let close = callback(&mut called, &mut dropped);
                let lease = msrt_channel_group_add(group, close);
                crate::obj::release(close.cast());
                crate::obj::retain(lease.cast());
                crate::obj::release(lease.cast());
                assert_eq!((*group).first, lease);
                crate::obj::release(lease.cast());
                assert!(
                    (*group).first.is_null(),
                    "an idle group retained a dead channel"
                );
            }
            msrt_channel_group_close(group);
            crate::obj::release(group.cast());
        }
        assert_eq!(called, 0);
        assert_eq!(dropped, 10_000);
    }

    #[test]
    fn group_close_releases_callbacks_while_channel_handles_remain() {
        let _g = lock();
        let (mut called, mut dropped) = (0, 0);
        let group = msrt_channel_group_new();
        // SAFETY: the retained leases remain live through both closes and are then released.
        unsafe {
            let close = callback(&mut called, &mut dropped);
            let a = msrt_channel_group_add(group, close);
            let b = msrt_channel_group_add(group, close);
            crate::obj::release(close.cast());
            msrt_channel_group_close(group);
            assert!((*group).first.is_null());
            assert!((*a).close.is_null());
            assert!((*b).close.is_null());
            assert_eq!(called, 2);
            assert_eq!(dropped, 1);
            msrt_channel_group_close(group);
            crate::obj::release(a.cast());
            crate::obj::release(b.cast());
            crate::obj::release(group.cast());
        }
        assert_eq!(called, 2);
        assert_eq!(dropped, 1);
    }

    #[test]
    fn a_channel_created_after_group_close_is_closed_immediately() {
        let _g = lock();
        let (mut called, mut dropped) = (0, 0);
        let group = msrt_channel_group_new();
        // SAFETY: live group and closure; the late lease is released once.
        unsafe {
            msrt_channel_group_close(group);
            let close = callback(&mut called, &mut dropped);
            let lease = msrt_channel_group_add(group, close);
            crate::obj::release(close.cast());
            assert!((*group).first.is_null());
            assert!((*lease).close.is_null());
            crate::obj::release(lease.cast());
            crate::obj::release(group.cast());
        }
        assert_eq!(called, 1);
        assert_eq!(dropped, 1);
    }

    #[test]
    fn a_close_callback_can_drop_its_lease_siblings_and_group_owner() {
        let _g = lock();
        let (mut called, mut dropped) = (0, 0);
        let group = msrt_channel_group_new();
        // SAFETY: the callback consumes the references placed in release; close retains the tracker.
        unsafe {
            let other_close = callback(&mut called, &mut dropped);
            let other = msrt_channel_group_add(group, other_close);
            crate::obj::release(other_close.cast());
            let close = callback(&mut called, &mut dropped);
            let lease = msrt_channel_group_add(group, close);
            (*close.cast::<TestClose>()).release = [lease.cast(), other.cast(), group.cast()];
            (*close.cast::<TestClose>()).reenter = group;
            crate::obj::release(close.cast());
            msrt_channel_group_close(group);
        }
        assert_eq!(called, 1, "the dropped sibling must not be called");
        assert_eq!(dropped, 2);
    }

    #[repr(C)]
    struct NestedDrop {
        hdr: Obj,
        child: *mut Obj,
        group: *mut ChannelGroup,
        lease: *mut ChannelLease,
        preserved: *mut bool,
        dropped: *mut usize,
        pending: *mut Obj,
    }

    #[repr(C)]
    struct PendingDrop {
        hdr: Obj,
        dropped: *mut usize,
    }

    unsafe extern "C" fn drop_pending(obj: *mut Obj) {
        // SAFETY: this test object owns its allocation and keeps its counter live until drained.
        unsafe {
            *(*obj.cast::<PendingDrop>()).dropped += 1;
            crate::alloc::free(obj.cast());
        }
    }

    #[inline(never)]
    unsafe fn close_with_deferred_lease(node: *mut NestedDrop) {
        // SAFETY: the deepest node owns the lease and keeps the group and counters live.
        unsafe {
            crate::obj::release((*node).pending);
            crate::obj::release((*node).lease.cast());
            // At the drop-depth limit the lease is pending, with rc reused as its next link.
            let link = (*node).pending as usize;
            assert_eq!((*(*node).lease).hdr.rc, link);
            msrt_channel_group_close((*node).group);
            *(*node).preserved = (*(*node).lease).hdr.rc == link;
        }
    }

    unsafe extern "C" fn drop_nested(obj: *mut Obj) {
        // SAFETY: this node owns its child; the deepest node owns the designated lease.
        unsafe {
            let node = obj.cast::<NestedDrop>();
            if !(*node).child.is_null() {
                crate::obj::release((*node).child);
            } else {
                // Keep assertion formatting and close's locals out of all 4096 recursive frames.
                close_with_deferred_lease(node);
            }
            *(*node).dropped += 1;
            crate::alloc::free(obj.cast());
        }
    }

    fn check_group_close_with_deferred_lease(with_pending: bool) {
        let _g = lock();
        let (mut called, mut dropped) = (0, 0);
        let mut preserved = false;
        let mut nodes_dropped = 0;
        let mut pending_dropped = 0;
        let group = msrt_channel_group_new();
        // SAFETY: the chain owns the lease and every node; the group stays live until it drains.
        unsafe {
            let close = callback(&mut called, &mut dropped);
            let lease = msrt_channel_group_add(group, close);
            crate::obj::release(close.cast());
            let pending = if with_pending {
                let pending = crate::obj::new_obj(size_of::<PendingDrop>(), drop_pending)
                    .cast::<PendingDrop>();
                (*pending).dropped = &raw mut pending_dropped;
                pending.cast()
            } else {
                null_mut()
            };
            let mut child = null_mut();
            for _ in 0..4096 {
                let node =
                    crate::obj::new_obj(size_of::<NestedDrop>(), drop_nested).cast::<NestedDrop>();
                (*node).child = child;
                (*node).group = group;
                (*node).lease = lease;
                (*node).preserved = &raw mut preserved;
                (*node).dropped = &raw mut nodes_dropped;
                (*node).pending = pending;
                child = node.cast();
            }
            crate::obj::release(child);
            assert!((*group).first.is_null());
            crate::obj::release(group.cast());
        }
        assert!(
            preserved,
            "group close changed the pending object's link word"
        );
        assert_eq!(called, 1);
        assert_eq!(dropped, 1);
        assert_eq!(nodes_dropped, 4096);
        assert_eq!(pending_dropped, usize::from(with_pending));
    }

    #[test]
    fn group_close_does_not_resurrect_a_lease_with_a_deferred_drop() {
        check_group_close_with_deferred_lease(false);
    }

    #[test]
    fn group_close_preserves_a_deferred_leases_nonzero_pending_link() {
        check_group_close_with_deferred_lease(true);
    }

    #[test]
    fn wait_queues_wake_in_order_and_drop_removed_tokens() {
        let _g = lock();
        task::teardown();
        let (a, b, c) = (
            msrt_channel_token(),
            msrt_channel_token(),
            msrt_channel_token(),
        );
        msrt_waitq_push(7, a);
        msrt_waitq_push(7, b);
        msrt_waitq_push(7, c);
        assert_eq!(msrt_waitq_remove(7, b), 1);
        assert_eq!(msrt_waitq_remove(7, b), 0);
        assert_eq!(msrt_waitq_wake(8), 0);
        // The first wake posts `a`: its park returns at once.
        assert_eq!(msrt_waitq_wake(7), 1);
        msrt_channel_park(a);
        assert_eq!(msrt_waitq_wake(7), 1);
        msrt_channel_park(c);
        assert_eq!(msrt_waitq_wake(7), 0);
        assert!(queues().is_empty());
        task::teardown();
    }

    #[test]
    fn a_post_before_the_park_returns_at_once_and_frees_the_token() {
        let _g = lock();
        task::teardown();
        let token = msrt_channel_token();
        assert_ne!(token, 0);
        msrt_channel_post(token);
        msrt_channel_park(token);
        // A late post to the freed token is dropped, and the slot is reused under a new id.
        msrt_channel_post(token);
        assert_ne!(msrt_channel_token(), token);
        task::teardown();
    }
}
