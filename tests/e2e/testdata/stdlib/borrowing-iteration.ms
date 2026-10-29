import {expect_equal, expect_true} from "@std/test.ms"
import {Deque, DequeIter} from "@std/deque.ms"
import {PriorityQueue, PriorityQueueIter, Queue, QueueIter} from "@std/queue.ms"

# `for item in container` over an `Iterable` container borrows each item: the lambdas below are
# never cloned.
test "deque iterates front to back by borrow":
    var d = Deque[Int]()
    d.push_back(2)
    d.push_back(3)
    d.push_front(1)

    var seen: List[Int] = []
    for item in d:
        seen.append(item)
    try expect_equal(seen, [1, 2, 3])
    try expect_equal(d.length(), 3)

test "queue iterates oldest first and skips consumed slots":
    var q = Queue[String]()
    q.enqueue("a")
    q.enqueue("b")
    q.enqueue("c")
    try expect_equal(q.dequeue(), some("a"))

    var seen: List[String] = []
    for item in q:
        seen.append(item.clone())
    try expect_equal(seen, ["b", "c"])

test "priority queue iterates every value and peek borrows":
    var q = PriorityQueue[Int]()
    q.enqueue(5)
    q.enqueue(1)
    q.enqueue(3)

    var total = 0
    for item in q:
        total += item
    try expect_equal(total, 9)
    try expect_equal(q.peek(), some(1))

test "break and continue work in a borrowing loop":
    var d = Deque[Int]()
    for i in 0..6:
        d.push_back(i)

    var seen: List[Int] = []

    for item in d:
        if item == 1:
            continue
        if item == 4:
            break

        seen.append(item)

    try expect_equal(seen, [0, 2, 3])

test "empty container and temporary iterable":
    var d = Deque[Int]()
    var count = 0
    for item in d:
        count += item + 1
    try expect_equal(count, 0)
    for item in Deque[Int]():
        count += 1
    try expect_equal(count, 0)

test "nested loops over one container":
    var d = Deque[Int]()
    d.push_back(1)
    d.push_back(2)

    var pairs = 0
    for a in d:
        for b in d:
            pairs += a * b
    try expect_equal(pairs, 9)

test "callbacks are called through the borrow":
    var d = Deque[fn(Int) Int]()
    d.push_back(fn(x: Int) Int: return x + 1)
    d.push_back(fn(x: Int) Int: return x * 10)

    var total = 0
    for f in d:
        total += f(2)
    try expect_equal(total, 23)

test "deque iterator keeps exhausted positions unchanged":
    let empty = Deque[Int]()
    for position in [-1, 0, 9223372036854775807]:
        var it = DequeIter(source: empty, position: position)
        for attempt in 0..3:
            try expect_true(it.next().is_none())
        try expect_equal(it.position, position)

    var d = Deque[Int]()
    d.push_back(7)
    var it = d.iter()
    try expect_equal(it.next(), some(7))
    for attempt in 0..3:
        try expect_true(it.next().is_none())
    try expect_equal(it.position, 1)

test "queue iterator keeps exhausted positions unchanged":
    let empty = Queue[Int]()
    for position in [-1, 0, 9223372036854775807]:
        var it = QueueIter(source: empty, position: position)
        for attempt in 0..3:
            try expect_true(it.next().is_none())
        try expect_equal(it.position, position)

    var q = Queue[Int]()
    q.enqueue(7)
    var it = q.iter()
    try expect_equal(it.next(), some(7))
    for attempt in 0..3:
        try expect_true(it.next().is_none())
    try expect_equal(it.position, 1)

test "priority queue iterator keeps exhausted positions unchanged":
    let empty = PriorityQueue[Int]()
    for position in [-1, 0, 9223372036854775807]:
        var it = PriorityQueueIter(source: empty, position: position)
        for attempt in 0..3:
            try expect_true(it.next().is_none())
        try expect_equal(it.position, position)

    var q = PriorityQueue[Int]()
    q.enqueue(7)
    var it = q.iter()
    try expect_equal(it.next(), some(7))
    for attempt in 0..3:
        try expect_true(it.next().is_none())
    try expect_equal(it.position, 1)
