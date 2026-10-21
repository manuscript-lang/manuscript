import range from "@std/collections.ms"
import {bench} from "./harness.ms"
import {Queue, PriorityQueue} from "@std/queues.ms"
import {Deque} from "@std/deque.ms"
import {BitSet} from "@std/bitset.ms"
import {SortedMap} from "@std/sorted.ms"

fn ascending(left: Int, right: Int) Int:
    if left < right:
        return -1
    if left > right:
        return 1

    return 0

# Queue, PriorityQueue, Deque, BitSet and SortedMap at two sizes each, so ns/op staying flat shows the complexity class.
export fn bench_structures() Unit:
    for n in [100000, 400000]:
        bench(
            "queue.enqueue_dequeue_{n}",
            n * 2,
            fn() Int:
                let queue = Queue[Int]()
                for i in range(0, n):
                    queue.enqueue(i)
                var total = 0
                for i in range(0, n):
                    total += queue.dequeue().get(0)
                return total
        )
        bench(
            "priority_queue.enqueue_dequeue_{n}",
            n * 2,
            fn() Int:
                let queue = PriorityQueue[Int](ascending)
                for i in range(0, n):
                    queue.enqueue((i * 7919) % 100003)
                var total = 0
                for i in range(0, n):
                    total += queue.dequeue().get(0)
                return total
        )
        bench(
            "deque.push_pop_both_ends_{n}",
            n * 4,
            fn() Int:
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
            "bitset.add_contains_{n}",
            n * 2,
            fn() Int:
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
            "sorted_map.add_contains_{n}",
            n * 2,
            fn() Int:
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
            "list.insert_remove_middle_{n}",
            2000,
            fn() Int:
                var list = range(0, n)

                for i in range(0, 1000):
                    list.insert(n / 2, i)
                    list.remove(n / 2)

                return list.length()
        )
