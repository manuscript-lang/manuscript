package msruntime

import (
	"fmt"
	"math"
)

// Helpers shared by the text, number, bytes and pattern modules. Names carry
// the tx prefix so they cannot collide with other modules' helpers.

const (
	txUnlimited = math.MaxInt
	// txMaxBytes is the native allocation ceiling for built strings.
	txMaxBytes = int(1 << 30)
)

// txLimit unwraps an optional budget: none is unlimited.
func txLimit(o Option[int]) int {
	if !o.Some {
		return txUnlimited
	}
	return o.Val
}

// txFaultNegative raises the fault of a non-Result operation whose supplied
// optional limit is negative.
func txFaultNegative(operation, parameter string, value int) {
	Raise(fmt.Sprintf("%s: %s must be nonnegative, found %d", operation, parameter, value))
}

// txRelative resolves a possibly negative index against length.
func txRelative(length int, index int) int {
	if index < 0 {
		return int(length) + index
	}
	return index
}

// txSliceBounds resolves negative bounds against the end and reports whether
// 0 <= start <= end <= length holds afterward.
func txSliceBounds(length int, start, end int) (int, int, bool) {
	start, end = txRelative(length, start), txRelative(length, end)
	return start, end, start >= 0 && end >= start && end <= int(length)
}

func txRangeFault(operation, parameter string, value, minimum, maximum int) {
	Raise(fmt.Sprintf("%s: %s must be between %d and %d, found %d", operation, parameter, minimum, maximum, value))
}

func txIndexFault(operation string, length int, index int) {
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
