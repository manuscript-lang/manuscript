//! Cells: one owned value of any type, parked in the runtime so a closure can carry only its id.
//!
//! A stream's `read` returns a promise whose work runs later in the waiting task; the work cannot
//! capture the stream (an escaping closure owns its captures), so the stream keeps its source in a
//! cell and the work takes the source out, runs it and puts it back. `take` of an empty cell
//! (a read already running) answers no value.
//!
//! Cells live in a table of fixed pages that never move, so `take` and `put` read a cell with no
//! lock. A cell's value belongs to the stream that owns it, and one owner uses it at a time (a move
//! to another thread is a synchronized handoff), so `take` and `put` are a load and a store of the
//! cell's word, which packs its generation and state, with no locked instruction. Only `new` and
//! `drop` take the mutex that guards the free list of dead slots, and `drop` swaps the word so a
//! cell dropped by another thread after a handoff still frees its block once.
use crate::alloc;
use crate::desc::slot_drop;
use ms_rt_abi::TypeDesc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicPtr, AtomicU32, AtomicUsize, Ordering};

/// The state in the low three bits of a cell's word; the rest is the generation.
const DEAD: u32 = 0;
/// The block holds the value.
const FULL: u32 = 1;
/// A read has the value out; the block is empty.
const OUT: u32 = 2;
const STATE_BITS: u32 = 3;
const STATE_MASK: u32 = (1 << STATE_BITS) - 1;
const GENERATION_LIMIT: u32 = 1 << (32 - STATE_BITS);

const PAGE_SHIFT: usize = 10;
const PAGE_CELLS: usize = 1 << PAGE_SHIFT;
const MAX_PAGES: usize = 4096;

/// A cell owns one block, sized for its value, from `new` until `drop`: `take` and `put` copy the
/// value out of and back into it, so a stream read allocates nothing.
struct Cell {
    word: AtomicU32,
    ptr: AtomicUsize,
    desc: AtomicUsize,
}

static PAGES: [AtomicPtr<[Cell; PAGE_CELLS]>; MAX_PAGES] =
    [const { AtomicPtr::new(core::ptr::null_mut()) }; MAX_PAGES];

struct Slots {
    /// Slots handed out so far.
    len: usize,
    /// The first dead slot whose generation can still grow, plus one; each dead slot's `ptr`
    /// holds the next one, so the list takes no memory of its own.
    head: usize,
}

static SLOTS: Mutex<Slots> = Mutex::new(Slots { len: 0, head: 0 });

fn slots() -> std::sync::MutexGuard<'static, Slots> {
    SLOTS.lock().unwrap_or_else(|e| e.into_inner())
}

fn cell_at(index: usize) -> Option<&'static Cell> {
    let page = PAGES.get(index >> PAGE_SHIFT)?.load(Ordering::Acquire);
    if page.is_null() {
        return None;
    }
    // SAFETY: pages are leaked, so they live for the process and never move.
    Some(unsafe { &(*page)[index & (PAGE_CELLS - 1)] })
}

/// The cell `id` names and the word it must hold for the state `state`.
fn lookup(id: i64, state: u32) -> Option<(&'static Cell, u32)> {
    let index = usize::try_from((id & 0xffff_ffff) - 1).ok()?;
    let generation = u32::try_from(id >> 32).ok()?;
    Some((cell_at(index)?, generation << STATE_BITS | state))
}

/// Drops the value in a block that holds one, and frees the block.
fn free_block(ptr: usize, desc: usize, full: bool) {
    if ptr != 0 {
        // SAFETY: a full block holds an owned value of its descriptor that nobody took.
        unsafe {
            if full {
                slot_drop(&*(desc as *const TypeDesc), ptr as *mut u8);
            }
            alloc::free(ptr as *mut u8);
        }
    }
}

/// Puts the dead slot `index` on the list of reusable ones, unless its generation is spent.
fn retire(index: usize, generation: u32) {
    if generation + 1 < GENERATION_LIMIT
        && let Some(c) = cell_at(index)
    {
        let mut table = slots();
        c.ptr.store(table.head, Ordering::Relaxed);
        table.head = index + 1;
    }
}

/// A new cell holding `value`, which moves in.
///
/// # Safety
/// `value` holds an owned value of `d`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_cells_new(value: *mut u8, d: ms_rt_abi::ValueDesc) -> i64 {
    // SAFETY: `value` holds an owned value of `d`, which moves into the new block.
    let ptr = unsafe {
        let size = (*d).size as usize;
        let block = alloc::alloc(size.max(1));
        core::ptr::copy_nonoverlapping(value, block, size);
        block as usize
    };
    let index = {
        let mut table = slots();
        if table.head != 0 {
            let i = table.head - 1;
            table.head = cell_at(i).map_or(0, |c| c.ptr.load(Ordering::Relaxed));
            i
        } else {
            let i = table.len;
            if i >> PAGE_SHIFT >= MAX_PAGES {
                crate::fault::fatal(b"too many open streams");
            }
            if i & (PAGE_CELLS - 1) == 0 {
                // Zeroed cells are dead. The page comes straight from the system so that the
                // runtime's live-block count, which only sees program values, ignores it.
                // SAFETY: a plain allocation, zeroed before use and never freed.
                let page = unsafe {
                    let size = core::mem::size_of::<[Cell; PAGE_CELLS]>();
                    let p = crate::sys::malloc(size).cast::<u8>();
                    if p.is_null() {
                        crate::fault::fatal(b"out of memory");
                    }
                    core::ptr::write_bytes(p, 0, size);
                    p.cast::<[Cell; PAGE_CELLS]>()
                };
                PAGES[i >> PAGE_SHIFT].store(page, Ordering::Release);
            }
            table.len += 1;
            i
        }
    };
    let c = cell_at(index).expect("a handed-out slot has a page");
    let generation = (c.word.load(Ordering::Relaxed) >> STATE_BITS) + 1;
    c.ptr.store(ptr, Ordering::Relaxed);
    c.desc.store(d as usize, Ordering::Relaxed);
    c.word
        .store(generation << STATE_BITS | FULL, Ordering::Release);
    (i64::from(generation) << 32) | (index as i64 + 1)
}

/// Moves the value out into `out` and answers 1; 0 when the cell is empty or gone.
///
/// # Safety
/// `out` is writable memory for a value of `d`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_cells_take(
    id: i64,
    d: ms_rt_abi::ValueDesc,
    out: *mut u8,
) -> u8 {
    let Some((c, full)) = lookup(id, FULL) else {
        return 0;
    };
    if c.word.load(Ordering::Acquire) != full {
        return 0;
    }
    c.word.store(full & !STATE_MASK | OUT, Ordering::Relaxed);
    // SAFETY: the block holds an owned value of `d`; it moves out and the block stays for `put`.
    unsafe {
        core::ptr::copy_nonoverlapping(
            c.ptr.load(Ordering::Relaxed) as *const u8,
            out,
            (*d).size as usize,
        )
    };
    1
}

/// Moves `value` into the (empty) cell; a gone or full cell drops it.
///
/// # Safety
/// `value` holds an owned value of `d`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_cells_put(id: i64, value: *mut u8, d: ms_rt_abi::ValueDesc) {
    if let Some((c, out)) = lookup(id, OUT)
        && c.word.load(Ordering::Acquire) == out
    {
        let ptr = c.ptr.load(Ordering::Relaxed);
        // SAFETY: the cell is out, so the block is empty and the reader's; `new` sized it for `d`.
        unsafe { core::ptr::copy_nonoverlapping(value, ptr as *mut u8, (*d).size as usize) };
        c.word.store(out & !STATE_MASK | FULL, Ordering::Release);
        return;
    }
    // SAFETY: `value` is an owned value of `d` that nothing keeps.
    unsafe { slot_drop(&*d, value) };
}

/// Drops the cell and the value in it.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cells_drop(id: i64) {
    let Some((c, full)) = lookup(id, FULL) else {
        return;
    };
    let generation = full >> STATE_BITS;
    let index = ((id & 0xffff_ffff) - 1) as usize;
    let dead = generation << STATE_BITS | DEAD;
    loop {
        let word = c.word.load(Ordering::Acquire);
        if word >> STATE_BITS != generation {
            return;
        }
        let state = word & STATE_MASK;
        if state == DEAD
            || c.word
                .compare_exchange(word, dead, Ordering::Acquire, Ordering::Relaxed)
                .is_err()
        {
            if state == DEAD {
                return;
            }
            continue;
        }
        // A cell whose read has the value out has an empty block; a late `put` finds it dead.
        free_block(
            c.ptr.load(Ordering::Relaxed),
            c.desc.load(Ordering::Relaxed),
            state == FULL,
        );
        retire(index, generation);
        return;
    }
}

/// Whether the cell holds a value now (a read that is not running).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cells_full(id: i64) -> u8 {
    lookup(id, FULL).is_some_and(|(c, full)| c.word.load(Ordering::Acquire) == full) as u8
}

/// Whether the cell is live with its value out (a holder has it and may put it back); false once
/// the cell is dropped, so a holder whose stream closed closes the value itself.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cells_out(id: i64) -> u8 {
    lookup(id, OUT).is_some_and(|(c, out)| c.word.load(Ordering::Acquire) == out) as u8
}

/// `take` for a caller that binds the value with `try`: moves the value into `out` and answers
/// `STATUS_OK`, or answers `STATUS_CLOSED` when the cell is empty or gone.
///
/// # Safety
/// `out` is writable memory for a value of `d`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_cells_take_result(
    id: i64,
    d: ms_rt_abi::ValueDesc,
    out: *mut u8,
) -> u8 {
    // SAFETY: forwarded contract.
    if unsafe { msrt_cells_take(id, d, out) } == 1 {
        ms_rt_abi::STATUS_OK
    } else {
        ms_rt_abi::STATUS_CLOSED
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::desc::msrt_desc_bool;

    fn desc() -> ms_rt_abi::ValueDesc {
        core::ptr::addr_of!(msrt_desc_bool).cast()
    }

    #[test]
    fn a_cell_gives_its_value_once_and_takes_it_back() {
        let mut v = 1u8;
        let id = unsafe { msrt_cells_new(&mut v, desc()) };
        assert_eq!(msrt_cells_full(id), 1);
        let mut out = 0u8;
        assert_eq!(unsafe { msrt_cells_take(id, desc(), &mut out) }, 1);
        assert_eq!(out, 1);
        assert_eq!(msrt_cells_full(id), 0);
        assert_eq!(unsafe { msrt_cells_take(id, desc(), &mut out) }, 0);
        let mut back = 1u8;
        unsafe { msrt_cells_put(id, &mut back, desc()) };
        assert_eq!(msrt_cells_full(id), 1);
        msrt_cells_drop(id);
        assert_eq!(msrt_cells_full(id), 0);
        assert_eq!(unsafe { msrt_cells_take(id, desc(), &mut out) }, 0);
    }

    #[test]
    fn a_cell_dropped_during_a_read_frees_its_block_and_ignores_the_late_put() {
        let mut v = 1u8;
        let id = unsafe { msrt_cells_new(&mut v, desc()) };
        let mut out = 0u8;
        assert_eq!(unsafe { msrt_cells_take(id, desc(), &mut out) }, 1);
        msrt_cells_drop(id);
        assert_eq!(msrt_cells_full(id), 0);
        unsafe { msrt_cells_put(id, &mut out, desc()) };
        assert_eq!(msrt_cells_full(id), 0);
        // The slot is reusable, and the old id stays dead.
        let mut again = 1u8;
        let next = unsafe { msrt_cells_new(&mut again, desc()) };
        assert_ne!(next, id);
        assert_eq!(msrt_cells_full(id), 0);
        assert_eq!(msrt_cells_full(next), 1);
        msrt_cells_drop(next);
    }
}
