import panic from "@std/core.ms"
import sqrt, frexp, ldexp from "@std/math/math.ms"
import rat_of_float, rat_of_int from "@std/math/big.ms"

/*
Summary statistics over a `List[Float]`, in binary64 arithmetic.
An operation that needs more data than it was given returns none: the mean of an empty list, the sample variance of one value.
A violated precondition (a percentile outside 0 to 100, mismatched list lengths, a bin count below 1) faults.
`statistics.mean([1.0, 2.0, 6.0])` is `3.0`.
*/

// Equal-width counts over a range of values, from `bin_counts`. (`@std/data/histogram.ms` has the recording `Histogram`.)
export type BinCounts:
    // The least value counted, which is the lower edge of the first bin.
    low: Float
    // The greatest value counted, which is the upper edge of the last bin.
    high: Float
    // The number of values in each bin; the last bin includes `high`.
    counts: List[Int]

// The least-squares line `y = slope * x + intercept` fitted by `linear_regression`.
export type Regression:
    // The change in `y` per unit of `x`.
    slope: Float
    // The value of `y` at `x = 0`.
    intercept: Float

// Returns the arithmetic mean, or none for an empty list.
// Example: `mean([1.0, 2.0, 6.0])` is `3.0`.
export fn mean(values: List[Float]) Float?:
    if values.is_empty():
        return none

    let sum = values.sum()
    let ordinary = sum / values.length().to_float()
    if sum.is_finite(): return ordinary

    // Keep the existing NaN/infinity behavior; only a finite-input overflow needs repair.
    for value in values:
        if not value.is_finite(): return ordinary

    // Exact accumulation preserves small cancellation residuals that scaling would discard.
    var total = rat_of_int(0)

    for value in values:
        if let term = rat_of_float(value):
            total = total.add(term)
        else:
            panic("statistics: finite mean input could not be converted")

    if let average = total.divide(rat_of_int(values.length())):
        if let result = average.to_float(): return result

    // The exact average of finite inputs lies between their finite extrema.
    panic("statistics: finite mean could not be represented")

// Returns the median, the middle value of the sorted list or the mean of the two middle values, or none for an empty list.
// Example: `median([5.0, 1.0, 3.0, 2.0])` is `2.5`.
export fn median(values: List[Float]) Float?:
    if values.is_empty():
        return none

    let ordered = values.sorted()
    let middle = ordered.length() / 2
    if ordered.length() % 2 == 1:
        return ordered[middle]

    let low = ordered[middle - 1]
    let high = ordered[middle]
    let sum = low + high

    // Only overflowing finite sums need halves; halving tiny values would lose precision.
    if not sum.is_finite() and low.is_finite() and high.is_finite():
        return low / 2.0 + high / 2.0

    return sum / 2.0

// Returns the most frequent value, or none for an empty list. When several values are equally frequent the least one wins.
// Example: `mode([2.0, 1.0, 2.0, 1.0, 3.0])` is `1.0`.
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

// Returns the sum of squared distances from the mean, or none for an empty list.
fn squared_deviations(values: List[Float]) Float?:
    if let center = mean(values):
        var total = 0.0
        for value in values:
            total += (value - center) * (value - center)
        return total

    return none

// Returns the population variance (divide by n), or none for an empty list.
// Example: `population_variance([1.0, 2.0, 3.0, 4.0])` is `1.25`.
export fn population_variance(values: List[Float]) Float?:
    if let total = squared_deviations(values):
        return total / values.length().to_float()

    return none

// Returns the sample variance (divide by n - 1), or none when the list has fewer than two values.
// Example: `variance([1.0, 2.0, 3.0, 4.0])` is `1.6666666666666667`.
export fn variance(values: List[Float]) Float?:
    if values.length() < 2:
        return none
    if let total = squared_deviations(values):
        return total / (values.length() - 1).to_float()

    return none

// Returns the population standard deviation, or none for an empty list.
export fn population_stdev(values: List[Float]) Float?:
    if let spread_squared = population_variance(values):
        return sqrt(spread_squared)

    return none

// Returns the sample standard deviation, or none when the list has fewer than two values.
// Example: `stdev([2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0])` is about `2.138`.
export fn stdev(values: List[Float]) Float?:
    if let spread_squared = variance(values):
        return sqrt(spread_squared)

    return none

/*
Returns the value `percent` percent of the way through the sorted list, interpolating linearly between neighbors, or none for an empty list.
`percent` runs from 0.0 (the least value) to 100.0 (the greatest); a value outside that range faults.
Example: `percentile([1.0, 2.0, 3.0, 4.0, 5.0], 25.0)` is `2.0`.
*/
export fn percentile(values: List[Float], percent: Float) Float?:
    if not (percent >= 0.0 and percent <= 100.0):
        panic("percentile: percent must be from 0 to 100")
    if values.is_empty():
        return none

    return percentile_sorted(values.sorted(), percent)

// Interpolates the percentile of an already sorted, non-empty list.
fn percentile_sorted(ordered: List[Float], percent: Float) Float:
    let position = percent / 100.0 * (ordered.length() - 1).to_float()
    let below = position.truncate_to_int().get(0)
    let fraction = position - below.to_float()
    if below + 1 >= ordered.length():
        return ordered[ordered.length() - 1]

    let low = ordered[below]
    let high = ordered[below + 1]

    // An exact position or equal neighbors return the neighbor; interpolating would turn `inf - inf` or `inf * 0` into NaN.
    if fraction == 0.0 or low == high:
        return low

    // A lone infinite neighbor stays the result of the weighted blend.
    if not low.is_finite() and high != -low:
        return low

    let span = high - low

    // Finite opposite-sign endpoints can overflow their difference, not their weighted mean.
    // Keep the original formula for finite spans to preserve small/subnormal rounding.
    if not span.is_finite() and low.is_finite() and high.is_finite():
        return low * (1.0 - fraction) + high * fraction

    return low + span * fraction

/*
Returns the `parts - 1` cut points that divide the sorted values into `parts` groups of equal probability, using the same interpolation as `percentile`.
An empty list gives an empty list; a `parts` below 2 faults.
Example: `quantiles([1.0, 2.0, 3.0, 4.0, 5.0], 4)` is `[2.0, 3.0, 4.0]`.
*/
export fn quantiles(values: List[Float], parts: Int) List[Float]:
    if parts < 2:
        panic("quantiles: parts must be at least 2")

    var cuts: List[Float] = []
    if values.is_empty():
        return cuts

    let ordered = values.sorted()
    for i in 1..parts:
        cuts.append(percentile_sorted(ordered, 100.0 * i.to_float() / parts.to_float()))
    return cuts

/*
Counts the values into `bins` equal-width bins between the least and greatest value, or returns none for an empty list.
Values equal to the greatest value fall in the last bin (so an infinite value does), and when every value is equal they all fall in the first bin. When the range is infinite, the finite values fall in the first bin. A `bins` below 1 faults.
Example: `if let bins = bin_counts([1.0, 2.0, 2.0, 3.0], 2): print(bins.counts)` prints `[1, 3]`.
*/
export fn bin_counts(values: List[Float], bins: Int) BinCounts?:
    if bins < 1:
        panic("bin_counts: bins must be at least 1")
    if values.is_empty():
        return none

    let low = values.min().get(0.0)
    let high = values.max().get(0.0)

    // A range beyond the Float maximum (or an infinite end) is measured in halves so the width stays finite where it can.
    let halved = not (high - low).is_finite()
    let origin = if halved: low / 2.0 else: low
    let width = (if halved: high / 2.0 - origin else: high - low) / bins.to_float()
    var counts: List[Int] = []
    for index in 0..bins:
        counts.append(0)

    for value in values:
        var bin = 0

        if low < high and value >= high:
            bin = bins - 1
        else if width > 0.0 and width.is_finite():
            let scaled = if halved: value / 2.0 else: value
            bin = ((scaled - origin) / width).truncate_to_int().get(0)

        if bin >= bins:
            bin = bins - 1
        counts.set(bin, counts[bin] + 1)

    return BinCounts(low: low, high: high, counts: counts)

// Returns the sum of products of deviations of two lists of equal length, with both sums of squares, or none when there are fewer than two pairs.
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

/*
Returns the Pearson correlation of paired values, from -1.0 to 1.0, or none when there are fewer than two pairs or either list has no spread.
Lists of different lengths fault.
Example: `correlation([1.0, 2.0, 3.0], [2.0, 4.0, 6.0])` is `1.0`.
*/
export fn correlation(xs: List[Float], ys: List[Float]) Float?:
    if xs.length() != ys.length():
        panic("statistics: the lists must have the same length")
    if xs.length() < 2: return none
    if let result = range_safe_correlation(xs, ys): return result

    var scale_x = 0.0
    var scale_y = 0.0

    for i in 0..xs.length():
        if not xs[i].is_finite() or not ys[i].is_finite():
            return nonfinite_correlation(xs, ys)

        scale_x = scale_x.max(xs[i].abs())
        scale_y = scale_y.max(ys[i].abs())

    if scale_x == 0.0 or scale_y == 0.0: return none

    // Power-of-two scaling avoids overflow without rounding adjacent large values together.
    let exponent_x = frexp(scale_x).exponent
    let exponent_y = frexp(scale_y).exponent
    let factor_x = ldexp(1.0, -exponent_x)
    let factor_y = ldexp(1.0, -exponent_y)
    let multiply_x = factor_x.is_finite()
    let multiply_y = factor_y.is_finite()
    let origin_x = ldexp(xs[0], -exponent_x)
    let origin_y = ldexp(ys[0], -exponent_y)
    var sum_x = CorrelationSum()
    var sum_y = CorrelationSum()

    for i in 0..xs.length():
        let scaled_x = if multiply_x: xs[i] * factor_x else: ldexp(xs[i], -exponent_x)
        let scaled_y = if multiply_y: ys[i] * factor_y else: ldexp(ys[i], -exponent_y)
        sum_x.add(scaled_x - origin_x)
        sum_y.add(scaled_y - origin_y)

    let center_x = sum_x.value() / xs.length().to_float()
    let center_y = sum_y.value() / ys.length().to_float()

    // Subtract the origin before the mean to preserve variation near a large common offset.
    var xx = CorrelationSum()
    var yy = CorrelationSum()
    var xy = CorrelationSum()

    for i in 0..xs.length():
        let scaled_x = if multiply_x: xs[i] * factor_x else: ldexp(xs[i], -exponent_x)
        let scaled_y = if multiply_y: ys[i] * factor_y else: ldexp(ys[i], -exponent_y)
        let dx = (scaled_x - origin_x) - center_x
        let dy = (scaled_y - origin_y) - center_y
        xx.add(dx * dx)
        yy.add(dy * dy)
        xy.add(dx * dy)

    let square_x = xx.value()
    let square_y = yy.value()
    if square_x == 0.0 or square_y == 0.0: return none

    // Rounding may exceed the mathematical correlation bound by a final ulp.
    return (xy.value() / sqrt(square_x * square_y)).max(-1.0).min(1.0)

// Neumaier accumulation retains small contributions on the scaled fallback path.
type CorrelationSum:
    total: Float = 0.0
    correction: Float = 0.0

impl CorrelationSum:
    var fn add(value: Float) Unit:
        let next = self.total + value

        if self.total.abs() >= value.abs():
            self.correction += (self.total - next) + value
        else:
            self.correction += (value - next) + self.total

        self.total = next

    fn value() Float:
        return self.total + self.correction

// Origin-shifted means and compensated moments avoid scaling when intermediates stay normal.
// A failed range check requests the scaled/compensated path; it does not mean zero spread.
fn range_safe_correlation(xs: List[Float], ys: List[Float]) Float?:
    let origin_x = xs[0]
    let origin_y = ys[0]
    var sum_x = 0.0
    var sum_y = 0.0

    for i in 0..xs.length():
        sum_x += xs[i] - origin_x
        sum_y += ys[i] - origin_y

    let mean_x = sum_x / xs.length().to_float()
    let mean_y = sum_y / ys.length().to_float()
    if not mean_x.is_finite() or not mean_y.is_finite(): return none

    var xx = 0.0
    var xx_error = 0.0
    var yy = 0.0
    var yy_error = 0.0
    var xy = 0.0
    var xy_error = 0.0

    for i in 0..xs.length():
        let dx = (xs[i] - origin_x) - mean_x
        let dy = (ys[i] - origin_y) - mean_y
        let adjusted_xx = dx * dx - xx_error
        let next_xx = xx + adjusted_xx
        xx_error = (next_xx - xx) - adjusted_xx
        xx = next_xx

        let adjusted_yy = dy * dy - yy_error
        let next_yy = yy + adjusted_yy
        yy_error = (next_yy - yy) - adjusted_yy
        yy = next_yy

        let adjusted_xy = dx * dy - xy_error
        let next_xy = xy + adjusted_xy
        xy_error = (next_xy - xy) - adjusted_xy
        xy = next_xy

    let min_normal = 2.2250738585072014e-308
    let product = xx * yy
    if not (xx >= min_normal and yy >= min_normal and product >= min_normal): return none
    if not product.is_finite() or not xy.is_finite(): return none

    return (xy / sqrt(product)).max(-1.0).min(1.0)

// Raw sums intentionally preserve the old nonfinite arithmetic even when mean repairs finite overflow.
fn nonfinite_correlation(xs: List[Float], ys: List[Float]) Float?:
    let mean_x = xs.sum() / xs.length().to_float()
    let mean_y = ys.sum() / ys.length().to_float()
    var xx = 0.0
    var yy = 0.0
    var xy = 0.0

    for i in 0..xs.length():
        let dx = xs[i] - mean_x
        let dy = ys[i] - mean_y
        xx += dx * dx
        yy += dy * dy
        xy += dx * dy

    if xx == 0.0 or yy == 0.0: return none

    return xy / sqrt(xx * yy)

/*
Returns the least-squares line through paired values, or none when there are fewer than two pairs or the `xs` are all equal.
Lists of different lengths fault.
Example: `linear_regression([1.0, 2.0, 3.0], [3.0, 5.0, 7.0])` has slope `2.0` and intercept `1.0`.
*/
export fn linear_regression(xs: List[Float], ys: List[Float]) Regression?:
    if let s = spread(xs, ys):
        if s.xx == 0.0:
            return none

        let slope = s.xy / s.xx
        return Regression(slope: slope, intercept: s.mean_y - slope * s.mean_x)

    return none
