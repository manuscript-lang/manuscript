// A generic receiver with ordinary, bounded and specialized operations.
export type Box[T]:
    value: T

// Reports whether an argument was supplied.
fn Box[T].accepts(flag: Bool = true) Bool:
    return flag

interface OrderedBox[T: Comparable]:
    fn precedes(other: T) Bool

// Compares the stored value using its element's declared order.
fn Box[T: Comparable].precedes(other: T) Bool:
    return self.value.compare(other) < 0

export interface IntBoxSourceMethods:
    fn number() Int

// Returns the stored integer.
fn Box[Int].number() Int:
    return self.value
