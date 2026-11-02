import Histogram from "@std/math/statistics.ms"
import (
    expect_close,
    expect_equal,
    expect_fault,
    expect_none,
    expect_some
) from "@std/test/test.ms"
import (
    correlation,
    histogram,
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

test "histogram bins values":
    let h = try expect_some(histogram([1.0, 2.0, 2.0, 3.0], 2))
    try expect_equal(h.counts, [1, 3])
    try expect_close(h.low, 1.0, 0.000001)
    try expect_close(h.high, 3.0, 0.000001)

    let same = try expect_some(histogram([2.0, 2.0], 3))
    try expect_equal(same.counts, [2, 0, 0])
    try expect_none(histogram(List[Float](), 2))

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
    let _third = try expect_fault(fn: discard(histogram([1.0], 0)))
    let _fourth = try expect_fault(fn: discard(correlation([1.0, 2.0], [1.0])))
