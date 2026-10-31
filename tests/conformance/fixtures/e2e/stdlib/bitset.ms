# conform: tags=stdlib-bitset,stdlib-testing,testing,tier-stdlib
# conform: phase=test
import expect_equal, expect_true, expect_false from "@std/test.ms"
import BitSet from "@std/bitset.ms"

fn of(members: List[Int]) BitSet:
    var set = BitSet()
    for member in members:
        set.add(member)
    return set

test "add remove contains across word boundaries":
    var set = of([0, 1, 63, 64, 65, 200])
    try expect_equal(set.values(), [0, 1, 63, 64, 65, 200])
    try expect_equal(set.length(), 6)
    try expect_true(set.contains(63))
    try expect_true(set.contains(64))
    try expect_false(set.contains(62))
    try expect_false(set.contains(100000))
    try expect_false(set.contains(-1))
    set.remove(64)
    set.remove(999)
    set.remove(-5)
    try expect_equal(set.values(), [0, 1, 63, 65, 200])
    set.add(63)
    try expect_equal(set.length(), 5)

test "next finds the following member":
    let set = of([5, 64, 130])
    try expect_equal(set.next(), 5)
    try expect_equal(set.next(5), 5)
    try expect_equal(set.next(6), 64)
    try expect_equal(set.next(65), 130)
    try expect_equal(set.next(131), none)
    try expect_equal(set.next(-3), 5)
    try expect_equal(BitSet().next(), none)

test "set algebra matches Set":
    let a = of([1, 5, 63, 64, 130])
    let b = of([5, 63, 200])
    try expect_equal(a.union(b).values(), [1, 5, 63, 64, 130, 200])
    try expect_equal(a.intersection(b).values(), [5, 63])
    try expect_equal(a.difference(b).values(), [1, 64, 130])
    try expect_equal(a.symmetric_difference(b).values(), [1, 64, 130, 200])
    try expect_true(of([5, 63]).is_subset_of(a))
    try expect_true(a.is_superset_of(of([1])))
    try expect_true(of([2]).is_disjoint_from(a))
    try expect_false(a.is_disjoint_from(b))
    try expect_true(BitSet().is_subset_of(a))

test "copies are independent and clear empties":
    var a = of([1, 2])
    var b = a.clone()
    b.add(3)
    try expect_equal(a.values(), [1, 2])
    b.clear()
    try expect_true(b.is_empty())
    try expect_equal(b.length(), 0)
