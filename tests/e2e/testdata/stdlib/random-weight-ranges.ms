import (
    seeded, weighted_choice from "@std/random.ms",
    infinity, max_float, min_float, nan from "@std/math/math.ms",
    expect_equal,
    expect_error,
    expect_fault,
    expect_none,
    expect_some from "@std/test/test.ms",
)

fn compare_draws(weights: List[Float], ordinary: List[Float]) Unit!:
    var scaled = seeded(1)
    var reference = seeded(1)
    var draws = seeded(1)

    for draw in 0..1000:
        _point := draws.float()
        try expect_equal(
            scaled.weighted_choice([0, 1], weights),
            reference.weighted_choice([0, 1], ordinary)
        )

    // Selection consumes exactly one draw, independent of the weight scale.
    next := scaled.next_bits()
    try expect_equal(next, reference.next_bits())
    try expect_equal(next, draws.next_bits())

test "seeded weighted choices retain ratios across the Float range":
    try compare_draws([max_float, max_float], [1.0, 1.0])
    try compare_draws([min_float, min_float], [1.0, 1.0])
    try compare_draws([max_float / 2.0, max_float], [1.0, 2.0])
    try compare_draws([min_float, min_float * 2.0], [1.0, 2.0])
    try compare_draws([1e-300, 2e-300], [1.0, 2.0])
    try compare_draws([1e300, 2e300], [1.0, 2.0])

test "ordinary weighted choices keep direct draws":
    for weights in [
        [1.0, 2.0], [max_float / 2.0, max_float / 4.0],
        [1.1125369292536007e-308, 1.1125369292536007e-308],
        [0.8833108082136426, 0.1166891917863574]
    ]:
        var rng = seeded(0)
        var direct = seeded(0)
        total := weights[0] + weights[1]

        for draw in 0..1000:
            point := direct.float() * total
            expected := if point < weights[0]: 0 else: 1
            try expect_equal(rng.weighted_choice([0, 1], weights), expected)

    // The largest unit draw rounds to the minimum-normal total; keep the last positive slot.
    var edge = seeded(3558559446808474027)
    try expect_equal(
        edge.weighted_choice(
            [0, 1, 2], [2.2250738585072014e-308 - min_float, min_float, 0.0]
        ),
        1
    )

test "secure weighted choices accept finite extreme weights":
    for draw in 0..32:
        huge := try expect_some(try weighted_choice([0, 1], [max_float, max_float]))
        try expect_equal(huge == 0 or huge == 1, true)

        tiny := try expect_some(try weighted_choice([0, 1], [min_float, min_float]))
        try expect_equal(tiny == 0 or tiny == 1, true)
        try expect_equal(
            try expect_some(
                try weighted_choice([0, 1, 2], [0.0, max_float, -0.0])
            ),
            1
        )
        try expect_equal(
            try expect_some(
                try weighted_choice([0, 1, 2], [0.0, min_float, -0.0])
            ),
            1
        )

test "weighted choices retain zero exclusions and caller values":
    var tiny_first = seeded(7046029254386353131)
    var tiny_last = seeded(7046029254386353131)
    try expect_equal(
        tiny_first.weighted_choice(
            [0, 1, 2], [min_float, max_float, max_float]
        ),
        1
    )
    try expect_equal(
        tiny_last.weighted_choice([0, 1, 2], [max_float, max_float, min_float]), 0
    )

    // This seed makes the next SplitMix64 draw exactly zero.
    var rng = seeded(7046029254386353131)
    try expect_equal(rng.weighted_choice([0, 1, 2], [0.0, min_float, 0.0]), 1)

    values := [[1], [2]]
    weights := [max_float, max_float]
    var picked = try expect_some(rng.weighted_choice(values, weights))
    picked.append(3)
    try expect_equal(values, [[1], [2]])
    try expect_equal(weights, [max_float, max_float])

fn invalid_seeded(weights: List[Float]) Unit:
    var rng = seeded(1)
    _picked := rng.weighted_choice([0, 1], weights)

test "weighted choices preserve invalid input and empty behavior":
    for weights in [
        [0.0, 0.0], [-0.0, 0.0], [-1.0, 1.0], [nan, 1.0], [1.0, nan], [infinity, 1.0],
        [1.0, -infinity], [1.0], List[Float]()
    ]:
        try expect_equal(
            (try expect_error(weighted_choice([0, 1], weights))).kind, "EINVAL"
        )

        _message := try expect_fault(fn: invalid_seeded(weights))

    var rng = seeded(1)
    try expect_none(rng.weighted_choice(List[Int](), List[Float]()))
    try expect_none(try weighted_choice(List[Int](), List[Float]()))
    try expect_equal(
        (try expect_error(weighted_choice(List[Int](), [1.0]))).kind, "EINVAL"
    )
