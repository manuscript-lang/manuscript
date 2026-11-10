import (
    panic from "@std/core.ms",
    sqrt, frexp, ldexp from "@std/math/math.ms",
    BigRat, rat_of_float, rat_of_int from "@std/math/big.ms",
)

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
    if values.is_empty(): return none

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
    if values.is_empty(): return none

    let ordered = values.sorted()
    let middle = ordered.length() / 2
    if ordered.length() % 2 == 1: return ordered[middle]

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
    if values.is_empty(): return none

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

// The sum of squared deviations from the mean as `squares * 2^(2 * exponent)`, so a representable variance never overflows or underflows on the way.
type Moments:
    squares: Float
    exponent: Int

// Returns the centered second moment, or none for an empty list or any nonfinite value (which keeps plain Float rules).
// Values are scaled by a power of two to at most 1 in magnitude, shifted by the first value, then summed with compensation, so a large common offset keeps its variation.
fn centered_moments(values: List[Float]) Moments?:
    if values.is_empty(): return none

    var scale = 0.0

    for value in values:
        if not value.is_finite(): return none

        scale = scale.max(value.abs())

    if scale == 0.0: return Moments(squares: 0.0, exponent: 0)

    let exponent = frexp(scale).exponent
    let origin = ldexp(values[0], -exponent)
    var total = DeviationSum()
    for value in values:
        total.add(ldexp(value, -exponent) - origin)

    let center = total.value() / values.length().to_float()
    var squares = DeviationSum()

    for value in values:
        let delta = (ldexp(value, -exponent) - origin) - center
        squares.add(delta * delta)

    return Moments(squares: squares.value(), exponent: exponent)

// Returns the sum of squared distances from the mean divided by `divisor`, or none for an empty list.
fn spread_variance(values: List[Float], divisor: Int) Float?:
    if let moments = centered_moments(values):
        let result = moments.squares / divisor.to_float()
        return ldexp(ldexp(result, moments.exponent), moments.exponent)

    // Nonfinite input follows Float rules around the plain mean.
    if let center = mean(values):
        var total = 0.0
        for value in values:
            total += (value - center) * (value - center)
        return total / divisor.to_float()

    return none

// Returns the population variance (divide by n), or none for an empty list.
// Example: `population_variance([1.0, 2.0, 3.0, 4.0])` is `1.25`.
export fn population_variance(values: List[Float]) Float?:
    return spread_variance(values, values.length())

// Returns the sample variance (divide by n - 1), or none when the list has fewer than two values.
// Example: `variance([1.0, 2.0, 3.0, 4.0])` is `1.6666666666666667`.
export fn variance(values: List[Float]) Float?:
    if values.length() < 2: return none

    return spread_variance(values, values.length() - 1)

// Returns the population standard deviation, or none for an empty list.
export fn population_stdev(values: List[Float]) Float?:
    if let spread_squared = population_variance(values):
        return deviation_from_variance(values, spread_squared, 0)

    return none

// Returns the sample standard deviation, or none when the list has fewer than two values.
// Example: `stdev([2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0])` is about `2.138`.
export fn stdev(values: List[Float]) Float?:
    if let spread_squared = variance(values):
        return deviation_from_variance(values, spread_squared, 1)

    return none

// Preserve ordinary rounding; avoid requiring the squared result to fit for extreme finite inputs.
fn deviation_from_variance(
    values: List[Float],
    spread_squared: Float,
    correction: Int
) Float:
    let ordinary = sqrt(spread_squared)
    if spread_squared.is_finite() and spread_squared >= 2.2250738585072014e-308:
        return ordinary

    var scale = 0.0

    for value in values:
        if not value.is_finite(): return ordinary

        scale = scale.max(value.abs())

    if scale == 0.0: return 0.0

    let exponent = frexp(scale).exponent
    let origin = ldexp(values[0], -exponent)
    var total = DeviationSum()
    for value in values:
        total.add(ldexp(value, -exponent) - origin)

    let center = total.value() / values.length().to_float()
    var squares = DeviationSum()

    for value in values:
        let delta = (ldexp(value, -exponent) - origin) - center
        squares.add(delta * delta)

    let normalized = sqrt(squares.value() / (values.length() - correction).to_float())
    let result = ldexp(normalized, exponent)

    // Population deviation cannot exceed the greatest input magnitude.
    if correction == 0: return result.min(scale)
    if normalized == 0.0: return 0.0

    // Sample deviation is at most sqrt(2) times scale. Only these extreme inputs
    // can cross Float's overflow midpoint; decide that boundary exactly.
    if scale > 1.7976931348623157e308 / 2.0:
        if sample_deviation_overflows(values): return 1.0 / 0.0

        return result.min(1.7976931348623157e308)

    return result

fn sample_deviation_overflows(values: List[Float]) Bool:
    var total = rat_of_int(0)
    var squares = rat_of_int(0)

    for value in values:
        if let term = rat_of_float(value):
            total = total.add(term)
            squares = squares.add(term.multiply(term))
        else:
            panic("statistics: finite deviation input could not be converted")

    let count = rat_of_int(values.length())
    let numerator = squares.multiply(count).subtract(total.multiply(total))

    // Round-to-nearest overflows at MAX + half its upward ulp, including the tie.
    if let maximum = rat_of_float(1.7976931348623157e308):
        if let half_ulp = rat_of_float(ldexp(1.0, 970)):
            let midpoint = maximum.add(half_ulp)
            let bound = midpoint.multiply(
                midpoint
            ).multiply(count).multiply(rat_of_int(values.length() - 1))
            return numerator.compare(bound) >= 0

    panic("statistics: finite deviation overflow boundary could not be converted")

// Compensated summation on the bounded fallback coordinates.
type DeviationSum:
    total: Float = 0.0
    correction: Float = 0.0

impl DeviationSum:
    var fn add(value: Float) Unit:
        let next = self.total + value

        if self.total.abs() >= value.abs():
            self.correction += (self.total - next) + value
        else:
            self.correction += (value - next) + self.total

        self.total = next

    fn value() Float:
        return self.total + self.correction

/*
Returns the value `percent` percent of the way through the sorted list, interpolating linearly between neighbors, or none for an empty list.
`percent` runs from 0.0 (the least value) to 100.0 (the greatest); a value outside that range faults.
Example: `percentile([1.0, 2.0, 3.0, 4.0, 5.0], 25.0)` is `2.0`.
*/
export fn percentile(values: List[Float], percent: Float) Float?:
    if not (percent >= 0.0 and percent <= 100.0):
        panic("percentile: percent must be from 0 to 100")
    if values.is_empty(): return none

    return percentile_sorted(values.sorted(), percent)

// Interpolates the percentile of an already sorted, non-empty list.
// The rank is `percent * (n - 1) / 100`, so an integer percent at an exact rank is not displaced by an earlier rounding of `percent / 100`.
fn percentile_sorted(ordered: List[Float], percent: Float) Float:
    let position = percent * (ordered.length() - 1).to_float() / 100.0
    let below = position.truncate_to_int().get(0)
    return interpolate_sorted(ordered, below, position - below.to_float())

// Blends the neighbours at `below` and `below + 1` by `fraction` in 0 through 1.
fn interpolate_sorted(ordered: List[Float], below: Int, fraction: Float) Float:
    if below + 1 >= ordered.length(): return ordered[ordered.length() - 1]

    let low = ordered[below]
    let high = ordered[below + 1]

    // An exact position or equal neighbors return the neighbor; interpolating would turn `inf - inf` or `inf * 0` into NaN.
    if fraction == 0.0 or low == high: return low

    // A lone infinite neighbor stays the result of the weighted blend.
    if not low.is_finite() and high != -low: return low

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
    if values.is_empty(): return cuts

    let ordered = values.sorted()

    // The rank `i * (n - 1) / parts` is split in integers, so cut points at exact ranks return the element.
    let span = ordered.length() - 1

    for i in 1..parts:
        let numerator = i * span
        cuts.append(
            interpolate_sorted(
                ordered, numerator / parts,
                (numerator % parts).to_float() / parts.to_float()
            )
        )

    return cuts

/*
Counts the values into `bins` equal-width bins between the least and greatest value, or returns none for an empty list.
Values equal to the greatest value fall in the last bin (so an infinite value does), and when every value is equal they all fall in the first bin. When the range is infinite, the finite values fall in the first bin. A `bins` below 1 faults.
Example: `if let bins = bin_counts([1.0, 2.0, 2.0, 3.0], 2): print(bins.counts)` prints `[1, 3]`.
*/
export fn bin_counts(values: List[Float], bins: Int) BinCounts?:
    if bins < 1:
        panic("bin_counts: bins must be at least 1")
    if values.is_empty(): return none

    let low = values.min().get(0.0)
    let high = values.max().get(0.0)

    // A range beyond the Float maximum (or an infinite end) is measured in halves so the width stays finite where it can.
    let halved = not (high - low).is_finite()
    let origin = if halved: low / 2.0 else: low
    let width = (if halved: high / 2.0 - origin else: high - low) / bins.to_float()

    if (
        low < high
        and low.is_finite()
        and high.is_finite()
        and width < 2.2250738585072014e-308
    ):
        var finite = true
        for value in values:
            if not value.is_finite(): finite = false
        if finite:
            return BinCounts(
                low: low, high: high, counts: exact_bin_counts(values, low, high, bins)
            )

    var counts = [0].repeated(bins)

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

// A subnormal width loses bin boundaries. Classify exact binary64 inputs instead.
fn exact_bin_counts(values: List[Float], low: Float, high: Float, bins: Int) List[Int]:
    let origin = finite_bin_rat(low)
    let span = finite_bin_rat(high).subtract(origin)
    var counts = [0].repeated(bins)

    if let multiplier = rat_of_int(bins).divide(span):
        for value in values:
            var bin = 0

            if value >= high:
                bin = bins - 1
            else:
                let position = (
                    finite_bin_rat(value)
                    .subtract(origin)
                    .multiply(multiplier)
                )

                if let index = position.floor().to_int():
                    bin = index
                else:
                    panic("statistics: finite bin index could not be represented")

            counts.set(bin, counts[bin] + 1)

        return counts

    panic("statistics: finite bin range could not be divided")

fn finite_bin_rat(value: Float) BigRat:
    if let result = rat_of_float(value): return result

    panic("statistics: finite bin input could not be converted")

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
    if xs.length() < 2: return none

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

    // Correlation is unchanged by scaling each list, so power-of-two scaling keeps every square and product in range.
    if let s = spread(unit_scaled(xs), unit_scaled(ys)):
        if s.xx == 0.0 or s.yy == 0.0: return none

        return s.xy / (sqrt(s.xx) * sqrt(s.yy))

    return none

// Returns the values multiplied by the power of two that brings the greatest magnitude into [0.5, 1); lists with a nonfinite value or only zeros are unchanged.
fn unit_scaled(values: List[Float]) List[Float]:
    var scale = 0.0

    for value in values:
        if not value.is_finite(): return values.clone()

        scale = scale.max(value.abs())

    if scale == 0.0: return values.clone()

    let exponent = frexp(scale).exponent
    var scaled = values.map(fn value: ldexp(value, -exponent))
    return scaled

/*
Returns the least-squares line through paired values, or none when there are fewer than two pairs or the `xs` are all equal.
Lists of different lengths fault.
Example: `linear_regression([1.0, 2.0, 3.0], [3.0, 5.0, 7.0])` has slope `2.0` and intercept `1.0`.
*/
export fn linear_regression(xs: List[Float], ys: List[Float]) Regression?:
    if let s = spread(xs, ys):
        if (
            well_conditioned(s.mean_x, s.xx, xs.length(), false)
            and well_conditioned(s.mean_y, s.yy, ys.length(), true)
        ):
            let slope = s.xy / s.xx
            return Regression(slope: slope, intercept: s.mean_y - slope * s.mean_x)

        if let x_exponent = unit_exponent(xs):
            if let y_exponent = unit_exponent(ys):
                return finite_regression(xs, ys, x_exponent, y_exponent)

        // Nonfinite input follows Float rules around the plain means.
        if s.xx == 0.0: return none

        let slope = s.xy / s.xx
        return Regression(slope: slope, intercept: s.mean_y - slope * s.mean_x)

    return none

/*
Whether the plain sum of squared deviations `squares` around `mean` is trustworthy: it neither overflowed nor lost precision to
underflow, and the spread is not lost against a large common offset (mean square deviation above 2^-20 of the squared mean).
A flat list (`allow_flat`) has no spread to lose. Anything else, including nonfinite input, takes the scaled path or plain Float rules.
*/
fn well_conditioned(mean: Float, squares: Float, count: Int, allow_flat: Bool) Bool:
    if squares == 0.0: return allow_flat and mean.is_finite()
    if not (squares >= 1e-250 and squares <= 1e250): return false

    return squares > mean * mean * count.to_float() * 9.5367431640625e-7

// The exponent that brings the greatest magnitude into [0.5, 1), or none when a value is not finite; zeros give 0.
fn unit_exponent(values: List[Float]) Int?:
    var scale = 0.0

    for value in values:
        if not value.is_finite(): return none

        scale = scale.max(value.abs())

    if scale == 0.0: return 0

    return frexp(scale).exponent

// Values scaled by a power of two, as offsets from the first one and then from their center.
type Centered:
    origin: Float
    center: Float
    deviations: List[Float]

fn centered(values: List[Float], exponent: Int) Centered:
    let origin = ldexp(values[0], -exponent)
    var total = DeviationSum()
    for value in values:
        total.add(ldexp(value, -exponent) - origin)

    let center = total.value() / values.length().to_float()
    var deviations: List[Float] = []
    for value in values:
        deviations.append((ldexp(value, -exponent) - origin) - center)
    return Centered(origin: origin, center: center, deviations: deviations)

/*
Each list is scaled by its own power of two and measured from its first value, so squares and products stay in range and a large common
offset keeps its variation; the deviations are then scaled again, summed with compensation, and the units are restored at the end.
*/
fn finite_regression(
    xs: List[Float],
    ys: List[Float],
    x_exponent: Int,
    y_exponent: Int
) Regression?:
    let x = centered(xs, x_exponent)
    let y = centered(ys, y_exponent)
    let x_unit = unit_exponent(x.deviations).get(0)
    let y_unit = unit_exponent(y.deviations).get(0)
    var xx = DeviationSum()
    var xy = DeviationSum()

    for i in 0..xs.length():
        let a = ldexp(x.deviations[i], -x_unit)
        let b = ldexp(y.deviations[i], -y_unit)
        xx.add(a * a)
        xy.add(a * b)

    if xx.value() == 0.0: return none

    let ratio = xy.value() / xx.value()
    let scaled_slope = ldexp(ratio, y_unit - x_unit)
    let scaled_intercept = (
        (y.origin - scaled_slope * x.origin)
        + (y.center - scaled_slope * x.center)
    )
    return Regression(
        slope: ldexp(ratio, y_unit - x_unit + y_exponent - x_exponent),
        intercept: ldexp(scaled_intercept, y_exponent)
    )
