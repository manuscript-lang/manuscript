from "@std/test.ms" import expect_equal, expect_false, expect_true
from "@std/queue.ms" import PriorityQueue, Queue
from "@std/collections.ms" import range

test "FIFO capacity empty reads draining and reuse":
    var queue = Queue[Int](2)
    try expect_false(not queue.is_empty() or not queue.peek().is_none())
    try expect_false((not queue.enqueue(1) or not queue.enqueue(2) or queue.enqueue(3)))
    try expect_false(queue.peek() != some(1) or queue.length() != 2)
    try expect_false(queue.dequeue() != some(1) or queue.dequeue() != some(2))
    try expect_false(not queue.dequeue().is_none() or not queue.enqueue(4))

test "priority queue orders values and honors capacity":
    var queue = PriorityQueue[Int](3)
    queue.enqueue(3)
    queue.enqueue(1)
    queue.enqueue(2)
    try expect_false(queue.enqueue(0))
    try expect_equal(queue.peek(), some(1))
    for expected in [1, 2, 3]:
        try expect_equal(queue.dequeue(), some(expected))
    try expect_false(not queue.is_empty())

test "priority queue sorts many values and copies are independent":
    var queue = PriorityQueue[Int]()
    for index in range(0, 200):
        queue.enqueue((index * 37) % 101)

    var copy = queue.clone()
    try expect_equal(copy.dequeue(), some(0))
    try expect_equal(queue.length(), 200)

    var previous = -1

    while not queue.is_empty():
        let next = queue.dequeue().get()
        try expect_false(next < previous)
        previous = next

    try expect_equal(copy.length(), 199)

test "ordered priority queue defaults to natural order and honors capacity":
    var queue = PriorityQueue[String](capacity: 2)
    try expect_true(queue.enqueue("b"))
    try expect_true(queue.enqueue("a"))
    try expect_false(queue.enqueue("c"))
    try expect_equal(queue.dequeue(), some("a"))
    try expect_equal(queue.dequeue(), some("b"))
    try expect_equal(queue.dequeue(), none)
