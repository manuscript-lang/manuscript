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

interface IntOrder:
    fn min(other: Int) Int
    fn max(other: Int) Int
    fn clamp(low: Int, high: Int) Int

impl IntOrder for Int:
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

interface Int8Order:
    fn min(other: Int8) Int8
    fn max(other: Int8) Int8
    fn clamp(low: Int8, high: Int8) Int8

impl Int8Order for Int8:
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

interface Int16Order:
    fn min(other: Int16) Int16
    fn max(other: Int16) Int16
    fn clamp(low: Int16, high: Int16) Int16

impl Int16Order for Int16:
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

interface Int32Order:
    fn min(other: Int32) Int32
    fn max(other: Int32) Int32
    fn clamp(low: Int32, high: Int32) Int32

impl Int32Order for Int32:
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

interface UInt8Order:
    fn min(other: UInt8) UInt8
    fn max(other: UInt8) UInt8
    fn clamp(low: UInt8, high: UInt8) UInt8

impl UInt8Order for UInt8:
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

interface UInt16Order:
    fn min(other: UInt16) UInt16
    fn max(other: UInt16) UInt16
    fn clamp(low: UInt16, high: UInt16) UInt16

impl UInt16Order for UInt16:
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

interface UInt32Order:
    fn min(other: UInt32) UInt32
    fn max(other: UInt32) UInt32
    fn clamp(low: UInt32, high: UInt32) UInt32

impl UInt32Order for UInt32:
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

interface UInt64Order:
    fn min(other: UInt64) UInt64
    fn max(other: UInt64) UInt64
    fn clamp(low: UInt64, high: UInt64) UInt64

impl UInt64Order for UInt64:
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

interface FloatOrder:
    fn min(other: Float) Float
    fn max(other: Float) Float
    fn clamp(low: Float, high: Float) Float

impl FloatOrder for Float:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: Float) Float:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal. Float orders NaN above every other value, so a NaN operand makes `max` NaN.
    # Example: `(3).max(2)` is `3`.
    fn max(other: Float) Float:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: Float, high: Float) Float:
        return clamped(self, low, high)

interface Float32Order:
    fn min(other: Float32) Float32
    fn max(other: Float32) Float32
    fn clamp(low: Float32, high: Float32) Float32

impl Float32Order for Float32:
    # Returns the lesser of this value and `other`, or this value when they compare equal.
    # Example: `(3).min(2)` is `2`.
    fn min(other: Float32) Float32:
        return lesser(self, other)

    # Returns the greater of this value and `other`, or this value when they compare equal. Float orders NaN above every other value, so a NaN operand makes `max` NaN.
    # Example: `(3).max(2)` is `3`.
    fn max(other: Float32) Float32:
        return greater(self, other)

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    # Example: `(15).clamp(0, 10)` is `10`.
    fn clamp(low: Float32, high: Float32) Float32:
        return clamped(self, low, high)

interface StringOrder:
    fn min(other: String) String
    fn max(other: String) String
    fn clamp(low: String, high: String) String

impl StringOrder for String:
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
