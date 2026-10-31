import Deque from "@std/deque.ms"
import Queue, PriorityQueue from "@std/queue.ms"
import stdout from "@std/io.ms"
import arguments from "@std/process.ms"
import clock from "@std/time.ms"
import keep from "@std/bench.ms"

export fn main() Int:
    let args = arguments()
    let operation = args[0]
    let size = args[1].parse_int().get()
    let shape = args[2]
    let repeats = args[3].parse_int().get()
    var values: List[Int] = []
    var random = 1

    for i in 0..size:
        random = (random * 1103515245 + 12345) % 2147483648

        let value = if shape == "ascending": i else: (
            if shape == "descending": size - i else: (
                if shape == "duplicate": i % 7 else: random % 100003
            )
        )

        values.append(value)

    var checksum = 0
    var priority = PriorityQueue[Int]()
    var queue = Queue[Int]()
    var deque = Deque[Int]()
    let started = clock().now()

    for unused in 0..repeats:
        if operation == "priority":
            for value in values:
                priority.enqueue(value)
            for i in 0..size:
                checksum += (priority.dequeue().get() + 1) * (i + 1)
        else if operation == "queue":
            for value in values:
                queue.enqueue(value)
            for i in 0..size:
                checksum += (queue.dequeue().get() + 1) * (i + 1)
        else:
            for i in 0..size:
                if i % 2 == 0:
                    deque.push_front(values[i])
                else:
                    deque.push_back(values[i])

            for i in 0..size:
                checksum += (deque.pop_front().get() + 1) * (i + 1)

        keep(checksum).get()

    let elapsed = clock().now().difference(started).to_nanoseconds()
    stdout().write("{elapsed} {checksum}\n").get()
    return 0
