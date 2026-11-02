import (
    expect_equal,
    expect_error,
    expect_fault,
    expect_none,
    expect_ok,
    expect_some,
    expect_true
) from "@std/test/test.ms"
import sample, seeded, weighted_choice from "@std/os/random.ms"

test "seeded sample picks distinct items":
    var rng = seeded(7)
    let picked = rng.sample([10, 20, 30, 40, 50], 3)
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
    let _first = try expect_fault(fn: discard(rng.sample([1], 2)))
    let _second = try expect_fault(fn: discard(rng.weighted_choice([1, 2], [1.0])))
    let _third = try expect_fault(fn: discard(rng.weighted_choice([1, 2], [0.0, 0.0])))
    let _fourth = try expect_fault(
        fn: discard(rng.weighted_choice([1, 2], [-1.0, 2.0]))
    )

test "secure sample and weighted_choice":
    let picked = try expect_ok(sample([1, 2, 3, 4], 4))
    try expect_equal(picked.sorted(), [1, 2, 3, 4])
    try expect_equal(try expect_ok(sample([1, 2, 3], 0)), List[Int]())

    let _error = try expect_error(sample([1], 2))
    try expect_equal(
        try expect_some(try expect_ok(weighted_choice(["a", "b"], [0.0, 2.0]))), "b"
    )

    let _other = try expect_error(weighted_choice(["a"], [0.0]))
    try expect_none(try expect_ok(weighted_choice(List[String](), List[Float]())))
