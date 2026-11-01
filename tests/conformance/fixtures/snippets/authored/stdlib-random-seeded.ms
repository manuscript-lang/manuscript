# conform: tags=stdlib-random,testing,tier-core
# conform: phase=test
# conform: origin=issue 2166
import expect_equal, expect_fault from "@std/test/test.ms"
import seeded from "@std/os/random.ms"

test "equal seeds give equal sequences and match SplitMix64":
    var first = seeded(1)
    var second = seeded(1)
    try expect_equal(first.next_bits(), -7995527694508729151)
    try expect_equal(first.next_bits(), -4689498862643123097)
    try expect_equal(second.next_bits(), -7995527694508729151)

test "int stays in range and is reproducible":
    var rng = seeded(1)
    var drawn = List[Int]()
    for step in 0..5:
        drawn.append(rng.int(0, 10))
    try expect_equal(drawn, [2, 9, 5, 7, 0])

    var wide = seeded(9)

    for step in 0..200:
        let value = wide.int(-3, 4)
        try expect_equal(value >= -3 and value < 4, true)

test "float is below one and reproducible":
    var rng = seeded(1)
    try expect_equal(rng.float(), 0.5665615751722809)

test "shuffle keeps the items and choice picks one":
    var rng = seeded(5)
    let shuffled = rng.shuffle([1, 2, 3, 4, 5, 6])
    try expect_equal(shuffled.sorted(fn(a: Int, b: Int) Int: a - b), [1, 2, 3, 4, 5, 6])
    try expect_equal(seeded(5).shuffle([1, 2, 3, 4, 5, 6]), shuffled)
    try expect_equal(rng.choice(List[Int]()), none)
    try expect_equal(seeded(2).choice([7]), 7)

fn draw_from_empty_range() Unit:
    var rng = seeded(1)
    rng.int(3, 3)

test "an empty range faults":
    let message = try expect_fault(draw_from_empty_range)
    try expect_equal(message.contains("min must be below"), true)
