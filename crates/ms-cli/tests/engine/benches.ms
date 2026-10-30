import keep, measure from "@std/bench.ms"
import expect_equal, fail from "@std/test.ms"

fn sum_to(n: Int) Int:
    var total = 0
    for i in 0..n:
        total += i
    return total

bench "sums a range":
    try expect_equal(sum_to(100), 4950)

bench "breaks":
    try fail("not measurable")

test "is not a bench":
    try expect_equal(sum_to(3), 3)

bench "measures after setup":
    let data = [3, 1, 2]
    try measure(3, fn: keep(data.sorted().length()))

bench "reports per operation" per 8:
    try keep(8)
