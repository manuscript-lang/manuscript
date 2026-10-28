import {keep, measure} from "@std/bench.ms"
import {Queue, PriorityQueue} from "@std/queue.ms"
import Deque from "@std/deque.ms"
import BitSet from "@std/bitset.ms"
import SortedMap from "@std/sorted.ms"

# Queue, PriorityQueue, Deque, BitSet and SortedMap at two sizes each, so ns/op staying flat shows the complexity class.
bench "queue.enqueue_dequeue_100000":
    fn work() Result[Unit, Error]:
        var queue = Queue[Int]()
        for i in 0..100000:
            queue.enqueue(i)

        var total = 0
        for i in 0..100000:
            total += queue.dequeue().get(0)
        return keep(total)

    try measure(100000 * 2, work)

bench "priority_queue.enqueue_dequeue_100000":
    fn work() Result[Unit, Error]:
        var queue = PriorityQueue[Int]()
        for i in 0..100000:
            queue.enqueue((i * 7919) % 100003)

        var total = 0
        for i in 0..100000:
            total += queue.dequeue().get(0)
        return keep(total)

    try measure(100000 * 2, work)

bench "deque.push_pop_both_ends_100000":
    fn work() Result[Unit, Error]:
        var deque = Deque[Int]()

        for i in 0..100000:
            deque.push_back(i)
            deque.push_front(i)

        var total = 0
        for i in 0..100000:
            total += deque.pop_front().get(0) + deque.pop_back().get(0)
        return keep(total)

    try measure(100000 * 4, work)

bench "bitset.add_contains_100000":
    fn work() Result[Unit, Error]:
        var set = BitSet()
        for i in 0..100000:
            set.add((i * 7919) % 1000003)

        var hits = 0
        for i in 0..100000:
            if set.contains(i):
                hits += 1
        return keep(hits + set.length())

    try measure(100000 * 2, work)

bench "sorted_map.add_contains_100000":
    fn work() Result[Unit, Error]:
        var map = SortedMap[Int, Int]()
        var x = 1

        for i in 0..100000:
            x = (x * 1103515245 + 12345) % 2147483648
            map.add(x, i)

        var hits = 0

        for i in 0..100000:
            x = (x * 1103515245 + 12345) % 2147483648
            if map.contains(x):
                hits += 1

        return keep(hits + map.length())

    try measure(100000 * 2, work)

bench "list.insert_remove_middle_100000":
    fn work() Result[Unit, Error]:
        var list = 0..100000

        for i in 0..1000:
            list.insert(100000 / 2, i)
            list.remove(100000 / 2)

        return keep(list.length())

    try measure(2000, work)

bench "queue.enqueue_dequeue_400000":
    fn work() Result[Unit, Error]:
        var queue = Queue[Int]()
        for i in 0..400000:
            queue.enqueue(i)

        var total = 0
        for i in 0..400000:
            total += queue.dequeue().get(0)
        return keep(total)

    try measure(400000 * 2, work)

bench "priority_queue.enqueue_dequeue_400000":
    fn work() Result[Unit, Error]:
        var queue = PriorityQueue[Int]()
        for i in 0..400000:
            queue.enqueue((i * 7919) % 100003)

        var total = 0
        for i in 0..400000:
            total += queue.dequeue().get(0)
        return keep(total)

    try measure(400000 * 2, work)

bench "deque.push_pop_both_ends_400000":
    fn work() Result[Unit, Error]:
        var deque = Deque[Int]()

        for i in 0..400000:
            deque.push_back(i)
            deque.push_front(i)

        var total = 0
        for i in 0..400000:
            total += deque.pop_front().get(0) + deque.pop_back().get(0)
        return keep(total)

    try measure(400000 * 4, work)

bench "bitset.add_contains_400000":
    fn work() Result[Unit, Error]:
        var set = BitSet()
        for i in 0..400000:
            set.add((i * 7919) % 1000003)

        var hits = 0
        for i in 0..400000:
            if set.contains(i):
                hits += 1
        return keep(hits + set.length())

    try measure(400000 * 2, work)

bench "sorted_map.add_contains_400000":
    fn work() Result[Unit, Error]:
        var map = SortedMap[Int, Int]()
        var x = 1

        for i in 0..400000:
            x = (x * 1103515245 + 12345) % 2147483648
            map.add(x, i)

        var hits = 0

        for i in 0..400000:
            x = (x * 1103515245 + 12345) % 2147483648
            if map.contains(x):
                hits += 1

        return keep(hits + map.length())

    try measure(400000 * 2, work)

bench "list.insert_remove_middle_400000":
    fn work() Result[Unit, Error]:
        var list = 0..400000

        for i in 0..1000:
            list.insert(400000 / 2, i)
            list.remove(400000 / 2)

        return keep(list.length())

    try measure(2000, work)
