# A generic receiver with ordinary, bounded and specialized operations.
export type Box[T]:
    value: T

impl Box[T]:
    # Reports whether an argument was supplied.
    fn accepts(flag: Bool = true) Bool:
        return flag

interface OrderedBox[T: Comparable]:
    fn precedes(other: T) Bool

impl OrderedBox[T] for Box[T]:
    # Compares the stored value using its element's declared order.
    fn precedes(other: T) Bool:
        return self.value.compare(other) < 0

interface IntBox:
    fn number() Int

impl IntBox for Box[Int]:
    # Returns the stored integer.
    fn number() Int:
        return self.value
