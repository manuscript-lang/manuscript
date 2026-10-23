# conform: tags=closures,control-flow,match,modules,optional,stdlib-queues,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/queues.ms
import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"
import Queue from "@std/queue.ms"

test "omitted capacity creates an unbounded queue":
    var queue = Queue[Int]()
    var inferred: Queue[Int] = Queue()

    for unused in [1, 2]:
        for value in [1, 2, 3, 4, 5]:
            (queue.enqueue(value)) | try expect_true
        queue.length() | try expect_equal(5)

        for value in [1, 2, 3, 4, 5]:
            let expected: Optional[Int] = some(value)
            queue.dequeue() | try expect_equal(expected)

        let missing: Optional[Int] = none
        (queue.is_empty() and queue.dequeue() == missing) | try expect_true

    (inferred.enqueue(1)) | try expect_true

test "a copy is an independent queue":
    var queue = Queue[Int](2)
    let missing: Optional[Int] = none
    (queue.is_empty() and queue.length() == 0) | try expect_true
    (queue.dequeue() == missing and queue.peek() == missing) | try expect_true
    (queue.enqueue(3) and queue.enqueue(value: 4)) | try expect_true
    queue.enqueue(5) | try expect_false
    var copy = queue.clone()
    let first: Optional[Int] = some(3)
    let second: Optional[Int] = some(4)
    (copy.dequeue() == first and copy.length() == 1) | try expect_true
    (queue.peek() == first and queue.length() == 2) | try expect_true
    (queue.dequeue() == first and queue.dequeue() == second) | try expect_true
    (queue.dequeue() == missing and queue.is_empty()) | try expect_true
    (copy.peek() == second and copy.enqueue(6)) | try expect_true
    (queue.enqueue(4)) | try expect_true
    queue.dequeue() | try expect_equal(second)

test "queue elements include ordinary functions":
    var queue = Queue[fn() Int](1)
    queue.enqueue(
        fn():
            return 7
    )

    match queue.dequeue():
        some(callback):
            try expect_equal(callback(), 7)
        none:
            return fail("callback missing")
