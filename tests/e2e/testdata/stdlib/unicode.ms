import (
    is_alphabetic,
    is_alphanumeric,
    is_numeric,
    is_lowercase,
    is_uppercase,
    is_whitespace,
    is_control,
    is_ascii
) from "@std/unicode.ms"
import expect_equal, expect_true, expect_false from "@std/test/test.ms"

test "Unicode properties distinguish letters numbers marks and symbols":
    for text in ["A", "é", "中", "\u{345}"]:
        is_alphabetic(text.scalar_at(0)) | try expect_true
        is_alphanumeric(text.scalar_at(0)) | try expect_true

    for text in ["7", "٣", "Ⅷ", "½"]:
        is_numeric(text.scalar_at(0)) | try expect_true
        is_alphanumeric(text.scalar_at(0)) | try expect_true

    is_numeric("中".scalar_at(0)) | try expect_false
    is_alphabetic("\u{301}".scalar_at(0)) | try expect_false
    is_alphanumeric("🙂".scalar_at(0)) | try expect_false
    is_lowercase("é".scalar_at(0)) | try expect_true
    is_uppercase("É".scalar_at(0)) | try expect_true
    is_uppercase("Ⅷ".scalar_at(0)) | try expect_true
    is_lowercase("ⅷ".scalar_at(0)) | try expect_true

test "Unicode whitespace and controls keep distinct property sets":
    for value in [9, 10, 11, 12, 13, 32, 133, 160, 5760, 8232, 8233, 8239, 8287, 12288]:
        is_whitespace(value) | try expect_true
    for value in 8192..8203: is_whitespace(value) | try expect_true
    for value in [0, 8203, 8205, 65279]: is_whitespace(value) | try expect_false
    for value in [0, 9, 31, 127, 133, 159]: is_control(value) | try expect_true
    for value in [32, 160, 8205, 65279]: is_control(value) | try expect_false
    for value in 0..128: is_ascii(value) | try expect_true
    is_ascii(128) | try expect_false

test "Unicode invalid scalars never wrap into valid characters":
    let predicates = [
        is_alphabetic, is_alphanumeric, is_numeric, is_lowercase, is_uppercase,
        is_whitespace, is_control, is_ascii
    ]
    for value in [-9223372036854775808, -1, 55296, 57343, 1114112, 9223372036854775807]:
        for predicate in predicates: predicate(value) | try expect_false
    for predicate in predicates:
        predicate(1114111) | try expect_false

test "Unicode predicates can be passed as ordinary function values":
    let values = [65, 233, 32, 51, 128578]
    values.filter(is_alphanumeric) | try expect_equal([65, 233, 51])
