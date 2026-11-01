import panic from "@std/core.ms"

# Source-written ordering methods for the built-in scalars and String: `a.min(b)`, `a.max(b)` and `a.clamp(low, high)`,
# defined once over `compare` so every numeric width and String agree. The methods apply to every program.
fn lesser[T: Comparable](left: T, right: T) T:
    if right.compare(left) < 0:
        return right

    return left

fn greater[T: Comparable](left: T, right: T) T:
    if right.compare(left) > 0:
        return right

    return left

fn clamped[T: Comparable](value: T, low: T, high: T) T:
    if low.compare(high) > 0:
        panic("clamp: low must not be greater than high")
    if value.compare(low) < 0:
        return low
    if value.compare(high) > 0:
        return high

    return value

interface Ordered:
    fn min(other: Self) Self
    fn max(other: Self) Self
    fn clamp(low: Self, high: Self) Self

impl Ordered for Int:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: Int) Int:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal.
    # Example: `(3).max(2)` is `3`.
    fn max(other: Int) Int:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: Int, high: Int) Int:
        return clamped(self, low, high)

impl Ordered for Int8:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: Int8) Int8:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal.
    # Example: `(3).max(2)` is `3`.
    fn max(other: Int8) Int8:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: Int8, high: Int8) Int8:
        return clamped(self, low, high)

impl Ordered for Int16:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: Int16) Int16:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal.
    # Example: `(3).max(2)` is `3`.
    fn max(other: Int16) Int16:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: Int16, high: Int16) Int16:
        return clamped(self, low, high)

impl Ordered for Int32:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: Int32) Int32:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal.
    # Example: `(3).max(2)` is `3`.
    fn max(other: Int32) Int32:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: Int32, high: Int32) Int32:
        return clamped(self, low, high)

impl Ordered for UInt8:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: UInt8) UInt8:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal.
    # Example: `(3).max(2)` is `3`.
    fn max(other: UInt8) UInt8:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: UInt8, high: UInt8) UInt8:
        return clamped(self, low, high)

impl Ordered for UInt16:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: UInt16) UInt16:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal.
    # Example: `(3).max(2)` is `3`.
    fn max(other: UInt16) UInt16:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: UInt16, high: UInt16) UInt16:
        return clamped(self, low, high)

impl Ordered for UInt32:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: UInt32) UInt32:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal.
    # Example: `(3).max(2)` is `3`.
    fn max(other: UInt32) UInt32:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: UInt32, high: UInt32) UInt32:
        return clamped(self, low, high)

impl Ordered for UInt64:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: UInt64) UInt64:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal.
    # Example: `(3).max(2)` is `3`.
    fn max(other: UInt64) UInt64:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: UInt64, high: UInt64) UInt64:
        return clamped(self, low, high)

impl Ordered for Float:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: Float) Float:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal.
    # Example: `(3).max(2)` is `3`.
    fn max(other: Float) Float:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: Float, high: Float) Float:
        return clamped(self, low, high)

impl Ordered for Float32:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: Float32) Float32:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal.
    # Example: `(3).max(2)` is `3`.
    fn max(other: Float32) Float32:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: Float32, high: Float32) Float32:
        return clamped(self, low, high)

impl Ordered for String:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: String) String:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal.
    # Example: `(3).max(2)` is `3`.
    fn max(other: String) String:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: String, high: String) String:
        return clamped(self, low, high)
