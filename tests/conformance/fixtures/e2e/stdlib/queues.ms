# conform: tags=control-flow,modules,optional,stdlib-queues,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/queues.ms
import {expect_equal, expect_false} from "@std/testing.ms"
import {Queue, PriorityQueue} from "@std/collections.ms"

fn compare(left: Int, right: Int) Int: left - right

test "FIFO capacity empty reads draining and reuse":
    let queue = Queue[Int](2)
    try expect_false(not queue.is_empty() or not queue.peek().is_none())
    try expect_false((not queue.enqueue(1) or not queue.enqueue(2) or queue.enqueue(3)))
    try expect_false(queue.peek() != some(1) or queue.length() != 2)
    try expect_false(queue.dequeue() != some(1) or queue.dequeue() != some(2))
    try expect_false(not queue.dequeue().is_none() or not queue.enqueue(4))

test "priority queue orders values and honors capacity":
    let queue = PriorityQueue(compare, 3)
    queue.enqueue(3)
    queue.enqueue(1)
    queue.enqueue(2)
    try expect_false(queue.enqueue(0))
    try expect_equal(queue.peek(), some(1))
    for expected in [1, 2, 3]:
        try expect_equal(queue.dequeue(), some(expected))
    try expect_false(not queue.is_empty())
