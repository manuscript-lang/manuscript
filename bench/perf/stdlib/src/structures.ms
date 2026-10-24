from "@std/collections.ms" import range
from "./harness.ms" import bench
from "@std/queue.ms" import Queue, PriorityQueue
from "@std/deque.ms" import Deque
from "@std/bitset.ms" import BitSet
from "@std/sorted.ms" import SortedMap

def ascending(left: Int, right: Int) -> Int:
    if left < right:
        return -1
    if left > right:
        return 1

    return 0

# Queue, PriorityQueue, Deque, BitSet and SortedMap at two sizes each, so ns/op staying flat shows the complexity class.
export def bench_structures() -> Unit:
    for n in [100000, 400000]:
        bench(
            f"queue.enqueue_dequeue_{n}",
            n * 2,
            lambda () -> Int:
                var queue = Queue[Int]()
                for i in range(0, n):
                    queue.enqueue(i)

                var total = 0
                for i in range(0, n):
                    total += queue.dequeue().get(0)
                return total
        )

        bench(
            f"priority_queue.enqueue_dequeue_{n}",
            n * 2,
            lambda () -> Int:
                var queue = PriorityQueue[Int](ascending)
                for i in range(0, n):
                    queue.enqueue((i * 7919) % 100003)

                var total = 0
                for i in range(0, n):
                    total += queue.dequeue().get(0)
                return total
        )

        bench(
            f"deque.push_pop_both_ends_{n}",
            n * 4,
            lambda () -> Int:
                var deque = Deque[Int]()

                for i in range(0, n):
                    deque.push_back(i)
                    deque.push_front(i)

                var total = 0
                for i in range(0, n):
                    total += deque.pop_front().get(0) + deque.pop_back().get(0)
                return total
        )

        bench(
            f"bitset.add_contains_{n}",
            n * 2,
            lambda () -> Int:
                var set = BitSet()
                for i in range(0, n):
                    set.add((i * 7919) % 1000003)

                var hits = 0
                for i in range(0, n):
                    if set.contains(i):
                        hits += 1
                return hits + set.length()
        )

        bench(
            f"sorted_map.add_contains_{n}",
            n * 2,
            lambda () -> Int:
                var map = SortedMap[Int, Int]()
                var x = 1

                for i in range(0, n):
                    x = (x * 1103515245 + 12345) % 2147483648
                    map.add(x, i)

                var hits = 0

                for i in range(0, n):
                    x = (x * 1103515245 + 12345) % 2147483648
                    if map.contains(x):
                        hits += 1

                return hits + map.length()
        )

        bench(
            f"list.insert_remove_middle_{n}",
            2000,
            lambda () -> Int:
                var list = range(0, n)

                for i in range(0, 1000):
                    list.insert(n / 2, i)
                    list.remove(n / 2)

                return list.length()
        )
