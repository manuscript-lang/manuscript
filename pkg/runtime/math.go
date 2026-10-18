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
	return extreme(ctx, cmp, values, 1)
}

// Math_MinOf returns the least element, keeping the first of equals.
func Math_MinOf[T any](ctx *Execution, cmp Cmp[T], values *List[T]) Option[T] {
	return extreme(ctx, cmp, values, -1)
}

func extreme[T any](ctx *Execution, cmp Cmp[T], values *List[T], sign int) Option[T] {
	if len(values.Items) == 0 {
		return None[T]()
	}
	best := values.Items[0]
	for _, v := range values.Items[1:] {
		if cmp(ctx, v, best)*sign > 0 {
			best = v
		}
	}
	return Some(best)
}
