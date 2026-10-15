package rt

import (
	"fmt"
	"math"
)

// Helpers shared by the text, number, bytes and pattern modules. Names carry
// the tx prefix so they cannot collide with other modules' helpers.

const (
	txUnlimited = int64(math.MaxInt64)
	// txMaxBytes is the native allocation ceiling for built strings.
	txMaxBytes = int64(1 << 30)
)

// txLimit unwraps an optional budget: none is unlimited.
func txLimit(o Option[int64]) int64 {
	if !o.Some {
		return txUnlimited
	}
	return o.Val
}

// txFaultNegative raises the fault of a non-Result operation whose supplied
// optional limit is negative.
func txFaultNegative(operation, parameter string, value int64) {
	Raise(fmt.Sprintf("%s: %s must be nonnegative, found %d", operation, parameter, value))
}

// txRelative resolves a possibly negative index against length.
func txRelative(length int, index int64) int64 {
	if index < 0 {
		return int64(length) + index
	}
	return index
}

// txSliceBounds resolves negative bounds against the end and reports whether
// 0 <= start <= end <= length holds afterward.
func txSliceBounds(length int, start, end int64) (int64, int64, bool) {
	start, end = txRelative(length, start), txRelative(length, end)
	return start, end, start >= 0 && end >= start && end <= int64(length)
}

func txRangeFault(operation, parameter string, value, minimum, maximum int64) {
	Raise(fmt.Sprintf("%s: %s must be between %d and %d, found %d", operation, parameter, minimum, maximum, value))
}

func txIndexFault(operation string, length int, index int64) {
	if length == 0 {
		Raise(fmt.Sprintf("%s: index has no valid value for an empty collection, found %d", operation, index))
	}
	Raise(fmt.Sprintf("%s: index must be between %d and %d (negative indexes count from the end), found %d", operation, -length, length-1, index))
}

const (
	txInvalidInput  = "invalid input"
	txInvalidData   = "invalid data"
	txLimitExceeded = "limit exceeded"
	txOutOfRange    = "value out of range"
)
