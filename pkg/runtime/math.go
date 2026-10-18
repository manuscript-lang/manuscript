package msruntime

import "math"

func Math_Abs(_ *Execution, v float64) float64          { return math.Abs(v) }
func Math_Acos(_ *Execution, v float64) float64         { return math.Acos(v) }
func Math_Asin(_ *Execution, v float64) float64         { return math.Asin(v) }
func Math_Atan(_ *Execution, v float64) float64         { return math.Atan(v) }
func Math_Atan2(_ *Execution, y, x float64) float64     { return math.Atan2(y, x) }
func Math_Ceil(_ *Execution, v float64) float64         { return math.Ceil(v) }
func Math_Cos(_ *Execution, v float64) float64          { return math.Cos(v) }
func Math_Cosh(_ *Execution, v float64) float64         { return math.Cosh(v) }
func Math_E(_ *Execution) float64                       { return math.E }
func Math_Exp(_ *Execution, v float64) float64          { return math.Exp(v) }
func Math_Floor(_ *Execution, v float64) float64        { return math.Floor(v) }
func Math_Hypot(_ *Execution, a, b float64) float64     { return math.Hypot(a, b) }
func Math_Log(_ *Execution, v float64) float64          { return math.Log(v) }
func Math_Log10(_ *Execution, v float64) float64        { return math.Log10(v) }
func Math_Log2(_ *Execution, v float64) float64         { return math.Log2(v) }
func Math_Pi(_ *Execution) float64                      { return math.Pi }
func Math_Pow(_ *Execution, a, b float64) float64       { return math.Pow(a, b) }
func Math_Remainder(_ *Execution, a, b float64) float64 { return math.Mod(a, b) }
func Math_Sin(_ *Execution, v float64) float64          { return math.Sin(v) }
func Math_Sinh(_ *Execution, v float64) float64         { return math.Sinh(v) }
func Math_Sqrt(_ *Execution, v float64) float64         { return math.Sqrt(v) }
func Math_Tan(_ *Execution, v float64) float64          { return math.Tan(v) }
func Math_Tanh(_ *Execution, v float64) float64         { return math.Tanh(v) }
func Math_Truncate(_ *Execution, v float64) float64     { return math.Trunc(v) }

// Math_Round rounds halves away from the lower integer (toward positive
// infinity), preserving signed zero.
func Math_Round(_ *Execution, value float64) float64 {
	if math.IsNaN(value) || math.IsInf(value, 0) || value == 0 {
		return value
	}
	lower := math.Floor(value)
	if value-lower >= 0.5 {
		lower++
	}
	if lower == 0 {
		return math.Copysign(0, value)
	}
	return lower
}

// Math_AbsInt faults on the one value whose magnitude does not fit.
func Math_AbsInt(_ *Execution, n int) int {
	if n == math.MinInt {
		intOverflow()
	}
	if n < 0 {
		n = -n
	}
	return n
}

// Math_Max returns left unless right orders after it.
func Math_Max[T any](ctx *Execution, cmp Cmp[T], left, right T) T {
	if cmp(ctx, left, right) >= 0 {
		return left
	}
	return right
}

// Math_Min returns left unless right orders before it.
func Math_Min[T any](ctx *Execution, cmp Cmp[T], left, right T) T {
	if cmp(ctx, left, right) <= 0 {
		return left
	}
	return right
}

// Math_MaxOf returns the greatest element, keeping the first of equals.
func Math_MaxOf[T any](ctx *Execution, cmp Cmp[T], values *List[T]) Option[T] {
	return extreme(ctx, cmp, values, true)
}

// Math_MinOf returns the least element, keeping the first of equals.
func Math_MinOf[T any](ctx *Execution, cmp Cmp[T], values *List[T]) Option[T] {
	return extreme(ctx, cmp, values, false)
}

func extreme[T any](ctx *Execution, cmp Cmp[T], values *List[T], maximum bool) Option[T] {
	if len(values.Items) == 0 {
		return None[T]()
	}
	best := values.Items[0]
	for _, v := range values.Items[1:] {
		// Compare signs directly: negating the minimum Int would overflow.
		order := cmp(ctx, v, best)
		if maximum && order > 0 || !maximum && order < 0 {
			best = v
		}
	}
	return Some(best)
}

func Math_Acosh(_ *Execution, v float64) float64 { return math.Acosh(v) }
func Math_Asinh(_ *Execution, v float64) float64 { return math.Asinh(v) }
func Math_Atanh(_ *Execution, v float64) float64 { return math.Atanh(v) }
func Math_Cbrt(_ *Execution, v float64) float64  { return math.Cbrt(v) }
func Math_Expm1(_ *Execution, v float64) float64 { return math.Expm1(v) }
func Math_Log1p(_ *Execution, v float64) float64 { return math.Log1p(v) }

// Math_Sign returns -1, 0 or 1 by sign, keeping signed zero and NaN.
func Math_Sign(_ *Execution, v float64) float64 {
	switch {
	case math.IsNaN(v) || v == 0:
		return v
	case v < 0:
		return -1
	}
	return 1
}

// Math_SignInt returns -1, 0 or 1.
func Math_SignInt(_ *Execution, n int) int {
	switch {
	case n < 0:
		return -1
	case n > 0:
		return 1
	}
	return 0
}

func Math_ToFloat32(_ *Execution, v float64) float64 { return float64(float32(v)) }

const maxSafeInteger = 1<<53 - 1

func Math_IsInteger(_ *Execution, v float64) bool {
	return !math.IsInf(v, 0) && !math.IsNaN(v) && v == math.Trunc(v)
}

func Math_IsSafeInteger(ctx *Execution, v float64) bool {
	return Math_IsInteger(ctx, v) && math.Abs(v) <= maxSafeInteger
}

func Math_Infinity(_ *Execution) float64   { return math.Inf(1) }
func Math_Nan(_ *Execution) float64        { return math.NaN() }
func Math_Epsilon(_ *Execution) float64    { return 0x1p-52 }
func Math_MaxFloat(_ *Execution) float64   { return math.MaxFloat64 }
func Math_MinFloat(_ *Execution) float64   { return math.SmallestNonzeroFloat64 }
func Math_MaxInt(_ *Execution) int         { return math.MaxInt }
func Math_MinInt(_ *Execution) int         { return math.MinInt }
func Math_MaxSafeInteger(_ *Execution) int { return maxSafeInteger }
func Math_MinSafeInteger(_ *Execution) int { return -maxSafeInteger }
func Math_Ln2(_ *Execution) float64        { return math.Ln2 }
func Math_Ln10(_ *Execution) float64       { return math.Ln10 }
func Math_Log2e(_ *Execution) float64      { return math.Log2E }
func Math_Log10e(_ *Execution) float64     { return math.Log10E }
func Math_Sqrt2(_ *Execution) float64      { return math.Sqrt2 }
func Math_SqrtHalf(_ *Execution) float64   { return math.Sqrt2 / 2 }
