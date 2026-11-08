import BinCounts from "@std/math/statistics.ms"
import (
    expect_close,
    expect_equal,
    expect_fault,
    expect_none,
    expect_some
) from "@std/test/test.ms"
import (
    correlation,
    bin_counts,
    linear_regression,
    mean,
    median,
    mode,
    percentile,
    population_stdev,
    population_variance,
    quantiles,
    stdev,
    variance
) from "@std/math/statistics.ms"

test "mean median and mode":
    try expect_close(try expect_some(mean([1.0, 2.0, 6.0])), 3.0, 0.000001)
    try expect_none(mean(List[Float]()))
    try expect_close(try expect_some(median([5.0, 1.0, 3.0])), 3.0, 0.000001)
    try expect_close(try expect_some(median([5.0, 1.0, 3.0, 2.0])), 2.5, 0.000001)
    try expect_none(median(List[Float]()))
    try expect_close(try expect_some(mode([2.0, 1.0, 2.0, 1.0, 3.0])), 1.0, 0.000001)
    try expect_close(try expect_some(mode([4.0, 4.0, 1.0])), 4.0, 0.000001)
    try expect_none(mode(List[Float]()))

test "variance and standard deviation":
    let data = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
    try expect_close(try expect_some(population_variance(data)), 4.0, 0.000001)
    try expect_close(try expect_some(population_stdev(data)), 2.0, 0.000001)
    try expect_close(
        try expect_some(variance([1.0, 2.0, 3.0, 4.0])), 1.6666666666666667, 0.000001
    )
    try expect_close(try expect_some(stdev(data)), 2.138089935, 0.000001)
    try expect_none(variance([1.0]))
    try expect_none(stdev(List[Float]()))
    try expect_close(try expect_some(population_variance([3.0])), 0.0, 0.000001)

test "percentile and quantiles interpolate":
    let data = [5.0, 1.0, 3.0, 2.0, 4.0]
    try expect_close(try expect_some(percentile(data, 0.0)), 1.0, 0.000001)
    try expect_close(try expect_some(percentile(data, 25.0)), 2.0, 0.000001)
    try expect_close(try expect_some(percentile(data, 50.0)), 3.0, 0.000001)
    try expect_close(try expect_some(percentile(data, 100.0)), 5.0, 0.000001)
    try expect_close(try expect_some(percentile([1.0, 2.0], 50.0)), 1.5, 0.000001)
    try expect_none(percentile(List[Float](), 50.0))
    try expect_equal(quantiles(data, 4), [2.0, 3.0, 4.0])
    try expect_equal(quantiles(List[Float](), 4), List[Float]())

test "percentile keeps infinite neighbors from becoming NaN":
    let inf = 1.0 / 0.0
    try expect_equal(try expect_some(percentile([1.0, inf], 0.0)), 1.0)
    try expect_equal(try expect_some(percentile([inf, inf], 50.0)), inf)
    try expect_equal(try expect_some(percentile([1.0, inf, inf], 50.0)), inf)
    try expect_equal(try expect_some(percentile([-inf, 5.0], 40.0)), -inf)
    try expect_equal(quantiles([1.0, inf], 2), [inf])

test "bin_counts bins values":
    let h = try expect_some(bin_counts([1.0, 2.0, 2.0, 3.0], 2))
    try expect_equal(h.counts, [1, 3])
    try expect_close(h.low, 1.0, 0.000001)
    try expect_close(h.high, 3.0, 0.000001)

    let same = try expect_some(bin_counts([2.0, 2.0], 3))
    try expect_equal(same.counts, [2, 0, 0])
    try expect_none(bin_counts(List[Float](), 2))

test "bin_counts places the greatest value in the last bin when the range overflows":
    let inf = 1.0 / 0.0
    let wide = try expect_some(bin_counts([-1.7e308, 0.0, 1.7e308, 1.7e308], 2))
    try expect_equal(wide.counts, [1, 3])

    let unbounded = try expect_some(bin_counts([0.0, 1.0, inf], 2))
    try expect_equal(unbounded.counts, [2, 1])

test "correlation and regression":
    try expect_close(
        try expect_some(correlation([1.0, 2.0, 3.0], [2.0, 4.0, 6.0])), 1.0, 0.000001
    )
    try expect_close(
        try expect_some(correlation([1.0, 2.0, 3.0], [6.0, 4.0, 2.0])), -1.0, 0.000001
    )
    try expect_none(correlation([1.0, 1.0, 1.0], [1.0, 2.0, 3.0]))
    try expect_none(correlation([1.0], [2.0]))

    let line = try expect_some(linear_regression([1.0, 2.0, 3.0], [3.0, 5.0, 7.0]))
    try expect_close(line.slope, 2.0, 0.000001)
    try expect_close(line.intercept, 1.0, 0.000001)
    try expect_none(linear_regression([2.0, 2.0], [1.0, 3.0]))

fn discard[T](value: T) Unit:
    return unit

test "invalid arguments fault":
    let _first = try expect_fault(fn: discard(percentile([1.0], 101.0)))
    let _second = try expect_fault(fn: discard(quantiles([1.0], 1)))
    let _third = try expect_fault(fn: discard(bin_counts([1.0], 0)))
    let _fourth = try expect_fault(fn: discard(correlation([1.0, 2.0], [1.0])))

test "percentile finite spans do not overflow during interpolation":
    let values = [-1e308, 1e308]
    try expect_equal(try expect_some(percentile(values, 0.0)), -1e308)
    try expect_equal(try expect_some(percentile(values, 50.0)), 0.0)
    try expect_equal(try expect_some(percentile(values, 100.0)), 1e308)

    let cuts = quantiles(values, 4)
    try expect_close(cuts[0] / 1e308, -0.5, 1e-15)
    try expect_equal(cuts[1], 0.0)
    try expect_close(cuts[2] / 1e308, 0.5, 1e-15)
    try expect_close(
        (try expect_some(percentile([-1.5e308, 1e308], 40.0))) / 1e308, -0.5, 1e-15
    )

test "percentile stays finite ordered and bounded across the widest finite span":
    let edge = 1.7976931348623157e308
    var previous = -edge

    for percent in 0..101:
        let result = try expect_some(percentile([-edge, edge], percent.to_float()))
        try expect_equal(result.is_finite(), true)
        try expect_equal(result >= previous and result <= edge, true)
        previous = result

    try expect_equal(previous, edge)

test "percentile preserves finite small spans and special-value behavior":
    try expect_close(
        (try expect_some(percentile([1e308, 1.5e308], 50.0))) / 1e308, 1.25, 1e-15
    )
    try expect_close(
        (try expect_some(percentile([-1.5e308, -1e308], 50.0))) / 1e308, -1.25, 1e-15
    )
    try expect_equal(try expect_some(percentile([-1e-300, 1e-300], 50.0)), 0.0)
    try expect_equal(try expect_some(percentile([-1e-323, 5e-324], 50.0)), 0.0)

    let inf = 1.0 / 0.0
    let nan = 0.0 / 0.0
    try expect_equal(try expect_some(percentile([1.0, inf], 50.0)), inf)
    try expect_equal(try expect_some(percentile([-inf, 1.0], 50.0)), -inf)

    let opposite = try expect_some(percentile([-inf, inf], 50.0))
    try expect_equal(opposite.is_nan(), true)

    let unordered = try expect_some(percentile([nan, nan], 50.0))
    try expect_equal(unordered.is_nan(), true)

test "median finite middle values do not overflow their sum":
    let edge = 1.7976931348623157e308
    try expect_equal(try expect_some(median([edge, edge])), edge)
    try expect_equal(try expect_some(median([-edge, -edge])), -edge)
    try expect_close((try expect_some(median([1e308, 1.5e308]))) / 1e308, 1.25, 1e-15)
    try expect_close(
        (try expect_some(median([-1.5e308, -1e308]))) / 1e308, -1.25, 1e-15
    )
    try expect_equal(try expect_some(median([-edge, edge])), 0.0)
    try expect_equal(try expect_some(median([edge, edge, edge, edge])), edge)

test "median keeps ordinary tiny and nonfinite behavior":
    try expect_equal(try expect_some(median([5e-324, 5e-324])), 5e-324)
    try expect_equal(try expect_some(median([-5e-324, -5e-324])), -5e-324)
    try expect_equal(try expect_some(median([-5e-324, 5e-324])), 0.0)
    try expect_equal(try expect_some(median([1e-300, 3e-300])), 2e-300)
    try expect_equal(try expect_some(median([-0.0, 0.0])), 0.0)

    let inf = 1.0 / 0.0
    let nan = 0.0 / 0.0
    try expect_equal(try expect_some(median([inf, inf])), inf)
    try expect_equal(try expect_some(median([-inf, -inf])), -inf)
    try expect_equal(try expect_some(median([1.0, inf])), inf)
    try expect_equal(try expect_some(median([-inf, 1.0])), -inf)
    try expect_equal((try expect_some(median([-inf, inf]))).is_nan(), true)
    try expect_equal((try expect_some(median([nan, nan]))).is_nan(), true)

test "subnormal equal width bins preserve mathematical placement":
    let step = 5e-324
    let result = try expect_some(bin_counts([0.0, step, 2.0 * step], 4))
    try expect_equal(result.counts, [1, 0, 1, 1])

test "rounded subnormal width does not move interior values":
    let step = 5e-324
    let result = try expect_some(
        bin_counts([0.0, step, 2.0 * step, 3.0 * step, 4.0 * step], 3)
    )
    try expect_equal(result.counts, [2, 1, 2])

test "subnormal bins match an exact integer grid across signs and shifted ranges":
    let step = 5e-324

    for base in [0.0, 2.2250738585072014e-308, -2.2250738585072014e-308]:
        for offset in [-20, 0, 20]:
            for span in [1, 2, 4, 7, 13]:
                for bins in [1, 2, 3, 4, 7, 17]:
                    var values: List[Float] = []
                    var expected: List[Int] = []
                    for index in 0..bins: expected.append(0)

                    for position in 0..span + 1:
                        // Reverse ordering and duplicate values must not change placement.
                        let coordinate = span - position
                        let value = base + (offset + coordinate).to_float() * step
                        values.append(value)
                        values.append(value)

                        let index = if coordinate == span: bins - 1 else: coordinate * bins / span
                        expected.set(index, expected[index] + 2)

                    let result = try expect_some(bin_counts(values, bins))
                    try expect_equal(result.counts, expected)

test "subnormal bin repair preserves nonfinite and degenerate controls":
    let nan = 0.0 / 0.0
    let inf = 1.0 / 0.0

    for values in [
        [0.0, nan, 5e-324, 1e-323], [nan, 0.0, 5e-324, 1e-323],
        [0.0, 5e-324, 1e-323, nan]
    ]:
        let result = try expect_some(bin_counts(values, 4))
        try expect_equal(result.counts, [4, 0, 0, 0])

    for values in [[0.0, inf], [-inf, 0.0]]:
        let result = try expect_some(bin_counts(values, 4))
        try expect_equal(result.counts, [1, 0, 0, 1])

    for values in [[nan, nan], [5e-324, 5e-324], [-5e-324, -5e-324]]:
        let result = try expect_some(bin_counts(values, 4))
        try expect_equal(result.counts, [2, 0, 0, 0])
