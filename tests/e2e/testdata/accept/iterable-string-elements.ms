import expect_equal from "@std/test.ms"
import Deque from "@std/deque.ms"
import Queue from "@std/queue.ms"

test "reading string elements while iterating does not change the container":
    var deque = Deque[String]()
    for i in 0..5:
        deque.push_back("item-{i}")

    var total = 0
    for item in deque:
        total += item.length()
    total | try expect_equal(30)
    deque.length() | try expect_equal(5)
    deque.at(4) | try expect_equal("item-4")

test "an element kept past the loop is an independent copy":
    var queue = Queue[String](none)
    for i in 0..3:
        queue.enqueue("q-{i}")

    var kept: List[String] = []
    for item in queue:
        kept.append(item.clone())
    queue.dequeue()
    queue.enqueue("later")
    kept | try expect_equal(["q-0", "q-1", "q-2"])
    queue.length() | try expect_equal(3)

test "iteration sees each element once after the ring buffer wraps":
    var deque = Deque[String]()
    for i in 0..4:
        deque.push_back("b{i}")
    deque.pop_front()
    deque.push_front("a")
    deque.push_back("z")

    var seen = ""
    for item in deque:
        seen = seen + item + ","
    seen | try expect_equal("a,b1,b2,b3,z,")
