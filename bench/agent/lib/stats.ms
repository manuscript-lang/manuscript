// Small-sample statistics for the report: confidence intervals for pass rates and
// means.
import sqrt from "@std/math/math.ms"

// z for a two-sided 95% interval.
Z := 1.96

// A point estimate with the bounds of its 95% interval.
export type Interval:
	mid Float
	low Float
	high Float

// The Wilson score interval for `ok` successes in `n` trials, as (low, high) fractions.
// It stays inside [0, 1] and is honest for the small n a benchmark cell has.
export fn wilson(ok Int, n Int) Interval:
	if n == 0: return Interval(0.0, 0.0, 1.0)

	p := ok.to_float() / n.to_float()
	nf := n.to_float()
	z2 := Z * Z
	centre := (p + z2 / (2.0 * nf)) / (1.0 + z2 / nf)
	half := Z * sqrt(p * (1.0 - p) / nf + z2 / (4.0 * nf * nf)) / (1.0 + z2 / nf)
	return Interval(p, centre - half, centre + half)

// The sample mean with its 95% interval (normal approximation; a zero-width interval
// when there are fewer than two values).
export fn mean_ci(values List[Float]) Interval:
	n := values.length()
	if n == 0: return Interval(0.0, 0.0, 0.0)

	nf := n.to_float()
	mean := values.sum() / nf
	if n < 2: return Interval(mean, mean, mean)

	var squares = 0.0
	for v in values: squares += (v - mean) * (v - mean)

	half := Z * sqrt(squares / (nf - 1.0)) / sqrt(nf)
	return Interval(mean, mean - half, mean + half)
