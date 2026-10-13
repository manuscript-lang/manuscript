package msruntime

import "math"

// Scalar extraction and checked operations let generated numeric expressions
// stay typed between operations, while values at language boundaries stay boxed.
func IntValue(value Value) int64     { return value.(int64) }
func FloatValue(value Value) float64 { return value.(float64) }
func IntAdd(a, b int64) int64        { return checkedAdd(a, b) }
func IntSubtract(a, b int64) int64   { return checkedSub(a, b) }
func IntMultiply(a, b int64) int64   { return checkedMul(a, b) }

func IntDivide(a, b int64) int64 {
	if b == 0 {
		Panic("division by zero; test that the divisor is not 0 before dividing")
	}
	if a == math.MinInt64 && b == -1 {
		Panic("Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
	}
	return a / b
}

func IntRemainder(a, b int64) int64 {
	if b == 0 {
		Panic("division by zero; test that the divisor is not 0 before dividing")
	}
	return a % b
}
