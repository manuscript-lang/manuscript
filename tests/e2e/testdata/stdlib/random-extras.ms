import (
    expect_equal,
    expect_error,
    expect_fault,
    expect_none,
    expect_ok,
    expect_some,
    expect_true from "@std/test/test.ms",
    choice, secure_int, sample, seeded, shuffle, weighted_choice from "@std/random.ms",
)

test "seeded sample picks distinct items":
    var rng = seeded(7)
    picked := rng.sample([10, 20, 30, 40, 50], 3)
    try expect_equal(picked.length(), 3)
    try expect_equal(picked.sorted().length(), 3)
    for item in picked:
        try expect_true(item % 10 == 0 and item >= 10 and item <= 50)
    try expect_equal(
        picked[0] == picked[1] or picked[1] == picked[2] or picked[0] == picked[
            2
        ],
        false
    )

    var again = seeded(7)
    try expect_equal(again.sample([10, 20, 30, 40, 50], 3), picked)
    try expect_equal(rng.sample([1, 2], 0), List[Int]())
    try expect_equal(rng.sample([1, 2, 3], 3).sorted(), [1, 2, 3])

test "seeded weighted_choice follows the weights":
    var rng = seeded(3)
    for round in 0..50:
        try expect_equal(
            try expect_some(
                rng.weighted_choice(["a", "b", "c"], [0.0, 1.0, 0.0])
            ),
            "b"
        )
    try expect_none(rng.weighted_choice(List[String](), List[Float]()))

    var heavy = 0
    for draw in 0..200:
        if try expect_some(rng.weighted_choice(["x", "y"], [9.0, 1.0])) == "x":
            heavy += 1
    try expect_true(heavy > 140)

fn discard[T](value: T) Unit:
    return unit

test "seeded invalid arguments fault":
    var rng = seeded(1)
    _first := try expect_fault(fn: discard(rng.sample([1], 2)))
    _second := try expect_fault(fn: discard(rng.weighted_choice([1, 2], [1.0])))
    _third := try expect_fault(fn: discard(rng.weighted_choice([1, 2], [0.0, 0.0])))
    _fourth := try expect_fault(fn: discard(rng.weighted_choice([1, 2], [-1.0, 2.0])))

test "secure sample and weighted_choice":
    picked := try expect_ok(sample([1, 2, 3, 4], 4))
    try expect_equal(picked.sorted(), [1, 2, 3, 4])
    try expect_equal(try expect_ok(sample([1, 2, 3], 0)), List[Int]())

    _error := try expect_error(sample([1], 2))
    try expect_equal(
        try expect_some(try expect_ok(weighted_choice(["a", "b"], [0.0, 2.0]))), "b"
    )

    _other := try expect_error(weighted_choice(["a"], [0.0]))
    try expect_none(try expect_ok(weighted_choice(List[String](), List[Float]())))

test "secure_int covers wide and empty ranges":
    _same := try expect_error(secure_int(3, 3))
    _reversed := try expect_error(secure_int(5, 2))
    try expect_equal(try secure_int(7, 8), 7)

    wide := try secure_int(-9223372036854775807 - 1, none)
    try expect_true(wide <= 9223372036854775806)

    low := try secure_int(-9223372036854775807 - 1, -9223372036854775807)
    try expect_equal(low, -9223372036854775807 - 1)

    empty: List[Int] = []
    try expect_equal(try choice(empty), none)
    try expect_equal(try shuffle([5]), [5])

fn draw_wide(min: Int, max_exclusive: Int) Unit:
    var rng = seeded(1)
    discard(rng.int(min, max_exclusive))

test "seeded int names a range wider than the largest Int":
    message := try expect_fault(
        fn: draw_wide(-9223372036854775807, 9223372036854775807)
    )
    try expect_true(message.contains("wider than the largest Int"))

    edge := try expect_fault(fn: draw_wide(-1, 9223372036854775807))
    try expect_true(edge.contains("wider than the largest Int"))

    var rng = seeded(1)
    widest := rng.int(-1, 9223372036854775806)
    try expect_true(widest >= -1 and widest < 9223372036854775806)
