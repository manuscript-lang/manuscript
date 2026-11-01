//! One borrowed bulk call. Read list descriptors lazily so row/cell/byte bounds
//! precede allocations; input cell bytes and nested lists are never copied.
#![allow(unsafe_code)]

use core::slice;
use ms_rt::ffi::{STATUS_OK, StrVal, VecVal, new_string, opt, str_ref};

/// # Safety
/// The generated caller supplies a live `List[List[String]]`, `List[Alignment]`, and writable
/// string output. Every borrowed value outlives this call. Output is written only on success.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_table_format(
    rows: *const VecVal,
    alignments: *const VecVal,
    padding: i64,
    has_max_rows: u8,
    max_rows: i64,
    has_max_cells: u8,
    max_cells: i64,
    has_max_bytes: u8,
    max_bytes: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller contract; empty runtime lists may have null data pointers.
    unsafe {
        let rows = if (*rows).len == 0 {
            &[]
        } else {
            slice::from_raw_parts((*rows).ptr.cast::<VecVal>(), (*rows).len)
        };
        // Alignment has no payload: the standard alternative layout is one i64 case index
        // (ms-clif/src/layout.rs::alt_shape), including when stored inline in a list.
        let alignments = if (*alignments).len == 0 {
            &[]
        } else {
            slice::from_raw_parts((*alignments).ptr.cast::<i64>(), (*alignments).len)
        };
        let rows = rows.iter().map(|row| {
            let cells = if row.len == 0 {
                &[]
            } else {
                slice::from_raw_parts(row.ptr.cast::<StrVal>(), row.len)
            };
            cells.iter().map(|cell| str_ref(cell))
        });
        let limits = crate::Limits {
            rows: opt(has_max_rows, max_rows),
            cells: opt(has_max_cells, max_cells),
            bytes: opt(has_max_bytes, max_bytes),
        };
        match crate::format(rows, alignments, padding, limits) {
            Ok(text) => {
                out.write(new_string(&text));
                STATUS_OK
            }
            Err(error) => error.status(),
        }
    }
}
