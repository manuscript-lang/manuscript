//! C ABI shims for `@std/csv.ms` (`msrt_csv_*`).
//!
//! `CsvOptions` is flattened into its two strings, `delimiter` and `line_ending`.
//! Results are written through `out` only when the status is `STATUS_OK`.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use ms_std_core::{
    StrObj, VecVal, new_string, opt, read_string_matrix, status_of, str_ref, write_string_matrix,
};

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_csv_parse(
    text: *const StrObj,
    delimiter: *const StrObj,
    line_ending: *const StrObj,
    has_max_rows: u8,
    max_rows: i64,
    has_max_cells: u8,
    max_cells: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: all string pointers are live; `out` is writable.
    unsafe {
        let r = crate::options(str_ref(delimiter), str_ref(line_ending)).and_then(|o| {
            crate::parse(
                str_ref(text),
                o,
                opt(has_max_rows, max_rows),
                opt(has_max_cells, max_cells),
            )
        });
        if let Ok(rows) = &r {
            write_string_matrix(out, rows.iter().map(|r| r.iter().map(|s| s.as_str())));
        }
        status_of(&r)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_csv_stringify(
    rows: *const VecVal,
    delimiter: *const StrObj,
    line_ending: *const StrObj,
    has_max_bytes: u8,
    max_bytes: i64,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: `rows` is a live `List[List[String]]`; the strings are live; `out` is writable.
    unsafe {
        let r = crate::options(str_ref(delimiter), str_ref(line_ending)).and_then(|o| {
            crate::stringify(&read_string_matrix(rows), o, opt(has_max_bytes, max_bytes))
        });
        if let Ok(s) = &r {
            out.write(new_string(s));
        }
        status_of(&r)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_std_core::read_string_matrix;

    #[test]
    fn abi_roundtrip() {
        let (text, comma, lf) = (
            new_string("a,\"b,c\"\n1,2\n"),
            new_string(","),
            new_string("\n"),
        );
        let mut rows = MaybeUninit::<VecVal>::uninit();
        let mut s = MaybeUninit::<*mut StrObj>::uninit();
        // SAFETY: all pointers are live; results are released below.
        unsafe {
            assert_eq!(
                msrt_csv_parse(text, comma, lf, 0, 0, 0, 0, rows.as_mut_ptr()),
                0
            );
            assert_eq!(
                read_string_matrix(rows.as_ptr()),
                [["a", "b,c"], ["1", "2"]]
            );
            assert_eq!(
                msrt_csv_stringify(rows.as_ptr(), comma, lf, 0, 0, s.as_mut_ptr()),
                0
            );
            assert_eq!(str_ref(s.assume_init()), "a,\"b,c\"\n1,2\n");
            let bad = new_string("ab");
            assert_eq!(
                msrt_csv_parse(text, bad, lf, 0, 0, 0, 0, rows.as_mut_ptr()),
                ms_std_core::STATUS_INVALID_INPUT
            );
            for o in [text, comma, lf, bad, s.assume_init()] {
                ms_rt::obj::msrt_release(o.cast());
            }
        }
    }
}
