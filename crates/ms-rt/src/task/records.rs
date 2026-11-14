//! Task records, handle lookup and stack allocation.

use super::*;

// ---- records and handles ----

pub(super) fn clock_ns() -> i64 {
    sys::monotonic_ns()
}

pub(super) fn lookup_in(slots: &[Slot], h: u64) -> *mut Task {
    let idx = (h & 0xffff_ffff) as usize;
    match slots.get(idx.wrapping_sub(1)) {
        Some(slot) if slot.gen_ == (h >> 32) as u32 => slot.task,
        _ => null_mut(),
    }
}

pub(super) fn lookup(h: u64) -> *mut Task {
    lookup_in(&sched().slots, h)
}

pub(super) unsafe fn new_task(ctx: Ctx) -> *mut Task {
    let mut s = sched();
    let t = alloc::alloc(size_of::<Task>()) as *mut Task;
    let (idx, gen_) = match s.free_slots.pop() {
        Some(i) => {
            let slot = &mut s.slots[i];
            slot.gen_ = (slot.gen_.wrapping_add(1) & 0x7fff_ffff).max(1);
            slot.task = t;
            (i, slot.gen_)
        }
        None => {
            s.slots.push(Slot { task: t, gen_: 1 });
            (s.slots.len() - 1, 1)
        }
    };
    // SAFETY: `t` is a fresh block of the right size.
    unsafe {
        t.write(Task {
            handle: (gen_ as u64) << 32 | (idx as u64 + 1),
            state: State::Ready,
            sp: 0,
            ctx,
            stack: null_mut(),
            stack_len: 0,
            entry: None,
            arg: null_mut(),
            detached: false,
            joiner: 0,
            status: 0,
            msg: crate::string::NO_STR,
            wait_fd: -1,
            wait_events: 0,
            wait_result: 0,
            deadline: NO_DEADLINE,
            read_limit: NO_DEADLINE,
            wait_token: 0,
            fatal: false,
            owned: null_mut(),
            kill_at: NO_DEADLINE,
            started_by: Vec::new(),
            timed_out: false,
            defer_deadline: i64::MAX,
            promise: 0,
            capture: 0,
            hdr: fault::Hdr::new(0),
            frozen: null_mut(),
            frozen_len: 0,
            parked_round: 0,
            pinned: 0,
            #[cfg(windows)]
            teb: sys::teb_stack(),
            segs: Vec::new(),
            seg: 0,
            left: Vec::new(),
            #[cfg(windows)]
            seg_teb: Vec::new(),
        });
    }
    s.live += 1;
    t
}

/// Buffers larger than this, or beyond this many tasks' worth, are freed instead of kept.
const SPARE_CAPACITY: usize = 256;
const SPARE_TASKS: usize = 1024;

pub(super) unsafe fn free_task(t: *mut Task) {
    let mut s = sched();
    // SAFETY: `t` is a live record from `new_task`; its slot is cleared before release.
    unsafe {
        let idx = ((*t).handle & 0xffff_ffff) as usize - 1;
        s.slots[idx].task = null_mut();
        s.free_slots.push(idx);
        if !(*t).frozen.is_null() {
            sys::free((*t).frozen.cast());
        }
        // A task's cleanup stack is small and short-lived; the next one starts with these.
        let spares = (*t).ctx.take_spares();
        if spares.0.capacity() <= SPARE_CAPACITY && s.spares.len() < SPARE_TASKS {
            s.spares.push(spares);
        }
        core::ptr::drop_in_place(t);
        alloc::free(t as *mut u8);
    }
    s.live -= 1;
}

/// Creates the record of the thread's current flow of control on first use.
pub(super) unsafe fn ensure_init() -> *mut Task {
    let mut s = sched();
    if s.cur.is_null() {
        // SAFETY: first use; the live globals belong to this flow, so its saved context starts empty.
        unsafe {
            let t = new_task(Ctx::new(0, 0));
            (*t).sp = stack::adopt_thread();
            (*t).state = State::Running;
            s.cur = t;
            s.main = t;
        }
    }
    s.cur
}

// ---- stacks ----

pub(super) unsafe fn alloc_stack(len: usize) -> *mut u8 {
    // SAFETY: forwarded.
    let p = unsafe { try_alloc_stack(len) };
    if p.is_null() {
        fault::fault(
            b"cannot allocate a task stack: too many tasks at once (the process is out of address space or, on a Linux kernel before 6.13, out of memory mappings: raise vm.max_map_count)",
        );
    }
    p
}

/// A pooled or fresh stack of `len` bytes; null when none is left.
pub(super) unsafe fn try_alloc_stack(len: usize) -> *mut u8 {
    let mut s = sched();
    if let Some(at) = s.pool.iter().rposition(|&(_, pooled)| pooled == len) {
        // The entry that moves into `at` may still hold pages.
        s.pool_clean = s.pool_clean.min(at);
        return s.pool.swap_remove(at).0 as *mut u8;
    }
    let _ = s;
    // SAFETY: the lowest pages of the fresh mapping become the guard.
    unsafe { stack::create(len) }
}

/// A finished task's stack goes to the pool. Slots are never unmapped one at a time: that would
/// split their region's mapping, and `vm.max_map_count` bounds how many mappings a process may
/// have (about 32k tasks, #2483). Regions go back at teardown.
pub(super) unsafe fn release_stack(base: usize, len: usize) {
    sched().pool.push((base, len));
}

/// Stacks the pool keeps with their pages when the scheduler idles; the rest give the pages back.
pub(super) const STACK_POOL_WARM: usize = 256;

/// Called before the scheduler blocks: after a burst of tasks the pool holds many stacks, and
/// each keeps the pages its task touched. The oldest give them back (one call per stack, once),
/// so a quiet server returns to its working set; the newest stay warm for the next request.
pub(super) unsafe fn trim_idle_stacks() {
    let mut s = sched();
    let end = s.pool.len().saturating_sub(STACK_POOL_WARM);
    for at in s.pool_clean..end {
        let (base, len) = s.pool[at];
        // SAFETY: a pooled stack is unused; its guard stays and the stack stays mapped.
        unsafe {
            sys::release(
                (base + GUARD) as *mut u8,
                stack_top(base, len) - base - GUARD,
            )
        };
    }
    s.pool_clean = s.pool_clean.max(end);
}

/// Called before the scheduler blocks: a task parked for `HIBERNATE_ROUNDS` idle rounds has its
/// used stack copied to the heap and its pages given back, so an idle task costs its records
/// and not a page (a Java virtual thread's freeze). `thaw` copies the bytes back to the same
/// addresses before the task runs again, so every pointer into the stack stays valid. Nothing
/// writes to a parked task's stack; a pool job that borrows a slice of its caller's frame pins the
/// task (`pin_current`) so it is skipped until the job is done.
///
/// One call walks every slot once, `HIBERNATE_SCAN` at a time, and stops early when work has
/// arrived, so a wake-up never waits for a million slots; the next idle round resumes where it
/// stopped.
pub(super) unsafe fn hibernate_idle() {
    let mut s = sched();
    s.round = s.round.wrapping_add(1);
    let round = s.round;
    let n = s.slots.len();
    if n == 0 {
        return;
    }
    // The blocking task is still on its stack with a stale saved pointer: never freeze it.
    let cur = s.cur;
    let mut at = s.scan.min(n);
    let mut left = n;
    while left > 0 {
        let chunk = HIBERNATE_SCAN.min(left);
        left -= chunk;
        for _ in 0..chunk {
            if at == n {
                at = 0;
            }
            let t = s.slots[at].task;
            at += 1;
            // SAFETY: slots hold live records or null.
            unsafe {
                if t.is_null()
                    || t == cur
                    || (*t).state != State::Waiting
                    || (*t).seg != 0
                    || (*t).pinned != 0
                    || !(*t).frozen.is_null()
                    || (*t).stack.is_null()
                    || round.wrapping_sub((*t).parked_round) < HIBERNATE_ROUNDS
                {
                    continue;
                }
                freeze(t);
            }
        }
        if crate::sched::work_available() || crate::sched::signalled() {
            break;
        }
    }
    s.scan = at;
}

/// Marks the running task's stack as lent out (`lend` true) or returned (`lend` false): a pool
/// job that borrows a slice of the caller's frame, or a promise task that reads what its work
/// captured, reads the frame while the task is parked, so the task must not hibernate until the
/// borrower is done.
pub(crate) unsafe fn pin_current(lend: bool) {
    // SAFETY: called on the runtime thread by the running task.
    unsafe {
        let cur = ensure_init();
        if lend {
            (*cur).pinned += 1;
        } else {
            (*cur).pinned -= 1;
        }
    }
}

/// Lends the running task's stack out until [`return_lent`] is called with the handle this
/// returns: the promise it starts reads the frame its work captured from, for as long as the
/// promise's task runs.
pub(crate) unsafe fn lend_current() -> u64 {
    // SAFETY: called on the runtime thread by the running task.
    unsafe {
        pin_current(true);
        (*ensure_init()).handle
    }
}

/// Returns a stack lent with [`lend_current`]; nothing to do when the task has ended since.
pub(crate) unsafe fn return_lent(handle: u64) {
    let t = lookup(handle);
    if t.is_null() {
        return;
    }
    // SAFETY: a live record of this thread's scheduler.
    unsafe { (*t).pinned -= 1 };
}

/// Copies the used part of `t`'s stack to the heap and gives all its pages back.
pub(super) unsafe fn freeze(t: *mut Task) {
    // SAFETY: `t` is parked, so nothing runs on its stack; `sp` is its saved stack pointer.
    unsafe {
        let top = stack_top((*t).stack as usize, (*t).stack_len);
        let sp = (*t).sp;
        let len = top - sp;
        // The system allocator sizes the copy exactly; the runtime's large classes round a
        // 3 KiB stack up to a 4 KiB block, which would give back nothing.
        let copy = sys::malloc(len.max(1)) as *mut u8;
        if copy.is_null() {
            fault::fatal(b"out of memory");
        }
        core::ptr::copy_nonoverlapping(sp as *const u8, copy, len);
        (*t).frozen = copy;
        (*t).frozen_len = len;
        // The whole stack: pages below `sp` that deeper calls touched and left behind go too,
        // and the segments a deep recursion grew into, all unused on the home segment.
        let low = (*t).stack as usize + GUARD;
        sys::release(low as *mut u8, top - low);
        for &base in &(*t).segs {
            sys::release((base + GUARD) as *mut u8, SLOT - GUARD);
        }
    }
}

/// Copies a hibernating task's stack back before it runs.
pub(super) unsafe fn thaw(t: *mut Task) {
    // SAFETY: `t` is about to run; its stack range is reserved and nothing else uses it.
    unsafe {
        let sp = (*t).sp;
        let len = (*t).frozen_len;
        let page = sp & !4095;
        if !sys::commit(page as *mut u8, sp + len - page)
            || !sys::commit_guard((page - 4096) as *mut u8)
        {
            fault::fatal(b"cannot commit a task stack");
        }
        #[cfg(windows)]
        {
            (*t).teb[1] = page;
        }
        core::ptr::copy_nonoverlapping((*t).frozen, sp as *mut u8, len);
        sys::free((*t).frozen.cast());
        (*t).frozen = null_mut();
        (*t).frozen_len = 0;
    }
}

/// Frees what finished tasks left behind; runs on the stack of a task that is still alive.
pub(super) unsafe fn reap() {
    let mut s = sched();
    // SAFETY: the zombie's stack is no longer in use; its record is unreachable.
    unsafe {
        if s.zombie_stack.0 != 0 {
            let (base, len) = s.zombie_stack;
            s.zombie_stack = (0, 0);
            release_stack(base, len);
        }
        if !s.zombie_task.is_null() {
            let t = s.zombie_task;
            s.zombie_task = null_mut();
            free_task(t);
        }
    }
}
