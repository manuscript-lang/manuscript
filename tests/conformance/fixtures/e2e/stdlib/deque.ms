# conform: tags=optional,stdlib-deque,stdlib-testing,testing,tier-stdlib
# conform: phase=test
from "@std/testing.ms" import expect_equal, expect_true
from "@std/deque.ms" import Deque
from "@std/collections.ms" import range

test "both ends push and pop":
    var d = Deque[Int]()
    try expect_true(d.is_empty())
    try expect_equal(d.pop_front(), none)
    try expect_equal(d.pop_back(), none)
    d.push_back(2)
    d.push_back(3)
    d.push_front(1)
    d.push_front(0)
    try expect_equal(d.to_list(), [0, 1, 2, 3])
    try expect_equal(d.front(), some(0))
    try expect_equal(d.back(), some(3))
    try expect_equal(d.pop_front(), some(0))
    try expect_equal(d.pop_back(), some(3))
    try expect_equal(d.length(), 2)

test "indexed reads follow the front":
    var d = Deque[String]()
    for name in ["b", "c", "d"]:
        d.push_back(name)
    d.push_front("a")
    try expect_equal(d.at(0), some("a"))
    try expect_equal(d.at(3), some("d"))
    try expect_equal(d.at(4), none)
    try expect_equal(d.at(-1), none)

test "wraps around and grows past the first buffer":
    var d = Deque[Int]()
    var expected: List[Int] = []

    for i in range(0, 100):
        d.push_back(i)
        d.push_front(-i)
        expected.append(i)
        expected.prepend(-i)

        if i % 3 == 0:
            try expect_equal(d.pop_front(), some(expected.get(0)))
            expected = expected.drop(1)
            try expect_equal(d.pop_back(), some(expected.pop().get()))

    try expect_equal(d.to_list(), expected)

test "a copy is independent and clear empties":
    var d = Deque[Int]()
    d.push_back(1)

    var e = d.clone()
    e.push_back(2)
    try expect_equal(d.to_list(), [1])
    try expect_equal(e.to_list(), [1, 2])
    e.clear()
    try expect_true(e.is_empty())
    e.push_front(7)
    try expect_equal(e.to_list(), [7])

test "optional elements keep none distinct from absent":
    var d = Deque[Optional[Int]]()
    d.push_back(none)
    try expect_equal(d.length(), 1)
    try expect_equal(d.pop_front(), some(none))
    try expect_equal(d.pop_front(), none)
