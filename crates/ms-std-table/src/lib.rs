//! `@std/io/table.ms` display widths. Unicode widths come from `unicode-width`, with ambiguous
//! characters narrow; the table layout itself is Manuscript.

use ms_rt::ffi::{Fail, native};
use unicode_width::UnicodeWidthStr;

fn width(text: &str) -> Result<i64, Fail> {
    if text
        .chars()
        .any(|c| c.is_control() || matches!(c, '\u{2028}' | '\u{2029}'))
    {
        return Err(Fail::InvalidData);
    }
    Ok(text.width() as i64)
}

native! {
    fn msstd_table_cell_width(text: &str) -> Result<i64, Fail> {
        width(text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unicode_cells_use_sequence_widths() {
        assert_eq!(width("e\u{301}"), Ok(1));
        assert_eq!(width("界"), Ok(2));
        assert_eq!(width("👩\u{200d}💻"), Ok(2));
        assert_eq!(width("·"), Ok(1));
    }

    #[test]
    fn controls_fail() {
        for bad in [
            "\t", "\n", "\r", "\x1b[31m", "\0", "\u{85}", "\u{2028}", "\u{2029}",
        ] {
            assert_eq!(width(bad), Err(Fail::InvalidData));
        }
    }
}
