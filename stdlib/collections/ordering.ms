import panic from "@std/core.ms"

// Source-written ordering methods for the built-in scalars and String: `a.min(b)`,
// `a.max(b)` and `a.clamp(low, high)`, defined once over `compare` so every numeric
// width and String agree. The methods apply to every program.
fn lesser[T: Comparable](left: T, right: T) T:
	if right.compare(left) < 0: return right
	return left

fn greater[T: Comparable](left: T, right: T) T:
	if right.compare(left) > 0: return right
	return left

fn clamped[T: Comparable](value: T, low: T, high: T) T:
	if low.compare(high) > 0:
		panic("clamp: low must not be greater than high")
	if value.compare(low) < 0: return low
	if value.compare(high) > 0: return high

	return value

interface Ordered:
	fn min(other: Self) Self
	fn max(other: Self) Self
	fn clamp(low: Self, high: Self) Self

// Returns the lesser of this value and `other`, or this value when they compare
// equal. Example: `(3).min(2)` is `2`.
fn Int.min(other: Int) Int:
	return lesser(self, other)

// Returns the greater of this value and `other`, or this value when they compare
// equal. Example: `(3).max(2)` is `3`.
fn Int.max(other: Int) Int:
	return greater(self, other)

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault. Example: `(15).clamp(0, 10)` is `10`.
fn Int.clamp(low: Int, high: Int) Int:
	return clamped(self, low, high)

// Returns the lesser of this value and `other`, or this value when they compare
// equal. Example: `(3).min(2)` is `2`.
fn Int8.min(other: Int8) Int8:
	return lesser(self, other)

// Returns the greater of this value and `other`, or this value when they compare
// equal. Example: `(3).max(2)` is `3`.
fn Int8.max(other: Int8) Int8:
	return greater(self, other)

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault. Example: `(15).clamp(0, 10)` is `10`.
fn Int8.clamp(low: Int8, high: Int8) Int8:
	return clamped(self, low, high)

// Returns the lesser of this value and `other`, or this value when they compare
// equal. Example: `(3).min(2)` is `2`.
fn Int16.min(other: Int16) Int16:
	return lesser(self, other)

// Returns the greater of this value and `other`, or this value when they compare
// equal. Example: `(3).max(2)` is `3`.
fn Int16.max(other: Int16) Int16:
	return greater(self, other)

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault. Example: `(15).clamp(0, 10)` is `10`.
fn Int16.clamp(low: Int16, high: Int16) Int16:
	return clamped(self, low, high)

// Returns the lesser of this value and `other`, or this value when they compare
// equal. Example: `(3).min(2)` is `2`.
fn Int32.min(other: Int32) Int32:
	return lesser(self, other)

// Returns the greater of this value and `other`, or this value when they compare
// equal. Example: `(3).max(2)` is `3`.
fn Int32.max(other: Int32) Int32:
	return greater(self, other)

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault. Example: `(15).clamp(0, 10)` is `10`.
fn Int32.clamp(low: Int32, high: Int32) Int32:
	return clamped(self, low, high)

// Returns the lesser of this value and `other`, or this value when they compare
// equal. Example: `(3).min(2)` is `2`.
fn UInt8.min(other: UInt8) UInt8:
	return lesser(self, other)

// Returns the greater of this value and `other`, or this value when they compare
// equal. Example: `(3).max(2)` is `3`.
fn UInt8.max(other: UInt8) UInt8:
	return greater(self, other)

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault. Example: `(15).clamp(0, 10)` is `10`.
fn UInt8.clamp(low: UInt8, high: UInt8) UInt8:
	return clamped(self, low, high)

// Returns the lesser of this value and `other`, or this value when they compare
// equal. Example: `(3).min(2)` is `2`.
fn UInt16.min(other: UInt16) UInt16:
	return lesser(self, other)

// Returns the greater of this value and `other`, or this value when they compare
// equal. Example: `(3).max(2)` is `3`.
fn UInt16.max(other: UInt16) UInt16:
	return greater(self, other)

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault. Example: `(15).clamp(0, 10)` is `10`.
fn UInt16.clamp(low: UInt16, high: UInt16) UInt16:
	return clamped(self, low, high)

// Returns the lesser of this value and `other`, or this value when they compare
// equal. Example: `(3).min(2)` is `2`.
fn UInt32.min(other: UInt32) UInt32:
	return lesser(self, other)

// Returns the greater of this value and `other`, or this value when they compare
// equal. Example: `(3).max(2)` is `3`.
fn UInt32.max(other: UInt32) UInt32:
	return greater(self, other)

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault. Example: `(15).clamp(0, 10)` is `10`.
fn UInt32.clamp(low: UInt32, high: UInt32) UInt32:
	return clamped(self, low, high)

// Returns the lesser of this value and `other`, or this value when they compare
// equal. Example: `(3).min(2)` is `2`.
fn UInt64.min(other: UInt64) UInt64:
	return lesser(self, other)

// Returns the greater of this value and `other`, or this value when they compare
// equal. Example: `(3).max(2)` is `3`.
fn UInt64.max(other: UInt64) UInt64:
	return greater(self, other)

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault. Example: `(15).clamp(0, 10)` is `10`.
fn UInt64.clamp(low: UInt64, high: UInt64) UInt64:
	return clamped(self, low, high)

// Returns the lesser of this value and `other`, or this value when they compare
// equal. Example: `(3).min(2)` is `2`.
fn Float.min(other: Float) Float:
	return lesser(self, other)

// Returns the greater of this value and `other`, or this value when they compare
// equal. Example: `(3).max(2)` is `3`.
fn Float.max(other: Float) Float:
	return greater(self, other)

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault. Example: `(15).clamp(0, 10)` is `10`.
fn Float.clamp(low: Float, high: Float) Float:
	return clamped(self, low, high)

// Returns the lesser of this value and `other`, or this value when they compare
// equal. Example: `(3).min(2)` is `2`.
fn Float32.min(other: Float32) Float32:
	return lesser(self, other)

// Returns the greater of this value and `other`, or this value when they compare
// equal. Example: `(3).max(2)` is `3`.
fn Float32.max(other: Float32) Float32:
	return greater(self, other)

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault. Example: `(15).clamp(0, 10)` is `10`.
fn Float32.clamp(low: Float32, high: Float32) Float32:
	return clamped(self, low, high)

// Returns the lesser of this value and `other`, or this value when they compare
// equal. Example: `(3).min(2)` is `2`.
fn String.min(other: String) String:
	return lesser(self, other).clone()

// Returns the greater of this value and `other`, or this value when they compare
// equal. Example: `(3).max(2)` is `3`.
fn String.max(other: String) String:
	return greater(self, other).clone()

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault. Example: `(15).clamp(0, 10)` is `10`.
fn String.clamp(low: String, high: String) String:
	return clamped(self, low, high).clone()
