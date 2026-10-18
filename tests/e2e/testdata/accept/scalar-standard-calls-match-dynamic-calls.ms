import {expect_true} from "@std/testing.ms"
import {
    abs,
    abs_int,
    atan2,
    ceil,
    floor,
    max,
    min,
    pow,
    remainder,
    round,
    sqrt,
    truncate
} from "@std/math.ms"

fn viaValue(f: fn(value: Float) -> Float, x: Float) -> Float: f(value: x)

test "typed math":
    (sqrt(value: 9.0) == 3.0) | try expect_true
    (viaValue(f: sqrt, x: 16.0) == 4.0) | try expect_true
    (abs(value: 0.0 - 2.5) == 2.5 and abs_int(value: 0 - 7) == 7) | try expect_true
    try expect_true(
        (
            floor(value: 2.7) == 2.0
            and ceil(value: 2.1) == 3.0
            and truncate(value: (0.0 - 2.7)) == 0.0 - 2.0
        )
    )
    ((round(value: 2.5) == 3.0 and round(value: 0.0 - 2.5) == 0.0 - 2.0)) | try expect_true
    (pow(base: 2.0, exponent: 10.0) == 1024.0) | try expect_true
    try expect_true(
        (
            min(left: 1.0, right: 2.0) == 1.0
            and max(left: 1.0, right: 2.0) == 2.0
        )
    )
    (remainder(left: 7.0, right: 4.0) == 3.0) | try expect_true
    (atan2(y: 0.0, x: 1.0) == 0.0) | try expect_true
    (sqrt(value: 0.0 - 1.0).is_nan() and sqrt(value: 1.0).is_finite()) | try expect_true
    var total = 0.0
    var i = 0

    while i < 4:
        total = total + sqrt(value: 4.0) + abs(value: 0.0 - 1.0)
        i = i + 1

    (total == 12.0) | try expect_true

test "typed string members":
    let text = "  Hello World  "
    (text.trim() == "Hello World") | try expect_true
    try expect_true(
        (
            text.trim().upper() == "HELLO WORLD"
            and text.trim().lower() == "hello world"
        )
    )
    ((text.contains(value: "World") and not text.contains(value: "world"))) | try expect_true
    try expect_true(
        (
            text.trim().starts_with(prefix: "Hello")
            and text.trim().ends_with(suffix: "World")
        )
    )
