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

struct Cell {
    generation: u32,
    live: bool,
    ptr: usize,
    desc: usize,
}

static CELLS: Mutex<Vec<Cell>> = Mutex::new(Vec::new());

fn cells() -> std::sync::MutexGuard<'static, Vec<Cell>> {
    CELLS.lock().unwrap_or_else(|e| e.into_inner())
}

fn slot(table: &mut [Cell], id: i64) -> Option<&mut Cell> {
    let i = usize::try_from((id & 0xffff_ffff) - 1).ok()?;
    let c = table.get_mut(i)?;
    (c.live && i64::from(c.generation) == id >> 32).then_some(c)
}

unsafe fn block_of(value: *mut u8, d: *const TypeDesc) -> usize {
    // SAFETY: `value` holds an owned value of `d`, which moves into the new block.
    unsafe {
        let size = (*d).size as usize;
        let block = alloc::alloc(size.max(1));
        core::ptr::copy_nonoverlapping(value, block, size);
        block as usize
    }
}

fn free_block(ptr: usize, desc: usize) {
    if ptr != 0 {
        // SAFETY: the block holds an owned value of its descriptor that nobody took.
        unsafe {
            slot_drop(&*(desc as *const TypeDesc), ptr as *mut u8);
            alloc::free(ptr as *mut u8);
        }
    }
}

/// A new cell holding `value`, which moves in.
///
/// # Safety
/// `value` holds an owned value of `d`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_cells_new(value: *mut u8, d: *const TypeDesc) -> i64 {
    // SAFETY: forwarded contract.
    let ptr = unsafe { block_of(value, d) };
    let mut table = cells();
    let i = match table
        .iter()
        .position(|c| !c.live && c.generation < 0x7fff_ffff)
    {
        Some(i) => i,
        None => {
            table.push(Cell {
                generation: 0,
                live: false,
                ptr: 0,
                desc: 0,
            });
            table.len() - 1
        }
    };
    let c = &mut table[i];
    c.generation += 1;
    c.live = true;
    c.ptr = ptr;
    c.desc = d as usize;
    (i64::from(c.generation) << 32) | (i as i64 + 1)
}

/// Moves the value out into `out` and answers 1; 0 when the cell is empty or gone.
///
/// # Safety
/// `out` is writable memory for a value of `d`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_cells_take(id: i64, d: *const TypeDesc, out: *mut u8) -> u8 {
    let mut table = cells();
    let Some(c) = slot(&mut table, id) else {
        return 0;
    };
    if c.ptr == 0 {
        return 0;
    }
    let ptr = core::mem::replace(&mut c.ptr, 0);
    // SAFETY: the block holds an owned value of `d`; it moves out.
    unsafe {
        core::ptr::copy_nonoverlapping(ptr as *const u8, out, (*d).size as usize);
        alloc::free(ptr as *mut u8);
    }
    1
}

/// Moves `value` into the (empty) cell; a gone cell drops it.
///
/// # Safety
/// `value` holds an owned value of `d`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_cells_put(id: i64, value: *mut u8, d: *const TypeDesc) {
    // SAFETY: forwarded contract.
    let ptr = unsafe { block_of(value, d) };
    let mut table = cells();
    match slot(&mut table, id) {
        Some(c) if c.ptr == 0 => {
            c.ptr = ptr;
            c.desc = d as usize;
        }
        _ => {
            drop(table);
            free_block(ptr, d as usize);
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
    let (ptr, desc) = (core::mem::take(&mut c.ptr), c.desc);
    drop(table);
    free_block(ptr, desc);
}
