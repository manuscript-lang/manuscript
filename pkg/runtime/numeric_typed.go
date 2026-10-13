package msruntime

import (
	"math"
	"math/bits"
)

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

func StringValue(value Value) string { return value.(string) }

// The *At variants take the operation's source site and record it only when
// the operation faults, so the fast path stores nothing.
const (
	overflowMessage = "Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt"
	divideMessage   = "division by zero; test that the divisor is not 0 before dividing"
)

func faultAt(position *string, site, message string) {
	*position = site
	Panic(message)
}

func IntAddAt(a, b int64, position *string, site string) int64 {
	r := a + b
	if (r < a) != (b < 0) {
		faultAt(position, site, overflowMessage)
	}
	return r
}

func IntSubtractAt(a, b int64, position *string, site string) int64 {
	r := a - b
	if (r > a) != (b < 0) {
		faultAt(position, site, overflowMessage)
	}
	return r
}

func IntMultiplyAt(a, b int64, position *string, site string) int64 {
	hi, lo := bits.Mul64(uint64(a), uint64(b))
	hi -= uint64((a>>63)&b) + uint64((b>>63)&a)
	if int64(hi) != int64(lo)>>63 {
		faultAt(position, site, overflowMessage)
	}
	return int64(lo)
}

func IntDivideAt(a, b int64, position *string, site string) int64 {
	if b == 0 {
		faultAt(position, site, divideMessage)
	}
	if a == math.MinInt64 && b == -1 {
		faultAt(position, site, overflowMessage)
	}
	return a / b
}

func IntRemainderAt(a, b int64, position *string, site string) int64 {
	if b == 0 {
		faultAt(position, site, divideMessage)
	}
	if b == -1 {
		return 0
	}
	return a % b
}
