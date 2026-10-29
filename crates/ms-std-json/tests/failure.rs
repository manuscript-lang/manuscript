use ms_rt::ffi::Fail;
use ms_std_json::{Limits, parse};

#[test]
fn syntax_errors_keep_invalid_data_with_unread_suffixes() {
    for suffix in ["plain", "\\\\\\\\", "\"\\u0041\"", "\"\\uD800\"", "\"\\u12"] {
        for prefix in ["]", "true x"] {
            let text = format!("{prefix}{suffix}");
            assert_eq!(
                parse(&text, Limits::default()).err(),
                Some(Fail::InvalidData)
            );
        }
    }
    let text = format!("]{}", "\\".repeat(4096));
    assert_eq!(
        parse(&text, Limits::default()).err(),
        Some(Fail::InvalidData)
    );
}

#[test]
fn unicode_errors_still_outrank_a_value_limit() {
    let limits = Limits {
        max_values: Some(0),
        ..Limits::default()
    };
    for text in ["\"\\uD800\"", "\"\\uDC00\"", "\"\\u12"] {
        assert_eq!(parse(text, limits).err(), Some(Fail::InvalidData));
    }
    assert_eq!(
        parse("\"\\u0041\"", limits).err(),
        Some(Fail::LimitExceeded)
    );
    assert_eq!(parse("true", limits).err(), Some(Fail::LimitExceeded));
}

#[test]
fn byte_and_negative_budgets_keep_admission_precedence() {
    let invalid_unicode = "\"\\uD800\"";
    assert_eq!(
        parse(
            invalid_unicode,
            Limits {
                max_bytes: Some(0),
                ..Limits::default()
            }
        )
        .err(),
        Some(Fail::LimitExceeded)
    );
    assert_eq!(
        parse(
            invalid_unicode,
            Limits {
                max_values: Some(-1),
                ..Limits::default()
            }
        )
        .err(),
        Some(Fail::InvalidInput)
    );
}
