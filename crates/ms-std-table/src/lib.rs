//! Pure table formatting. Unicode display widths come from `unicode-width`, with
//! ambiguous characters narrow. Cells are preserved intact and never interpreted as controls.

pub mod ffi;

use ms_rt::ffi::Fail;
use unicode_width::UnicodeWidthStr;

#[derive(Clone, Copy, Default)]
pub struct Limits {
    pub rows: Option<i64>,
    pub cells: Option<i64>,
    pub bytes: Option<i64>,
}

fn budget(n: Option<i64>) -> Result<usize, Fail> {
    match n {
        Some(n) => usize::try_from(n).map_err(|_| Fail::InvalidInput),
        None => Ok(usize::MAX),
    }
}

fn add(total: &mut usize, n: usize, max: usize) -> Result<(), Fail> {
    *total = total.checked_add(n).ok_or(Fail::LimitExceeded)?;
    if *total > max {
        return Err(Fail::LimitExceeded);
    }
    Ok(())
}

fn width(text: &str) -> Result<usize, Fail> {
    if text
        .chars()
        .any(|c| c.is_control() || matches!(c, '\u{2028}' | '\u{2029}'))
    {
        return Err(Fail::InvalidData);
    }
    Ok(text.width())
}

fn leading(align: i64, spare: usize) -> usize {
    match align {
        1 => spare,
        2 => spare / 2,
        _ => 0,
    }
}

/// Iterators borrow cell text. Repeated passes avoid copying rows or caching a width per cell.
/// Only column widths are allocated before the exact output length is known.
pub fn format<'a, R, C>(
    rows: R,
    alignments: &[i64],
    padding: i64,
    limits: Limits,
) -> Result<String, Fail>
where
    R: ExactSizeIterator<Item = C> + Clone,
    C: ExactSizeIterator<Item = &'a str> + Clone,
{
    let max_rows = budget(limits.rows)?;
    let max_cells = budget(limits.cells)?;
    let max_bytes = budget(limits.bytes)?.min(ms_rt::string::MAX_BYTES);
    let padding = usize::try_from(padding).map_err(|_| Fail::InvalidInput)?;
    let count = rows.len();
    if count > max_rows {
        return Err(Fail::LimitExceeded);
    }
    let columns = rows.clone().next().map_or(0, |r| r.len());
    if !alignments.is_empty() && alignments.len() != columns {
        return Err(Fail::InvalidInput);
    }
    let cells = count.checked_mul(columns).ok_or(Fail::LimitExceeded)?;
    if cells > max_cells {
        return Err(Fail::LimitExceeded);
    }
    if alignments.iter().any(|&a| !(0..=2).contains(&a)) {
        return Err(Fail::InvalidInput);
    }
    // Count separators and row breaks before allocating even column metadata.
    let gap = columns
        .saturating_sub(1)
        .checked_mul(padding)
        .ok_or(Fail::LimitExceeded)?;
    let mut bytes = count.saturating_sub(1);
    add(
        &mut bytes,
        gap.checked_mul(count).ok_or(Fail::LimitExceeded)?,
        max_bytes,
    )?;
    // Validate rectangularity and a byte lower bound before allocating widths. A zero-column
    // row is a blank line; an empty table is the empty string.
    for row in rows.clone() {
        if row.len() != columns {
            return Err(Fail::InvalidData);
        }
        for cell in row {
            add(&mut bytes, cell.len(), max_bytes)?;
        }
    }
    let mut widths = vec![0; columns];
    for row in rows.clone() {
        for (col, cell) in row.enumerate() {
            widths[col] = widths[col].max(width(cell)?);
        }
    }
    // Padding in the last column has no trailing spaces. Centering puts an odd extra space
    // on the right (which is omitted for the last column).
    for row in rows.clone() {
        for (col, cell) in row.enumerate() {
            let spare = widths[col] - cell.width();
            let fill = if col + 1 == columns {
                leading(alignments.get(col).copied().unwrap_or(0), spare)
            } else {
                spare
            };
            add(&mut bytes, fill, max_bytes)?;
        }
    }
    let mut output = String::with_capacity(bytes);
    for (index, row) in rows.enumerate() {
        if index > 0 {
            output.push('\n');
        }
        for (col, cell) in row.enumerate() {
            if col > 0 {
                output.extend(core::iter::repeat_n(' ', padding));
            }
            let spare = widths[col] - cell.width();
            let left = leading(alignments.get(col).copied().unwrap_or(0), spare);
            output.extend(core::iter::repeat_n(' ', left));
            output.push_str(cell);
            if col + 1 < columns {
                output.extend(core::iter::repeat_n(' ', spare - left));
            }
        }
    }
    debug_assert_eq!(bytes, output.len());
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn table(
        rows: &[&[&str]],
        aligns: &[i64],
        padding: i64,
        limits: Limits,
    ) -> Result<String, Fail> {
        format(
            rows.iter().map(|r| r.iter().copied()),
            aligns,
            padding,
            limits,
        )
    }

    #[test]
    fn alignment_and_no_trailing_padding() {
        let rows: &[&[&str]] = &[&["abc", "1234", "last"], &["x", "2", "z"]];
        assert_eq!(
            table(rows, &[0, 1, 2], 2, Limits::default()),
            Ok("abc  1234  last\nx       2   z".into())
        );
        assert_eq!(
            table(&[&["a"], &["abc"]], &[2], 0, Limits::default()),
            Ok(" a\nabc".into())
        );
    }

    #[test]
    fn unicode_cells_are_intact_and_use_sequence_widths() {
        let rows: &[&[&str]] = &[&["e\u{301}", "x"], &["界", "y"], &["👩‍💻", "z"], &["·", "w"]];
        assert_eq!(
            table(rows, &[], 1, Limits::default()),
            Ok("e\u{301}  x\n界 y\n👩‍💻 z\n·  w".into())
        );
    }

    #[test]
    fn controls_and_ragged_rows_fail() {
        for bad in [
            "\t", "\n", "\r", "\x1b[31m", "\0", "\u{85}", "\u{2028}", "\u{2029}",
        ] {
            assert_eq!(
                table(&[&[bad]], &[], 2, Limits::default()),
                Err(Fail::InvalidData)
            );
        }
        assert_eq!(
            table(&[&["x"], &[]], &[], 2, Limits::default()),
            Err(Fail::InvalidData)
        );
        assert_eq!(
            table(&[&[], &["x"]], &[], 2, Limits::default()),
            Err(Fail::InvalidData)
        );
    }

    #[test]
    fn empty_tables_and_zero_budgets() {
        let zero = Limits {
            rows: Some(0),
            cells: Some(0),
            bytes: Some(0),
        };
        assert_eq!(table(&[], &[], 2, zero), Ok(String::new()));
        assert_eq!(table(&[&[]], &[], 2, Limits::default()), Ok(String::new()));
        assert_eq!(
            table(&[&[], &[]], &[], 2, Limits::default()),
            Ok("\n".into())
        );
        assert_eq!(
            table(
                &[&[""]],
                &[],
                2,
                Limits {
                    cells: Some(1),
                    bytes: Some(0),
                    ..Limits::default()
                }
            ),
            Ok(String::new())
        );
    }

    #[test]
    fn budgets_count_rows_cells_and_exact_utf8_output() {
        let rows: &[&[&str]] = &[&["界", "x"], &["a", "yz"]];
        let text = table(rows, &[1, 1], 2, Limits::default()).unwrap();
        assert_eq!(text, "界   x\n a  yz");
        for (rows_max, cells_max, bytes_max) in
            [(1, 4, 100), (2, 3, 100), (2, 4, text.len() as i64 - 1)]
        {
            assert_eq!(
                table(
                    rows,
                    &[1, 1],
                    2,
                    Limits {
                        rows: Some(rows_max),
                        cells: Some(cells_max),
                        bytes: Some(bytes_max)
                    }
                ),
                Err(Fail::LimitExceeded)
            );
        }
        assert_eq!(
            table(
                rows,
                &[1, 1],
                2,
                Limits {
                    rows: Some(2),
                    cells: Some(4),
                    bytes: Some(text.len() as i64)
                }
            ),
            Ok(text)
        );
        for limits in [
            Limits {
                rows: Some(-1),
                ..Limits::default()
            },
            Limits {
                cells: Some(-1),
                ..Limits::default()
            },
            Limits {
                bytes: Some(-1),
                ..Limits::default()
            },
        ] {
            assert_eq!(table(&[], &[], 2, limits), Err(Fail::InvalidInput));
        }
        assert_eq!(
            table(rows, &[], -1, Limits::default()),
            Err(Fail::InvalidInput)
        );
        assert_eq!(
            table(rows, &[0], 2, Limits::default()),
            Err(Fail::InvalidInput)
        );
        assert_eq!(
            table(rows, &[0, 3], 2, Limits::default()),
            Err(Fail::InvalidInput)
        );
        assert_eq!(
            table(rows, &[], i64::MAX, Limits::default()),
            Err(Fail::LimitExceeded)
        );
    }

    #[test]
    fn row_budget_is_checked_without_visiting_cells() {
        let rows = (0..100).map(|_| -> core::iter::Empty<&str> { panic!("visited row") });
        assert_eq!(
            format(
                rows,
                &[],
                2,
                Limits {
                    rows: Some(1),
                    ..Limits::default()
                }
            ),
            Err(Fail::LimitExceeded)
        );
    }

    #[test]
    fn cell_and_byte_budgets_precede_cell_reads() {
        let rows = core::iter::once((0..100).map(|_| -> &str { panic!("visited cell") }));
        assert_eq!(
            format(
                rows.clone(),
                &[],
                2,
                Limits {
                    cells: Some(1),
                    ..Limits::default()
                }
            ),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(
            format(
                rows,
                &[],
                2,
                Limits {
                    bytes: Some(1),
                    ..Limits::default()
                }
            ),
            Err(Fail::LimitExceeded)
        );
    }
}
