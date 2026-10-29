import expect_equal from "@std/test.ms"

type Bag:
    items: List[Int]

interface Picker[T]:
    fn pick[K: Comparable](key: fn(T) K) Optional[T]
    fn mapped[U](transform: fn(T) U) List[U]

impl Picker[Int] for Bag:
    fn pick[K: Comparable](key: fn(Int) K) Optional[Int]:
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

    fn mapped[U](transform: fn(Int) U) List[U]:
        var out: List[U] = []
        for x in self.items:
            out.append(transform(x))
        return out

impl Bag:
    fn paired[U: Clonable](other: U) List[U]:
        var out: List[U] = []
        for item in self.items:
            out.append(other.clone())
        return out

fn pick_with[B: Picker[Int]](bag: B) Optional[Int]:
    return bag.pick(fn(x: Int) Int: 0 - x)

test "an interface operation takes type parameters of its own":
    let bag = Bag(items: [3, 1, 2])
    bag.pick(fn(x: Int) Int: x) | try expect_equal(some(3))
    bag.pick(fn(x: Int) String: "\{x\}") | try expect_equal(some(3))
    bag.mapped(fn(x: Int) String: "n") | try expect_equal(["n", "n", "n"])

test "a bounded type parameter calls a generic operation":
    pick_with(Bag(items: [3, 1, 2])) | try expect_equal(some(1))

test "an inherent method takes type parameters of its own":
    Bag(items: [1, 2]).paired("a") | try expect_equal(["a", "a"])
    Bag(items: [1, 2]).paired(true) | try expect_equal([true, true])

test "List max_by and min_by are source methods":
    let words = ["bb", "a", "ccc", "dd"]
    words.max_by(fn(w: String) Int: w.length()) | try expect_equal(some("ccc"))
    words.min_by(fn(w: String) Int: w.length()) | try expect_equal(some("a"))

export fn main() Int:
    return 0
