use super::*;
use crate::global::Process;
use crate::testutil::lock;

static LOG: Process<[u8; 16]> = Process::new([0; 16]);
static LOG_N: Process<usize> = Process::new(0);

/// A binding held across another `sched()` access must stay valid; Miri's Stacked Borrows
/// rejected the previous `&'static mut` return here.
#[test]
fn scheduler_handles_do_not_alias() {
    let _g = lock();
    let mut held = sched();
    let before = held.live;
    sched().live += 1;
    held.live += 1;
    assert_eq!(held.live, before + 2);
    sched().live -= 2;
}

fn note(v: u8) {
    // SAFETY: tests hold the lock; the log has room for 16 entries.
    unsafe {
        let n = *LOG_N.ptr();
        (*LOG.ptr())[n] = v;
        *LOG_N.ptr() = n + 1;
    }
}

unsafe extern "C-unwind" fn counter(arg: *mut u8) {
    let id = arg as usize as u8;
    for i in 0..3 {
        note(id * 10 + i);
        // SAFETY: called from a running task.
        unsafe { msrt_task_yield() };
    }
}

unsafe extern "C-unwind" fn sleeper(arg: *mut u8) {
    // SAFETY: called from a running task.
    let r = unsafe { msrt_task_sleep(arg as usize as i64 * 1_000_000) };
    note(if r == WAIT_TIMEOUT {
        arg as usize as u8
    } else {
        99
    });
}

#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn tasks_interleave_sleep_and_join() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock; every handle is joined once.
    unsafe {
        *LOG_N.ptr() = 0;
        let a = msrt_task_spawn(counter, core::ptr::without_provenance_mut(1), 0, 0);
        let b = msrt_task_spawn(counter, core::ptr::without_provenance_mut(2), 0, 0);
        assert_eq!(msrt_task_join(a, null_mut()), 0);
        assert_eq!(msrt_task_join(b, null_mut()), 0);
        assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[10, 20, 11, 21, 12, 22]);

        *LOG_N.ptr() = 0;
        let slow = msrt_task_spawn(sleeper, core::ptr::without_provenance_mut(20), 0, 0);
        let fast = msrt_task_spawn(sleeper, core::ptr::without_provenance_mut(5), 0, 0);
        assert_eq!(msrt_task_join(slow, null_mut()), 0);
        assert_eq!(msrt_task_join(fast, null_mut()), 0);
        assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[5, 20]);
        assert_eq!(msrt_task_count(), 1);
    }
    teardown();
}

unsafe extern "C-unwind" fn deadlocked_token(arg: *mut u8) {
    // SAFETY: the test owns the live token and deliberately supplies no completion.
    unsafe { msrt_token_park(arg as u64, -1, null_mut()) };
}

unsafe extern "C-unwind" fn deadlocked_join(arg: *mut u8) {
    // SAFETY: the test owns the live task, which has no matching completion.
    unsafe { msrt_task_join(arg as u64, null_mut()) };
}

#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn a_deadlocked_token_wait_releases_its_registration() {
    let _g = lock();
    teardown();
    // SAFETY: the guard contains the deliberate deadlock and all state is isolate-local.
    unsafe {
        let token = msrt_token_new(0);
        let status = fault::msrt_guard_call(deadlocked_token, token as *mut u8, null_mut());
        let waiter = token_mut(&mut sched(), token).unwrap().waiter;
        let running = (*sched().cur).state == State::Running;
        teardown();
        assert_eq!(status, 1);
        assert_eq!(waiter, 0, "a faulted wait must release its token");
        assert!(running, "fault cleanup must run as a running task");
    }
}

#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn a_deadlocked_join_releases_the_targets_joiner() {
    let _g = lock();
    teardown();
    // SAFETY: the guard contains the deliberate deadlock and teardown releases the task.
    unsafe {
        let token = msrt_token_new(0);
        let target = msrt_task_spawn(deadlocked_token, token as *mut u8, 0, 0);
        msrt_task_yield();
        let status = fault::msrt_guard_call(deadlocked_join, target as *mut u8, null_mut());
        let joiner = (*lookup(target)).joiner;
        let running = (*sched().cur).state == State::Running;
        teardown();
        assert_eq!(status, 1);
        assert_eq!(joiner, 0, "a faulted join must stop claiming its target");
        assert!(running, "fault cleanup must run as a running task");
    }
}

#[test]
#[cfg(unix)]
fn idle_trim_keeps_the_newest_pooled_stacks_warm() {
    let _g = lock();
    teardown();
    // SAFETY: a fabricated pool entry is a mapped slot that no task uses.
    unsafe {
        let n = STACK_POOL_WARM + 3;
        let slots: Vec<usize> = (0..n).map(|_| stack::create(SLOT) as usize).collect();
        for &base in &slots {
            assert!(base != 0);
            // Touch the top page, where a stack's first frames live.
            *((base + SLOT - 4096) as *mut u8) = 1;
            release_stack(base, SLOT);
        }
        trim_idle_stacks();
        assert_eq!(sched().pool_clean, 3);
        // The warm stacks keep their contents. A trimmed stack's pages went back to the
        // system, but macOS frees them lazily, so what they read as is unspecified; they
        // must stay writable.
        for (at, &base) in slots.iter().enumerate() {
            let page = (base + SLOT - 4096) as *mut u8;
            if at >= 3 {
                assert_eq!(*page, 1, "warm stack {at}");
            }
            *page = 2;
            assert_eq!(*page, 2, "stack {at} stays usable");
        }
        // Taking a stack back lowers the clean mark only when an older entry moves.
        let _ = alloc_stack(SLOT);
        assert_eq!(sched().pool_clean, 3);
        teardown();
    }
}

#[test]
#[cfg(unix)]
fn teardown_unmaps_pooled_task_stacks() {
    let _g = lock();
    teardown();
    // SAFETY: the entry ignores its argument and the test joins the task once.
    unsafe {
        let h = msrt_task_spawn(long_wait, null_mut(), 0, 0);
        msrt_task_cancel(h);
        assert_eq!(msrt_task_join(h, null_mut()), 0);
        let pooled = sched()
            .pool
            .iter()
            .map(|&(base, _)| base)
            .collect::<Vec<_>>();
        assert!(
            !pooled.is_empty(),
            "the completed stack must enter the pool"
        );
        let page_size = libc::sysconf(libc::_SC_PAGESIZE);
        assert!(page_size > 0);
        let page_size = page_size as usize;
        for &base in &pooled {
            assert_eq!(
                libc::msync(base as *mut core::ffi::c_void, page_size, libc::MS_ASYNC),
                0,
                "the control stack must still be mapped before teardown"
            );
        }
        teardown();
        for base in pooled {
            // Darwin mincore reports residency even for holes. msync checks mappings:
            // an unmapped page must fail with ENOMEM on both Darwin and Linux.
            for offset in (0..SLOT).step_by(page_size) {
                assert_eq!(
                    libc::msync(
                        (base + offset) as *mut core::ffi::c_void,
                        page_size,
                        libc::MS_ASYNC
                    ),
                    -1,
                    "teardown left a task stack page mapped"
                );
                assert_eq!(
                    std::io::Error::last_os_error().raw_os_error(),
                    Some(libc::ENOMEM)
                );
            }
        }
    }
}

/// Parks on the token in `arg`, then writes what it found on its stack into the token's
/// value slot, so a hibernation that lost or moved the stack shows.
unsafe extern "C-unwind" fn park_on_token(arg: *mut u8) {
    let token = arg as usize as u64;
    let marker = std::hint::black_box([0x5a5a_u16; 512]);
    let mut value = 0;
    // SAFETY: called on a live task; the test posts the token.
    unsafe {
        msrt_token_park(token, -1, &mut value);
        let sum: u64 = std::hint::black_box(&marker)
            .iter()
            .map(|&m| m as u64)
            .sum();
        assert_eq!(sum, 0x5a5a * 512, "stack contents survived hibernation");
    }
}

#[test]
fn parked_tasks_hibernate_and_resume_on_the_same_stack() {
    let _g = lock();
    teardown();
    // SAFETY: the test owns the token and joins the task.
    unsafe {
        let token = msrt_token_new(0);
        let h = msrt_task_spawn(park_on_token, token as usize as *mut u8, 0, 0);
        msrt_task_yield();
        let t = lookup(h);
        assert!((*t).state == State::Waiting);
        assert!((*t).frozen.is_null());
        // Two idle rounds after the park: the task gives its pages back.
        hibernate_idle();
        hibernate_idle();
        hibernate_idle();
        assert!(
            !(*t).frozen.is_null(),
            "a task parked for two rounds hibernates"
        );
        let top = stack_top((*t).stack as usize, (*t).stack_len);
        assert_eq!((*t).frozen_len, top - (*t).sp);
        // The copy holds the parked frames: the marker array `park_on_token` keeps live.
        let copy = core::slice::from_raw_parts((*t).frozen, (*t).frozen_len);
        let markers = copy
            .as_chunks::<2>()
            .0
            .iter()
            .filter(|w| w == &&[0x5a, 0x5a])
            .count();
        assert!(
            markers >= 512,
            "the frozen copy holds the stack ({markers} marker words)"
        );
        msrt_token_post(token, 7);
        assert_eq!(msrt_task_join(h, null_mut()), 0);
        assert!(sched().pool.iter().any(|&(base, _)| base == top - SLOT));
        msrt_token_free(token);
        teardown();
    }
}

static PARK_RESULT: core::sync::atomic::AtomicU32 = core::sync::atomic::AtomicU32::new(0);

/// Parks on the read end of the pipe in `arg` and records what the wait returned.
unsafe extern "C-unwind" fn park_on_fd(arg: *mut u8) {
    let fd = arg as usize as i32;
    // SAFETY: called on a live task; the test cancels it.
    let got = unsafe { msrt_task_wait_fd(fd, WAIT_READ, -1) };
    PARK_RESULT.store(got, Ordering::Relaxed);
}

/// A connected socket pair, the waitable descriptor every platform has.
fn socket_pair() -> (std::net::TcpStream, std::net::TcpStream) {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let client = std::net::TcpStream::connect(listener.local_addr().unwrap()).unwrap();
    let (server, _) = listener.accept().unwrap();
    (client, server)
}

fn raw_socket(stream: &std::net::TcpStream) -> i32 {
    #[cfg(unix)]
    {
        std::os::fd::AsRawFd::as_raw_fd(stream)
    }
    #[cfg(windows)]
    {
        std::os::windows::io::AsRawSocket::as_raw_socket(stream) as i32
    }
}

#[test]
fn a_hibernating_task_sees_its_cancellation() {
    let _g = lock();
    teardown();
    let (client, _server) = socket_pair();
    let fd = raw_socket(&client);
    // SAFETY: the test keeps the sockets open and joins the task.
    unsafe {
        PARK_RESULT.store(0, Ordering::Relaxed);
        let h = msrt_task_spawn(park_on_fd, fd as usize as *mut u8, 0, 0);
        msrt_task_yield();
        let t = lookup(h);
        assert!((*t).state == State::Waiting);
        hibernate_idle();
        hibernate_idle();
        hibernate_idle();
        assert!(!(*t).frozen.is_null(), "the parked task hibernates");
        msrt_task_cancel(h);
        assert_eq!(msrt_task_join(h, null_mut()), 0);
        assert_eq!(
            PARK_RESULT.load(Ordering::Relaxed) & WAIT_CANCELLED,
            WAIT_CANCELLED
        );
        teardown();
    }
}

static WORK_TOKEN: core::sync::atomic::AtomicU64 = core::sync::atomic::AtomicU64::new(0);
static PROMISE_ID: core::sync::atomic::AtomicI64 = core::sync::atomic::AtomicI64::new(0);

unsafe extern "C" fn drop_closure(obj: *mut ms_rt_abi::Obj) {
    // SAFETY: the capture-free closure owns this allocation.
    unsafe { alloc::free(obj.cast()) };
}

/// A promise's work: parks on `WORK_TOKEN` until the test posts it.
unsafe extern "C-unwind" fn promise_work(_: *mut ms_rt_abi::Closure) {
    let mut value = 0;
    // SAFETY: called from the promise's task.
    unsafe { msrt_token_park(WORK_TOKEN.load(Ordering::Relaxed), -1, &mut value) };
}

/// Starts a promise (whose work reads this frame) and parks on the token in `arg`.
unsafe extern "C-unwind" fn start_promise_then_park(arg: *mut u8) {
    let token = arg as usize as u64;
    let mut value = 0;
    // SAFETY: the closure is handed to the promise; the test ends the work and drops the promise.
    unsafe {
        let id = crate::promise::msrt_promise_new();
        let closure = crate::obj::new_obj(size_of::<ms_rt_abi::Closure>(), None, drop_closure)
            .cast::<ms_rt_abi::Closure>();
        (*closure).code = promise_work as *const u8;
        crate::promise::msrt_promise_start_here(id, closure);
        PROMISE_ID.store(id, Ordering::Relaxed);
        msrt_token_park(token, -1, &mut value);
    }
}

#[test]
fn a_task_whose_promise_still_runs_does_not_hibernate() {
    let _g = lock();
    teardown();
    // SAFETY: the test owns the tokens, ends the promise's work and joins the task.
    unsafe {
        let token = msrt_token_new(0);
        let work = msrt_token_new(0);
        WORK_TOKEN.store(work, Ordering::Relaxed);
        let h = msrt_task_spawn(start_promise_then_park, token as usize as *mut u8, 0, 0);
        msrt_task_yield();
        msrt_task_yield();
        let t = lookup(h);
        assert!((*t).state == State::Waiting);
        hibernate_idle();
        hibernate_idle();
        hibernate_idle();
        assert!(
            (*t).frozen.is_null(),
            "a task whose promise may read its frame keeps its pages"
        );
        // The work ends: its task reports to the creator, whose stack is its own again.
        msrt_token_post(work, 1);
        let id = PROMISE_ID.load(Ordering::Relaxed);
        // The work put no result, so the promise reports a failure; it is over all the same.
        assert_eq!(
            crate::promise::msrt_promise_wait(id, -1),
            crate::promise::FAILED
        );
        crate::promise::msrt_promise_drop(id);
        hibernate_idle();
        hibernate_idle();
        hibernate_idle();
        assert!(
            !(*t).frozen.is_null(),
            "the task hibernates once the promise is over"
        );
        msrt_token_post(token, 1);
        assert_eq!(msrt_task_join(h, null_mut()), 0);
        msrt_token_free(token);
        msrt_token_free(work);
        teardown();
    }
}

/// Parks on the token in `arg` with its stack lent out, as a pool job's borrow does.
unsafe extern "C-unwind" fn park_pinned(arg: *mut u8) {
    let token = arg as usize as u64;
    let mut value = 0;
    // SAFETY: called on a live task; the test posts the token.
    unsafe {
        pin_current(true);
        msrt_token_park(token, -1, &mut value);
        pin_current(false);
    }
}

/// Grows onto a segment twice over (the shim grows once more), checks each run is inside the
/// segment's bounds with the segment's limit, and that the home segment is back afterwards.
unsafe extern "C-unwind" fn grow_twice(arg: *mut u8) {
    // SAFETY: called on a live task.
    unsafe {
        let cur = ensure_init();
        let home = fault::segment_state();
        let mut probe = [0usize; 2];
        msrt_task_grow(on_segment, probe.as_mut_ptr().cast());
        assert_eq!((*cur).seg, 0);
        assert_eq!(fault::segment_state(), home);
        assert_eq!(probe[0], 2, "the shim ran on two segments");
        assert!(
            probe[1] < home.0 || probe[1] >= home.1,
            "the shim ran outside the home slot"
        );
        assert_eq!((*cur).segs.len(), 2);
        // The segments stay with the task: growing again allocates nothing.
        probe = [0; 2];
        msrt_task_grow(on_segment, probe.as_mut_ptr().cast());
        assert_eq!((*cur).segs.len(), 2);
        // A guard exit from a segment is the e2e fixture `task-stack-growth`'s to check:
        // the test build's guard unwinds a Rust panic, which cannot cross stacks on Windows.
        *(arg as *mut usize) = 1;
    }
}

unsafe extern "C-unwind" fn on_segment(block: *mut u8) {
    // SAFETY: `block` is the probe of `grow_twice`.
    unsafe {
        let cur = ensure_init();
        let p = block as *mut usize;
        let local = 0usize;
        let sp = core::ptr::addr_of!(local) as usize;
        let (lo, hi, chain) = fault::segment_state();
        assert!(
            sp >= lo && sp < hi,
            "the shim runs within the segment's bounds"
        );
        assert_ne!(chain, 0, "a grown segment chains to the one below");
        assert_eq!((*cur).hdr.limit, fault::stack_limit(lo, hi));
        *p.add(1) = sp;
        *p += 1;
        if *p < 2 {
            msrt_task_grow(on_segment, block);
        }
    }
}

#[test]
fn a_task_grows_onto_segments_and_comes_back() {
    let _g = lock();
    teardown();
    // SAFETY: the test joins the task.
    unsafe {
        let mut done = 0usize;
        let h = msrt_task_spawn(grow_twice, core::ptr::addr_of_mut!(done).cast(), 0, 0);
        assert_eq!(msrt_task_join(h, null_mut()), 0);
        assert_eq!(done, 1);
        // The task's segments went back to the pool with its slot.
        assert_eq!(sched().pool.len(), 3);
        teardown();
    }
}

#[test]
fn a_task_whose_stack_is_lent_out_does_not_hibernate() {
    let _g = lock();
    teardown();
    // SAFETY: the test owns the token and joins the task.
    unsafe {
        let token = msrt_token_new(0);
        let h = msrt_task_spawn(park_pinned, token as usize as *mut u8, 0, 0);
        msrt_task_yield();
        let t = lookup(h);
        assert!((*t).state == State::Waiting);
        hibernate_idle();
        hibernate_idle();
        hibernate_idle();
        assert!((*t).frozen.is_null(), "a lent stack keeps its pages");
        msrt_token_post(token, 1);
        assert_eq!(msrt_task_join(h, null_mut()), 0);
        msrt_token_free(token);
        teardown();
    }
}

unsafe extern "C-unwind" fn long_wait(_: *mut u8) {
    // SAFETY: called on a live task; the test cancels it after checking the heap.
    unsafe { msrt_task_sleep(3_600_000_000_000) };
}

unsafe extern "C-unwind" fn short_sleeps(_: *mut u8) {
    for _ in 0..100 {
        // SAFETY: called from a running task.
        unsafe { msrt_task_sleep(100_000) };
    }
}

/// A timer shorter than a millisecond must not wait a whole one (the poll timeout used to
/// round up): 100 sleeps of 100 us take about 10 ms, and at least 100 ms when rounded up.
#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn sleeps_shorter_than_a_millisecond_are_not_rounded_up() {
    let _g = lock();
    teardown();
    let mut best = u64::MAX;
    // SAFETY: tests hold the global lock; every handle is joined once.
    unsafe {
        // The best of a few runs, so a loaded machine does not fail the test.
        for _ in 0..3 {
            let start = std::time::Instant::now();
            let h = msrt_task_spawn(short_sleeps, null_mut(), 0, 0);
            assert_eq!(msrt_task_join(h, null_mut()), 0);
            best = best.min(start.elapsed().as_millis() as u64);
        }
    }
    teardown();
    assert!(best < 80, "100 sleeps of 100 us took {best} ms");
}

unsafe extern "C-unwind" fn busy(_: *mut u8) {
    for _ in 0..100 {
        // SAFETY: called from a running task.
        unsafe { msrt_task_yield() };
    }
    note(2);
}

unsafe extern "C-unwind" fn immediate_timer(_: *mut u8) {
    // SAFETY: called from a running task.
    assert_eq!(unsafe { msrt_task_sleep(0) }, WAIT_TIMEOUT);
    note(1);
}

#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn timers_progress_while_tasks_stay_ready() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock; every handle is joined once.
    unsafe {
        *LOG_N.ptr() = 0;
        let timer = msrt_task_spawn(immediate_timer, null_mut(), 0, 0);
        let spinner = msrt_task_spawn(busy, null_mut(), 0, 0);
        assert_eq!(msrt_task_join(timer, null_mut()), 0);
        assert_eq!(msrt_task_join(spinner, null_mut()), 0);
        assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[1, 2]);
    }
    teardown();
}

unsafe extern "C-unwind" fn posted_token(arg: *mut u8) {
    let mut value = 0;
    // SAFETY: the test keeps this token live through the join.
    assert_eq!(unsafe { msrt_token_park(arg as u64, -1, &mut value) }, 0);
    assert_eq!(value, 42);
    note(1);
}

#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn remote_posts_progress_while_tasks_stay_ready() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock; every handle is joined once.
    unsafe {
        *LOG_N.ptr() = 0;
        let token = msrt_token_new(TOKEN_REMOTE);
        let waiter = msrt_task_spawn(posted_token, token as *mut u8, 0, 0);
        let spinner = msrt_task_spawn(busy, null_mut(), 0, 0);
        std::thread::spawn(move || msrt_token_post_remote(token, 42))
            .join()
            .unwrap();
        assert_eq!(msrt_task_join(waiter, null_mut()), 0);
        assert_eq!(msrt_task_join(spinner, null_mut()), 0);
        msrt_token_free(token);
        assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[1, 2]);
    }
    teardown();
}

/// A thread that posts at every point of the waiter's path to sleep never loses the wake-up:
/// a lost one would leave the park below waiting forever.
#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn remote_posts_never_miss_a_sleeping_scheduler() {
    let _g = lock();
    teardown();
    for round in 0..2000u32 {
        // SAFETY: tests hold the global lock; every handle is joined once.
        unsafe {
            *LOG_N.ptr() = 0;
            let token = msrt_token_new(TOKEN_REMOTE);
            let waiter = msrt_task_spawn(posted_token, token as *mut u8, 0, 0);
            let poster = std::thread::spawn(move || {
                // Spread the posts over the waiter's spin, its last look and its sleep.
                for _ in 0..(round % 64) * 400 {
                    std::hint::spin_loop();
                }
                msrt_token_post_remote(token, 42)
            });
            assert_eq!(msrt_task_join(waiter, null_mut()), 0);
            poster.join().unwrap();
            msrt_token_free(token);
        }
    }
    teardown();
}

/// A wait for a plain thread (a blocking-pool job, a helper) is not a deadlock even while a
/// token that only another isolate could post is also pending.
#[test]
fn a_thread_post_is_not_a_deadlock_beside_a_pending_peer_token() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock; the test thread plays the main isolate.
    unsafe {
        let peer = msrt_token_new(TOKEN_REMOTE | TOKEN_PEER);
        let plain = msrt_token_new(TOKEN_REMOTE);
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(50));
            msrt_token_post_remote(plain, 7);
        });
        let mut value = 0;
        assert_eq!(msrt_token_park(plain, -1, &mut value), 0);
        assert_eq!(value, 7);
        msrt_token_free(plain);
        msrt_token_free(peer);
    }
    teardown();
}

static TOKEN: Process<u64> = Process::new(0);
static GOT: Process<(u32, u64)> = Process::new((0, 0));

unsafe extern "C-unwind" fn token_parker(arg: *mut u8) {
    let mut v = 0;
    // SAFETY: called from a running task; the token outlives the park.
    let r = unsafe { msrt_token_park(*TOKEN.ptr(), arg as usize as i64, &mut v) };
    // SAFETY: tests hold the lock.
    unsafe { *GOT.ptr() = (r, v) };
}

unsafe extern "C-unwind" fn token_poster(arg: *mut u8) {
    // SAFETY: called from a running task.
    unsafe { msrt_token_post(*TOKEN.ptr(), arg as usize as u64) };
}

#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn tokens_deliver_posts_made_before_and_during_a_park() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock; every handle is joined once.
    unsafe {
        let id = msrt_token_new(0);
        msrt_token_post(id, 7);
        // A second post while the first is untaken is dropped.
        msrt_token_post(id, 8);
        let mut v = 0;
        assert_eq!(msrt_token_park(id, -1, &mut v), 0);
        assert_eq!(v, 7);

        // The park took the post: the next one waits for a new post.
        *TOKEN.ptr() = id;
        let parker = msrt_task_spawn(
            token_parker,
            core::ptr::without_provenance_mut(usize::MAX),
            0,
            0,
        );
        let poster = msrt_task_spawn(token_poster, core::ptr::without_provenance_mut(9), 0, 0);
        assert_eq!(msrt_task_join(parker, null_mut()), 0);
        assert_eq!(msrt_task_join(poster, null_mut()), 0);
        assert_eq!(*GOT.ptr(), (0, 9));
        msrt_token_free(id);
    }
    teardown();
}

#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn a_timed_out_park_keeps_the_token_and_the_late_post() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock.
    unsafe {
        let id = msrt_token_new(0);
        let mut v = 0;
        assert_eq!(msrt_token_park(id, 1_000_000, &mut v), WAIT_TIMEOUT);
        msrt_token_post(id, 3);
        assert_eq!(msrt_token_park(id, 1_000_000, &mut v), 0);
        assert_eq!(v, 3);
        msrt_token_free(id);
    }
    teardown();
}

#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn cancelling_a_task_parked_on_a_token_releases_the_token() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock; the handle is joined once.
    unsafe {
        let id = msrt_token_new(0);
        *TOKEN.ptr() = id;
        let parker = msrt_task_spawn(
            token_parker,
            core::ptr::without_provenance_mut(usize::MAX),
            0,
            0,
        );
        msrt_task_yield();
        msrt_task_cancel(parker);
        assert_eq!(msrt_task_join(parker, null_mut()), 0);
        assert_eq!((*GOT.ptr()).0, WAIT_CANCELLED);
        // Nobody waits any more, so the token can be freed.
        msrt_token_free(id);
    }
    teardown();
}

#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn posts_to_a_freed_token_do_not_reach_its_reused_slot() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock.
    unsafe {
        let old = msrt_token_new(0);
        msrt_token_free(old);
        let new = msrt_token_new(0);
        assert_eq!(old & 0xffff_ffff, new & 0xffff_ffff, "the slot is reused");
        assert_ne!(old, new);
        msrt_token_post(old, 1);
        msrt_token_post_remote(old, 2);
        let mut v = 0;
        assert_eq!(msrt_token_park(new, 1_000_000, &mut v), WAIT_TIMEOUT);
        msrt_token_free(new);
    }
    teardown();
}

#[test]
fn an_exhausted_token_generation_does_not_revive_a_stale_id() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the runtime lock and own both tokens.
    unsafe {
        let old = msrt_token_new(0);
        // Exercise the last generation without spending a million cycles reaching it.
        let slot = (old as u32 as usize) - 1;
        sched().tokens[slot].gen_ = GEN_MASK;
        let generation_mask = u64::from(GEN_MASK) << 32;
        msrt_token_free((old & !generation_mask) | generation_mask);
        let new = msrt_token_new(0);
        msrt_token_post(old, 42);
        let result = msrt_token_park(new, 1_000_000, null_mut());
        msrt_token_free(new);
        teardown();
        assert_eq!(result, WAIT_TIMEOUT, "a stale post reached a wrapped token");
    }
}

#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn a_remote_post_wakes_a_parked_scheduler() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock.
    unsafe {
        let id = msrt_token_new(TOKEN_REMOTE);
        let poster = std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(20));
            msrt_token_post_remote(id, 42);
        });
        // No timer and no descriptor: only the pending remote post keeps this from being
        // reported as a deadlock.
        let mut v = 0;
        assert_eq!(msrt_token_park(id, -1, &mut v), 0);
        assert_eq!(v, 42);
        assert_eq!(sched().remote_tokens, 0);
        poster.join().unwrap();
        msrt_token_free(id);
    }
    teardown();
}

#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn freeing_an_unposted_remote_token_stops_counting_it() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock.
    unsafe {
        let id = msrt_token_new(TOKEN_REMOTE);
        assert_eq!(sched().remote_tokens, 1);
        msrt_token_free(id);
        assert_eq!(sched().remote_tokens, 0);
        // The late post is dropped when it is delivered.
        msrt_token_post_remote(id, 1);
        deliver_remote_posts();
        assert_eq!(sched().remote_tokens, 0);
    }
    teardown();
}

#[cfg(unix)]
mod fd_waits {
    use super::*;

    static RESULT: Process<u32> = Process::new(0);

    fn pipe() -> [i32; 2] {
        let mut fds = [0i32; 2];
        // SAFETY: `fds` has room for the two descriptors.
        assert_eq!(unsafe { sys::pipe(fds.as_mut_ptr()) }, 0);
        fds
    }

    fn put(fd: i32) {
        // SAFETY: writes one byte from a live buffer.
        assert_eq!(unsafe { sys::write(fd, b"x".as_ptr().cast(), 1) }, 1);
    }

    unsafe extern "C-unwind" fn reader(arg: *mut u8) {
        // SAFETY: called from a running task; `arg` is a pipe read end.
        let r = unsafe { msrt_task_wait_fd(arg as usize as i32, WAIT_READ, 2_000_000_000) };
        // SAFETY: tests hold the lock.
        unsafe { *RESULT.ptr() = r };
    }

    unsafe extern "C-unwind" fn writer(arg: *mut u8) {
        // SAFETY: called from a running task.
        unsafe { msrt_task_sleep(5_000_000) };
        put(arg as usize as i32);
    }

    fn close_all(fds: [i32; 2]) {
        // SAFETY: both descriptors are open and owned by the test.
        unsafe {
            sys::close(fds[0]);
            sys::close(fds[1]);
        }
    }

    #[test]
    fn timers_of_woken_waits_do_not_pile_up() {
        let _g = lock();
        teardown();
        let fds = pipe();
        put(fds[1]);
        // SAFETY: tests hold the global lock; the descriptor stays open.
        unsafe {
            // A sleeper with an earlier deadline holds the heap's head, so the stale entries
            // behind it are never popped lazily.
            msrt_task_spawn(sleeper, core::ptr::without_provenance_mut(10_000), 0, 0);
            // Each wait returns at once (the byte stays unread) and leaves its hour-long
            // deadline in the heap; the heap must not keep all of them.
            for _ in 0..10 * MIN_TIMER_LIMIT {
                let r = msrt_task_wait_fd(fds[0], WAIT_READ, 3_600_000_000_000);
                assert_eq!(r & WAIT_READ, WAIT_READ);
            }
            assert!(sched().timers.len() <= 2 * MIN_TIMER_LIMIT);
        }
        close_all(fds);
        teardown();
    }

    unsafe extern "C-unwind" fn ready_reader(arg: *mut u8) {
        // SAFETY: the test owns this pipe until the task joins.
        let result = unsafe { msrt_task_wait_fd(arg as i32, WAIT_READ, -1) };
        assert_ne!(result & WAIT_READ, 0);
        note(1);
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn io_progresses_while_tasks_stay_ready() {
        let _g = lock();
        teardown();
        let fds = pipe();
        put(fds[1]);
        // SAFETY: tests hold the global lock; the pipe stays open through both joins.
        unsafe {
            *LOG_N.ptr() = 0;
            let reader = msrt_task_spawn(ready_reader, fds[0] as *mut u8, 0, 0);
            let spinner = msrt_task_spawn(busy, null_mut(), 0, 0);
            assert_eq!(msrt_task_join(reader, null_mut()), 0);
            assert_eq!(msrt_task_join(spinner, null_mut()), 0);
            assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[1, 2]);
        }
        close_all(fds);
        teardown();
    }

    #[test]
    fn wakes_on_readable_then_stays_ready() {
        let _g = lock();
        teardown();
        let fds = pipe();
        // SAFETY: tests hold the global lock; every handle is joined once.
        unsafe {
            *RESULT.ptr() = 0;
            let r = msrt_task_spawn(
                reader,
                core::ptr::without_provenance_mut(fds[0] as usize),
                0,
                0,
            );
            let w = msrt_task_spawn(
                writer,
                core::ptr::without_provenance_mut(fds[1] as usize),
                0,
                0,
            );
            assert_eq!(msrt_task_join(r, null_mut()), 0);
            assert_eq!(msrt_task_join(w, null_mut()), 0);
            assert_eq!(*RESULT.ptr() & WAIT_READ, WAIT_READ);
            // Level triggered: the byte is still unread, so a new wait returns at once.
            assert_eq!(
                msrt_task_wait_fd(fds[0], WAIT_READ, 1_000_000_000) & WAIT_READ,
                WAIT_READ
            );
        }
        close_all(fds);
        teardown();
    }

    unsafe extern "C-unwind" fn shared_reader(arg: *mut u8) {
        // SAFETY: the test owns this pipe until the tasks join.
        let result = unsafe { msrt_task_wait_fd(arg as i32, WAIT_READ, 2_000_000_000) };
        note(if result & WAIT_READ != 0 { 1 } else { 2 });
    }

    unsafe extern "C-unwind" fn impatient_reader(arg: *mut u8) {
        // SAFETY: as `shared_reader`.
        let result = unsafe { msrt_task_wait_fd(arg as i32, WAIT_READ, 5_000_000) };
        note(if result == WAIT_TIMEOUT { 3 } else { 4 });
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn several_tasks_wait_on_one_descriptor() {
        let _g = lock();
        teardown();
        let fds = pipe();
        // SAFETY: tests hold the global lock; the pipe stays open through every join.
        unsafe {
            *LOG_N.ptr() = 0;
            let fd = core::ptr::without_provenance_mut(fds[0] as usize);
            let a = msrt_task_spawn(shared_reader, fd, 0, 0);
            let b = msrt_task_spawn(shared_reader, fd, 0, 0);
            // One waiter leaves by timeout; the others must stay registered.
            let c = msrt_task_spawn(impatient_reader, fd, 0, 0);
            let w = msrt_task_spawn(
                writer,
                core::ptr::without_provenance_mut(fds[1] as usize),
                0,
                0,
            );
            for h in [a, b, c, w] {
                assert_eq!(msrt_task_join(h, null_mut()), 0);
            }
            let mut log = (&(*LOG.ptr()))[..*LOG_N.ptr()].to_vec();
            log.sort();
            assert_eq!(log, [1, 1, 3]);
        }
        close_all(fds);
        teardown();
    }

    #[test]
    fn times_out_when_nothing_arrives() {
        let _g = lock();
        teardown();
        let fds = pipe();
        // SAFETY: tests hold the global lock.
        let got = unsafe { msrt_task_wait_fd(fds[0], WAIT_READ, 10_000_000) };
        assert_eq!(got, WAIT_TIMEOUT);
        close_all(fds);
        teardown();
    }

    #[test]
    fn writable_end_is_ready() {
        let _g = lock();
        teardown();
        let fds = pipe();
        // SAFETY: tests hold the global lock.
        let got = unsafe { msrt_task_wait_fd(fds[1], WAIT_WRITE, 1_000_000_000) };
        assert_eq!(got & WAIT_WRITE, WAIT_WRITE);
        close_all(fds);
        teardown();
    }
}

/// Runs `f` as a shielded cleanup action would: cancellation is off until it returns.
fn shielded_call<R>(f: impl FnOnce() -> R) -> R {
    fault::SHIELD.set(fault::SHIELD.get() + 1);
    cancel_flag().store(0, Ordering::Relaxed);
    let r = f();
    fault::SHIELD.set(fault::SHIELD.get() - 1);
    r
}

unsafe extern "C-unwind" fn shielded_sleeper(_: *mut u8) {
    let r = shielded_call(|| {
        // SAFETY: called from a running task.
        unsafe { msrt_task_sleep(3_000_000) }
    });
    note(if r == WAIT_TIMEOUT { 1 } else { 2 });
}

/// Clears the simulated stop request even when an assertion fails.
struct StopRequest;

impl StopRequest {
    fn raise() -> Self {
        fault::PENDING_SIGNAL.store(2, Ordering::Relaxed);
        StopRequest
    }
}

impl Drop for StopRequest {
    fn drop(&mut self) {
        fault::PENDING_SIGNAL.store(0, Ordering::Relaxed);
    }
}

#[test]
#[cfg_attr(miri, ignore = "parks on the poller")]
fn stop_request_does_not_interrupt_a_shielded_wait() {
    let _g = lock();
    teardown();
    let _stop = StopRequest::raise();
    // SAFETY: tests hold the global lock; the sleeps run on the test's own task.
    unsafe {
        // A parked task is woken at once by a stop request ...
        assert_eq!(msrt_task_sleep(3_000_000), WAIT_CANCELLED);
        // ... except while it runs a cleanup action, which waits out its sleep.
        let r = shielded_call(|| msrt_task_sleep(3_000_000));
        assert_eq!(r, WAIT_TIMEOUT);
    }
    teardown();
}

unsafe extern "C-unwind" fn stop_shielded_sleeper(_: *mut u8) {
    fault::stop_shield_enter();
    // SAFETY: called from a running task.
    let r = unsafe { msrt_task_sleep(3_000_000_000) };
    fault::stop_shield_exit();
    note(if r == WAIT_CANCELLED { 2 } else { 1 });
}

#[test]
#[cfg_attr(miri, ignore = "parks on the poller")]
fn a_stop_shield_holds_back_stop_requests_but_not_a_cancel_of_the_task() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock; every handle is joined once.
    unsafe {
        *LOG_N.ptr() = 0;
        // A stop request leaves the shielded task asleep: it ends by its own timeout.
        let stop = StopRequest::raise();
        let held = msrt_task_spawn(stop_shielded_sleeper, null_mut(), 0, 0);
        msrt_task_yield();
        assert!(!cancel_all_waiters_woke_any());
        drop(stop);
        cancel_flag().store(0, Ordering::Relaxed);
        // A cancel aimed at the task wakes it at once.
        msrt_task_cancel(held);
        msrt_task_join(held, null_mut());
        assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[2]);
    }
    teardown();
}

unsafe fn cancel_all_waiters_woke_any() -> bool {
    // SAFETY: tests hold the global lock.
    unsafe { cancel_all_waiters() }
}

#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn cancelling_a_task_does_not_interrupt_its_shielded_wait() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock; every handle is joined once.
    unsafe {
        *LOG_N.ptr() = 0;
        let t = msrt_task_spawn(shielded_sleeper, null_mut(), 0, 0);
        msrt_task_yield();
        msrt_task_cancel(t);
        assert_eq!(msrt_task_join(t, null_mut()), 0);
        assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[1]);
    }
    teardown();
}

/// A task parked on a token only this thread posts leaves the thread free for a blocking call;
/// one parked on a token another thread may post does not, since an inline call would delay
/// that wake-up.
#[test]
#[cfg_attr(miri, ignore = "context switches use inline assembly")]
fn others_are_stalled_only_when_no_other_thread_can_wake_them() {
    let _g = lock();
    teardown();
    // SAFETY: tests hold the global lock; every handle is joined once.
    unsafe {
        *LOG_N.ptr() = 0;
        let local = msrt_token_new(0);
        let waiter = msrt_task_spawn(posted_token, local as *mut u8, 0, 0);
        msrt_task_yield();
        assert!(
            msrt_task_others_stalled(),
            "a local token cannot be posted elsewhere"
        );
        msrt_token_post(local, 42);
        assert_eq!(msrt_task_join(waiter, null_mut()), 0);
        msrt_token_free(local);

        let remote = msrt_token_new(TOKEN_REMOTE);
        let waiter = msrt_task_spawn(posted_token, remote as *mut u8, 0, 0);
        msrt_task_yield();
        assert!(
            !msrt_task_others_stalled(),
            "a remote token can wake its task at any time"
        );
        std::thread::spawn(move || msrt_token_post_remote(remote, 42))
            .join()
            .unwrap();
        assert_eq!(msrt_task_join(waiter, null_mut()), 0);
        msrt_token_free(remote);
    }
    teardown();
}
