# List operations written in Manuscript. Each interface gathers the operations that need a bound on the element type;
# a List[T] has them only when T meets the bound. They apply wherever List is used, without an import.
interface ListIntSum:
    def sum() -> Int

impl ListIntSum for List[Int]:
    # Adds the elements left to right with `+`, so integer overflow faults; an empty list sums to 0.
    # Example: `[1, 2, 3].sum()` is `6`.
    def sum() -> Int:
        var total: Int = 0
        for x in self:
            total += x
        return total

interface ListFloatSum:
    def sum() -> Float

impl ListFloatSum for List[Float]:
    # Adds the elements left to right with `+`, so integer overflow faults; an empty list sums to 0.
    # Example: `[1, 2, 3].sum()` is `6`.
    def sum() -> Float:
        var total: Float = 0.0
        for x in self:
            total += x
        return total

interface ListInt8Sum:
    def sum() -> Int8

impl ListInt8Sum for List[Int8]:
    # Adds the elements left to right with `+`, so integer overflow faults; an empty list sums to 0.
    # Example: `[1, 2, 3].sum()` is `6`.
    def sum() -> Int8:
        var total: Int8 = 0
        for x in self:
            total += x
        return total

interface ListInt16Sum:
    def sum() -> Int16

impl ListInt16Sum for List[Int16]:
    # Adds the elements left to right with `+`, so integer overflow faults; an empty list sums to 0.
    # Example: `[1, 2, 3].sum()` is `6`.
    def sum() -> Int16:
        var total: Int16 = 0
        for x in self:
            total += x
        return total

interface ListInt32Sum:
    def sum() -> Int32

impl ListInt32Sum for List[Int32]:
    # Adds the elements left to right with `+`, so integer overflow faults; an empty list sums to 0.
    # Example: `[1, 2, 3].sum()` is `6`.
    def sum() -> Int32:
        var total: Int32 = 0
        for x in self:
            total += x
        return total

interface ListFloat32Sum:
    def sum() -> Float32

impl ListFloat32Sum for List[Float32]:
    # Adds the elements left to right with `+`, so integer overflow faults; an empty list sums to 0.
    # Example: `[1, 2, 3].sum()` is `6`.
    def sum() -> Float32:
        var total: Float32 = 0.0
        for x in self:
            total += x
        return total

interface ListOrder[T: Comparable]:
    def sorted() -> List[T]
    var def sort() -> Unit

impl ListOrder[T] for List[T]:
    # Returns a new list in ascending natural order; the receiver is unchanged. The sort is stable: equal elements keep their order.
    # Float orders NaN above every other value.
    # Example: `[3, 1, 2].sorted()` is `[1, 2, 3]`.
    def sorted() -> List[T]:
        return self.sorted(lambda a, b: a.compare(b))

    # Sorts the list in place, stably, in the same order as `sorted()`.
    # Example: `var xs = [3, 1, 2]` then `xs.sort()` leaves `[1, 2, 3]`.
    var def sort() -> Unit:
        self.sort(lambda a, b: a.compare(b))

interface ListExtremes[T: Comparable & Clonable]:
    def min() -> Optional[T]
    def max() -> Optional[T]

impl ListExtremes[T] for List[T]:
    # Returns a copy of the least element, or none for an empty list; the first of equal elements wins.
    # Example: `[3, 1, 2].min()` is `some(1)`; `List[Int]().min()` is `none`.
    def min() -> Optional[T]:
        if self.length() == 0:
            return none

        var at = 0
        for i in 1..self.length():
            if self [i].compare(self [at]) < 0:
                at = i
        return some(self [at].clone())

    # Returns a copy of the greatest element, or none for an empty list; the first of equal elements wins.
    # Example: `[3, 1, 2].max()` is `some(3)`.
    def max() -> Optional[T]:
        if self.length() == 0:
            return none

        var at = 0
        for i in 1..self.length():
            if self [i].compare(self [at]) > 0:
                at = i
        return some(self [at].clone())
