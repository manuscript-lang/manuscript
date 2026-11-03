//! Cells: one owned value of any type, parked in the runtime so a closure can carry only its id.
//!
//! A stream's `read` returns a promise whose work runs later in the waiting task; the work cannot
//! capture the stream (an escaping closure owns its captures), so the stream keeps its source in a
//! cell and the work takes the source out, runs it and puts it back. `take` of an empty cell
//! (a read already running) answers no value.
use crate::alloc;
use crate::desc::slot_drop;
use ms_rt_abi::TypeDesc;
use std::sync::Mutex;

/// A cell owns one block, sized for its value, from `new` until `drop`: `take` and `put` copy the
/// value out of and back into it, so a stream read allocates nothing.
struct Cell {
    generation: u32,
    live: bool,
    /// Whether the block holds the value now (false while a read has it out).
    full: bool,
    ptr: usize,
    desc: usize,
}

struct Table {
    cells: Vec<Cell>,
    /// Indices of dead cells whose generation can still grow.
    free: Vec<u32>,
}

static CELLS: Mutex<Table> = Mutex::new(Table {
    cells: Vec::new(),
    free: Vec::new(),
});

fn cells() -> std::sync::MutexGuard<'static, Table> {
    CELLS.lock().unwrap_or_else(|e| e.into_inner())
}

fn slot(table: &mut Table, id: i64) -> Option<&mut Cell> {
    let i = usize::try_from((id & 0xffff_ffff) - 1).ok()?;
    let c = table.cells.get_mut(i)?;
    (c.live && i64::from(c.generation) == id >> 32).then_some(c)
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
    let mut table = cells();
    let i = match table.free.pop() {
        Some(i) => i as usize,
        None => {
            table.cells.push(Cell {
                generation: 0,
                live: false,
                full: false,
                ptr: 0,
                desc: 0,
            });
            table.cells.len() - 1
        }
    };
    let c = &mut table.cells[i];
    c.generation += 1;
    c.live = true;
    c.full = true;
    c.ptr = ptr;
    c.desc = d as usize;
    (i64::from(c.generation) << 32) | (i as i64 + 1)
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
    let mut table = cells();
    let Some(c) = slot(&mut table, id) else {
        return 0;
    };
    if !c.full {
        return 0;
    }
    c.full = false;
    // SAFETY: the block holds an owned value of `d`; it moves out and the block stays for `put`.
    unsafe { core::ptr::copy_nonoverlapping(c.ptr as *const u8, out, (*d).size as usize) };
    1
}

/// Moves `value` into the (empty) cell; a gone or full cell drops it.
///
/// # Safety
/// `value` holds an owned value of `d`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_cells_put(id: i64, value: *mut u8, d: ms_rt_abi::ValueDesc) {
    let mut table = cells();
    match slot(&mut table, id) {
        Some(c) if !c.full => {
            c.full = true;
            // SAFETY: the block was sized for a value of `d` by `new`; `value` moves in.
            unsafe { core::ptr::copy_nonoverlapping(value, c.ptr as *mut u8, (*d).size as usize) };
        }
        _ => {
            drop(table);
            // SAFETY: `value` is an owned value of `d` that nothing keeps.
            unsafe { slot_drop(&*d, value) };
        }
    }
}

/// Drops the cell and the value in it.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cells_drop(id: i64) {
    let mut table = cells();
    let Some(c) = slot(&mut table, id) else {
        return;
    };
    c.live = false;
    let (ptr, desc, full) = (core::mem::take(&mut c.ptr), c.desc, c.full);
    c.full = false;
    let (index, retired) = {
        let index = (id & 0xffff_ffff) as u32 - 1;
        (index, c.generation >= 0x7fff_ffff)
    };
    if !retired {
        table.free.push(index);
    }
    drop(table);
    free_block(ptr, desc, full);
}

/// Whether the cell holds a value now (a read that is not running).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cells_full(id: i64) -> u8 {
    slot(&mut cells(), id).is_some_and(|c| c.full) as u8
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
