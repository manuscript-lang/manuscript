//! C ABI shims for `@std/csv.ms` (`msrt_csv_*`).
//!
//! `CsvOptions` is flattened into its two strings, `delimiter` and `line_ending`.
//! Results are written through `out` only when the status is `STATUS_OK`.

use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::{Fail, native};

native! {
    fn msrt_csv_parse(
        text: &str,
        delimiter: &str,
        line_ending: &str,
        has_max_rows: bool,
        max_rows: i64,
        has_max_cells: bool,
        max_cells: i64,
    ) -> Result<Vec<Vec<String>>, Fail> {
        crate::options(delimiter, line_ending).and_then(|o| {
            crate::parse(
                text,
                o,
                has_max_rows.then_some(max_rows),
                has_max_cells.then_some(max_cells),
            )
        })
    }

    fn msrt_csv_stringify(
        rows: Vec<Vec<&str>>,
        delimiter: &str,
        line_ending: &str,
        has_max_bytes: bool,
        max_bytes: i64,
    ) -> Result<String, Fail> {
        crate::options(delimiter, line_ending)
            .and_then(|o| crate::stringify(&rows, o, has_max_bytes.then_some(max_bytes)))
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_std_core::{StrObj, VecVal, new_string, read_string_matrix, str_ref};

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
