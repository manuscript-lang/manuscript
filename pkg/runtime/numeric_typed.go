package msruntime

import (
	"fmt"
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

func StringValue(value Value) string { return value.(string) }

// The *At variants take the operation's source site and record it only when
// the operation faults, so the fast path stores nothing. The fault itself is
// raised by the unsited operation, so both forms report identical messages.
func IntAddAt(a, b int64, position *string, site string) int64 {
	r := a + b
	if (r < a) != (b < 0) {
		*position = site
		return IntAdd(a, b)
	}
	return r
}

func IntSubtractAt(a, b int64, position *string, site string) int64 {
	r := a - b
	if (r > a) != (b < 0) {
		*position = site
		return IntSubtract(a, b)
	}
	return r
}

func IntMultiplyAt(a, b int64, position *string, site string) int64 {
	hi, lo := bits.Mul64(uint64(a), uint64(b))
	hi -= uint64((a>>63)&b) + uint64((b>>63)&a)
	if int64(hi) != int64(lo)>>63 {
		*position = site
		return IntMultiply(a, b)
	}
	return int64(lo)
}

func IntDivideAt(a, b int64, position *string, site string) int64 {
	if b == 0 || a == math.MinInt64 && b == -1 {
		*position = site
		return IntDivide(a, b)
	}
	return a / b
}

// IntNegateAt negates a, recording the site only when -a overflows.
func IntNegateAt(a int64, position *string, site string) int64 {
	if a == math.MinInt64 {
		*position = site
		Unary("-", a)
	}
	return -a
}

func IntRemainderAt(a, b int64, position *string, site string) int64 {
	if b == 0 {
		*position = site
		return IntRemainder(a, b)
	}
	if b == -1 {
		return 0
	}
	return a % b
}
