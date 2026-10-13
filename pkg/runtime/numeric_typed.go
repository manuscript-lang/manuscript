package msruntime

import (
	"fmt"
	"math"
)

// Scalar extraction and checked operations let generated numeric expressions
// stay typed between operations, while values at language boundaries stay boxed.
func IntValue(value Value) int32     { return value.(int32) }
func FloatValue(value Value) float32 { return value.(float32) }
func IntAdd(a, b int32) int32        { return checkedAdd(a, b) }
func IntSubtract(a, b int32) int32   { return checkedSub(a, b) }
func IntMultiply(a, b int32) int32   { return checkedMul(a, b) }

func IntDivide(a, b int32) int32 {
	if b == 0 || a == math.MinInt32 && b == -1 {
		intDivisionFault(a, b)
	}
	return a / b
}

func intDivisionFault(a, b int32) {
	if b == 0 {
		Panic("Int./: division by zero; right must be nonzero, found 0")
	}
	Panic(fmt.Sprintf("Int./: overflow; found left %d and right %d; result must be between %d and %d", a, b, math.MinInt32, math.MaxInt32))
}

func IntRemainder(a, b int32) int32 {
	if b == 0 {
		Panic("Int.%: remainder by zero; right must be nonzero, found 0")
	}
	return a % b
}
