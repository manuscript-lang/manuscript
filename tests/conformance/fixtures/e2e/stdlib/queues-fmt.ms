# conform: tags=control-flow,formatter,modules,optional,parser,stdlib-queues,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/queues.ms
import expect_equal, expect_false from "@std/test.ms"
import PriorityQueue, Queue from "@std/queue.ms"

test "FIFO capacity empty reads draining and reuse":
    var queue = Queue[Int](2)
    try expect_false(not queue.is_empty() or not queue.peek().is_none())
    try expect_false((not queue.enqueue(1) or not queue.enqueue(2) or queue.enqueue(3)))
    try expect_false(queue.peek() != 1 or queue.length() != 2)
    try expect_false(queue.dequeue() != 1 or queue.dequeue() != 2)
    try expect_false(not queue.dequeue().is_none() or not queue.enqueue(4))

test "priority queue orders values and honors capacity":
    var queue = PriorityQueue[Int](3)
    queue.enqueue(3)
    queue.enqueue(1)
    queue.enqueue(2)
    try expect_false(queue.enqueue(0))
    try expect_equal(queue.peek(), 1)
    for expected in [1, 2, 3]:
        try expect_equal(queue.dequeue(), expected)
    try expect_false(not queue.is_empty())

test "priority queue sorts many values and copies are independent":
    var queue = PriorityQueue[Int]()
    for index in 0..200:
        queue.enqueue((index * 37) % 101)

    var copy = queue.clone()
    try expect_equal(copy.dequeue(), 0)
    try expect_equal(queue.length(), 200)

    var previous = -1

    while not queue.is_empty():
        let next = queue.dequeue().get()
        try expect_false(next < previous)
        previous = next

    try expect_equal(copy.length(), 199)
