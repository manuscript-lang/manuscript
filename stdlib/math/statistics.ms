import panic from "@std/core.ms"
import sqrt from "@std/math/math.ms"

# Summary statistics over a `List[Float]`, in binary64 arithmetic.
# An operation that needs more data than it was given returns none: the mean of an empty list, the sample variance of one value.
# A violated precondition (a percentile outside 0 to 100, mismatched list lengths, a bin count below 1) faults.
# `statistics.mean([1.0, 2.0, 6.0])` is `3.0`.

# Equal-width counts over a range of values, from `histogram`.
export type Histogram:
    # The least value counted, which is the lower edge of the first bin.
    low: Float
    # The greatest value counted, which is the upper edge of the last bin.
    high: Float
    # The number of values in each bin; the last bin includes `high`.
    counts: List[Int]

# The least-squares line `y = slope * x + intercept` fitted by `linear_regression`.
export type Regression:
    # The change in `y` per unit of `x`.
    slope: Float
    # The value of `y` at `x = 0`.
    intercept: Float

# Returns the arithmetic mean, or none for an empty list.
# Example: `mean([1.0, 2.0, 6.0])` is `3.0`.
export fn mean(values: List[Float]) Float?:
    if values.is_empty():
        return none

    return values.sum() / values.length().to_float()

# Returns the median, the middle value of the sorted list or the mean of the two middle values, or none for an empty list.
# Example: `median([5.0, 1.0, 3.0, 2.0])` is `2.5`.
export fn median(values: List[Float]) Float?:
    if values.is_empty():
        return none

    let ordered = values.sorted()
    let middle = ordered.length() / 2
    if ordered.length() % 2 == 1:
        return ordered[middle]

    return (ordered[middle - 1] + ordered[middle]) / 2.0

# Returns the most frequent value, or none for an empty list. When several values are equally frequent the least one wins.
# Example: `mode([2.0, 1.0, 2.0, 1.0, 3.0])` is `1.0`.
export fn mode(values: List[Float]) Float?:
    if values.is_empty():
        return none

    let ordered = values.sorted()
    var best = ordered[0]
    var best_count = 0
    var run_start = 0

    for i in 1..ordered.length() + 1:
        if i == ordered.length() or ordered[i] != ordered[run_start]:
            if i - run_start > best_count:
                best = ordered[run_start]
                best_count = i - run_start

            run_start = i

    return best

# Returns the sum of squared distances from the mean, or none for an empty list.
fn squared_deviations(values: List[Float]) Float?:
    if let center = mean(values):
        var total = 0.0
        for value in values:
            total += (value - center) * (value - center)
        return total

    return none

# Returns the population variance (divide by n), or none for an empty list.
# Example: `population_variance([1.0, 2.0, 3.0, 4.0])` is `1.25`.
export fn population_variance(values: List[Float]) Float?:
    if let total = squared_deviations(values):
        return total / values.length().to_float()

    return none

# Returns the sample variance (divide by n - 1), or none when the list has fewer than two values.
# Example: `variance([1.0, 2.0, 3.0, 4.0])` is `1.6666666666666667`.
export fn variance(values: List[Float]) Float?:
    if values.length() < 2:
        return none
    if let total = squared_deviations(values):
        return total / (values.length() - 1).to_float()

    return none

# Returns the population standard deviation, or none for an empty list.
export fn population_stdev(values: List[Float]) Float?:
    if let spread_squared = population_variance(values):
        return sqrt(spread_squared)

    return none

# Returns the sample standard deviation, or none when the list has fewer than two values.
# Example: `stdev([2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0])` is about `2.138`.
export fn stdev(values: List[Float]) Float?:
    if let spread_squared = variance(values):
        return sqrt(spread_squared)

    return none

# Returns the value `percent` percent of the way through the sorted list, interpolating linearly between neighbors, or none for an empty list.
# `percent` runs from 0.0 (the least value) to 100.0 (the greatest); a value outside that range faults.
# Example: `percentile([1.0, 2.0, 3.0, 4.0, 5.0], 25.0)` is `2.0`.
export fn percentile(values: List[Float], percent: Float) Float?:
    if not (percent >= 0.0 and percent <= 100.0):
        panic("percentile: percent must be from 0 to 100")
    if values.is_empty():
        return none

    let ordered = values.sorted()
    let position = percent / 100.0 * (ordered.length() - 1).to_float()
    let below = position.truncate_to_int().get(0)
    let fraction = position - below.to_float()
    if below + 1 >= ordered.length():
        return ordered[ordered.length() - 1]

    return ordered[below] + (ordered[below + 1] - ordered[below]) * fraction

# Returns the `parts - 1` cut points that divide the sorted values into `parts` groups of equal probability, using the same interpolation as `percentile`.
# An empty list gives an empty list; a `parts` below 2 faults.
# Example: `quantiles([1.0, 2.0, 3.0, 4.0, 5.0], 4)` is `[2.0, 3.0, 4.0]`.
export fn quantiles(values: List[Float], parts: Int) List[Float]:
    if parts < 2:
        panic("quantiles: parts must be at least 2")

    var cuts: List[Float] = []
    if values.is_empty():
        return cuts

    for i in 1..parts:
        cuts.append(
            percentile(values, 100.0 * i.to_float() / parts.to_float()).get(
                0.0
            )
        )
    return cuts

# Counts the values into `bins` equal-width bins between the least and greatest value, or returns none for an empty list.
# Values equal to the greatest value fall in the last bin; when every value is equal they all fall in the first bin. A `bins` below 1 faults.
# Example: `histogram([1.0, 2.0, 2.0, 3.0], 2).counts` is `[1, 3]`.
export fn histogram(values: List[Float], bins: Int) Histogram?:
    if bins < 1:
        panic("histogram: bins must be at least 1")
    if values.is_empty():
        return none

    let low = values.min().get(0.0)
    let high = values.max().get(0.0)
    let width = (high - low) / bins.to_float()
    var counts: List[Int] = []
    for index in 0..bins:
        counts.append(0)

    for value in values:
        var bin = 0
        if width > 0.0:
            bin = ((value - low) / width).truncate_to_int().get(0)
        if bin >= bins:
            bin = bins - 1
        counts.set(bin, counts[bin] + 1)

    return Histogram(low: low, high: high, counts: counts)

# Returns the sum of products of deviations of two lists of equal length, with both sums of squares, or none when there are fewer than two pairs.
type Spread:
    xy: Float
    xx: Float
    yy: Float
    mean_x: Float
    mean_y: Float

fn spread(xs: List[Float], ys: List[Float]) Spread?:
    if xs.length() != ys.length():
        panic("statistics: the lists must have the same length")
    if xs.length() < 2:
        return none

    let mean_x = mean(xs).get(0.0)
    let mean_y = mean(ys).get(0.0)
    var xy = 0.0
    var xx = 0.0
    var yy = 0.0

    for i in 0..xs.length():
        let dx = xs[i] - mean_x
        let dy = ys[i] - mean_y
        xy += dx * dy
        xx += dx * dx
        yy += dy * dy

    return Spread(xy: xy, xx: xx, yy: yy, mean_x: mean_x, mean_y: mean_y)

# Returns the Pearson correlation of paired values, from -1.0 to 1.0, or none when there are fewer than two pairs or either list has no spread.
# Lists of different lengths fault.
# Example: `correlation([1.0, 2.0, 3.0], [2.0, 4.0, 6.0])` is `1.0`.
export fn correlation(xs: List[Float], ys: List[Float]) Float?:
    if let s = spread(xs, ys):
        if s.xx == 0.0 or s.yy == 0.0:
            return none

        return s.xy / sqrt(s.xx * s.yy)

    return none

# Returns the least-squares line through paired values, or none when there are fewer than two pairs or the `xs` are all equal.
# Lists of different lengths fault.
# Example: `linear_regression([1.0, 2.0, 3.0], [3.0, 5.0, 7.0])` has slope `2.0` and intercept `1.0`.
export fn linear_regression(xs: List[Float], ys: List[Float]) Regression?:
    if let s = spread(xs, ys):
        if s.xx == 0.0:
            return none

        let slope = s.xy / s.xx
        return Regression(slope: slope, intercept: s.mean_y - slope * s.mean_x)

    return none
