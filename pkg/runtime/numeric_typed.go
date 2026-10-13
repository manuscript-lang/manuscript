package msruntime

import (
	"fmt"
	"math"
)

// Scalar extraction and checked operations let generated numeric expressions
// stay typed between operations, while values at language boundaries stay boxed.
func IntValue(value Value) int64     { return value.(int64) }
func FloatValue(value Value) float64 { return value.(float64) }
func IntAdd(a, b int64) int64        { return checkedAdd(a, b) }
func IntSubtract(a, b int64) int64   { return checkedSub(a, b) }
func IntMultiply(a, b int64) int64   { return checkedMul(a, b) }

func IntDivide(a, b int64) int64 {
	if b == 0 || a == math.MinInt64 && b == -1 {
		intDivisionFault(a, b)
	}
	return a / b
}

func intDivisionFault(a, b int64) {
	if b == 0 {
		Panic("Int./: division by zero; right must be nonzero, found 0")
	}
	Panic(fmt.Sprintf("Int./: overflow; found left %d and right %d; result must be between %d and %d", a, b, math.MinInt64, math.MaxInt64))
}

func IntRemainder(a, b int64) int64 {
	if b == 0 {
		Panic("Int.%: remainder by zero; right must be nonzero, found 0")
	}
	return a % b
}

// FloatNegate prevents Go constant arithmetic from erasing a negative zero.
func FloatNegate(value float64) float64 { return -value }
