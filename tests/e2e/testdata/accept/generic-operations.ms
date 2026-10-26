from "@std/testing.ms" import expect_equal

type Bag:
    items: List[Int]

interface Picker[T]:
    def pick[K: Comparable](key: Callable[[T], K]) -> Optional[T]
    def mapped[U](transform: Callable[[T], U]) -> List[U]

impl Picker[Int] for Bag:
    def pick[K: Comparable](key: Callable[[Int], K]) -> Optional[Int]:
        if self.items.length() == 0:
            return none

        var at = 0
        var best = key(self.items[0])

        for i in 1..self.items.length():
            let k = key(self.items[i])

            if k.compare(best) > 0:
                at = i
                best = k

        return some(self.items[at])

    def mapped[U](transform: Callable[[Int], U]) -> List[U]:
        var out: List[U] = []
        for x in self.items:
            out.append(transform(x))
        return out

impl Bag:
    def paired[U: Clonable](other: U) -> List[U]:
        var out: List[U] = []
        for item in self.items:
            out.append(other.clone())
        return out

def pick_with[B: Picker[Int]](bag: B) -> Optional[Int]:
    return bag.pick(lambda (x: Int) -> Int: 0 - x)

test "an interface operation takes type parameters of its own":
    let bag = Bag(items: [3, 1, 2])
    bag.pick(lambda (x: Int) -> Int: x) | try expect_equal(some(3))
    bag.pick(lambda (x: Int) -> String: "{x}") | try expect_equal(some(3))
    bag.mapped(lambda (x: Int) -> String: "n") | try expect_equal(["n", "n", "n"])

test "a bounded type parameter calls a generic operation":
    pick_with(Bag(items: [3, 1, 2])) | try expect_equal(some(1))

test "an inherent method takes type parameters of its own":
    Bag(items: [1, 2]).paired("a") | try expect_equal(["a", "a"])
    Bag(items: [1, 2]).paired(True) | try expect_equal([True, True])

test "List max_by and min_by are source methods":
    let words = ["bb", "a", "ccc", "dd"]
    words.max_by(lambda (w: String) -> Int: w.length()) | try expect_equal(some("ccc"))
    words.min_by(lambda (w: String) -> Int: w.length()) | try expect_equal(some("a"))

export def main() -> Int:
    return 0
