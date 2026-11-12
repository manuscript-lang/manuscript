import panic from "@std/core.ms"

// Source-written ordering methods for the built-in scalars and String: `a.min(b)`,
// `a.max(b)` and `a.clamp(low, high)`, defined once over `compare` so every numeric
// width and String agree. The methods apply to every program. Each is written once
// on the `Ordered` set and exists on every member.
type Ordered = Int | Int8 | Int16 | Int32 | UInt8 | UInt16 | UInt32 | UInt64 | Float | Float32 | String

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

// Returns the lesser of this value and `other`, or this value when they compare
// equal. Example: `(3).min(2)` is `2`.
fn Ordered.min(other: Self) Self:
	return lesser(self, other).clone()

// Returns the greater of this value and `other`, or this value when they compare
// equal. Example: `(3).max(2)` is `3`.
fn Ordered.max(other: Self) Self:
	return greater(self, other).clone()

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault. Example: `(15).clamp(0, 10)` is `10`.
fn Ordered.clamp(low: Self, high: Self) Self:
	return clamped(self, low, high).clone()
