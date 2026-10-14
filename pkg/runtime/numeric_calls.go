package msruntime

import "math"

// Primitive native operations retain the ordinary native callable admission and
// delivery checkpoints. They do not add a source frame or source-call depth.
func nativeScalar[T any](ctx *Execution, body func() T) T {
	CheckCancelled(ctx)
	value := body()
	if ctx != nil && ctx.Context.Err() != nil {
		panic(cancelled{})
	}
	return value
}
func NativeFloatSqrt(ctx *Execution, value float64) float64 {
	return nativeScalar(ctx, func() float64 { return math.Sqrt(value) })
}
func NativeFloatAbs(ctx *Execution, value float64) float64 {
	return nativeScalar(ctx, func() float64 { return math.Abs(value) })
}
func NativeFloatFloor(ctx *Execution, value float64) float64 {
	return nativeScalar(ctx, func() float64 { return math.Floor(value) })
}
func NativeFloatCeil(ctx *Execution, value float64) float64 {
	return nativeScalar(ctx, func() float64 { return math.Ceil(value) })
}
func NativeIntToFloat(ctx *Execution, value int64) float64 {
	return nativeScalar(ctx, func() float64 { return float64(value) })
}
