from "@std/io.ms" import stdout
from "@std/time.ms" import clock, Instant
from "@std/string.ms" import StringBuilder
from "@std/bytes.ms" import BytesBuilder
from "@std/queue.ms" import PriorityQueue
from "@std/sorted.ms" import SortedMap
from "@std/collections.ms" import range

type Rec:
    key: Int
    id: Int

def say(text: String) -> Unit:
    let _ignored = stdout().write(text)

def since(started: Instant) -> Int:
    return clock().now().difference(started).to_nanoseconds()

def report(name: String, ops: Int, started: Instant) -> Unit:
    say(f"{name} {ops} {since(started)}\n")

def next_rand(x: Int) -> Int:
    return (x * 1103515245 + 12345) % 2147483648

def bench_list_append(n: Int) -> Int:
    let t = clock().now()
    var l: List[Int] = []
    for i in range(0, n):
        l.append(i)
    report("list_append", n, t)
    return l.length()

def bench_list_get(n: Int) -> Int:
    var l: List[Int] = []
    for i in range(0, n):
        l.append(i)

    let t = clock().now()
    var x = 1
    var sum = 0

    for i in range(0, n):
        x = next_rand(x)
        sum += l[x % n]

    report("list_get_random", n, t)
    return sum

def bench_list_sort(n: Int) -> Int:
    var l: List[Int] = []
    var x = 1

    for i in range(0, n):
        x = next_rand(x)
        l.append(x)

    let t = clock().now()
    let s = l.sorted()
    report("list_sort_int", n, t)
    return s[0]

def bench_list_sort_cmp(n: Int) -> Int:
    var l: List[Rec] = []
    var x = 1

    for i in range(0, n):
        x = next_rand(x)
        l.append(Rec(key: x % 100000, id: i))

    let t = clock().now()
    let s = l.sorted(compare: lambda (a: Rec, b: Rec) -> Int: a.key - b.key)
    report("list_sort_cmp", n, t)
    return s[0].id

def bench_map_int(n: Int) -> Int:
    let t = clock().now()
    var m = Map[Int, Int]()
    var x = 1

    for i in range(0, n):
        x = next_rand(x)
        m.add(x, i)

    var hits = 0
    x = 1

    for i in range(0, n):
        x = next_rand(x)
        hits += m.get_or(x, 0)

    report("map_int_put_get", n * 2, t)
    return hits

def bench_map_str(n: Int) -> Int:
    var keys: List[String] = []
    for i in range(0, n):
        keys.append(f"key{i}")

    let t = clock().now()
    var m = Map[String, Int]()
    for i in range(0, n):
        m.add(keys[i].clone(), i)

    var hits = 0
    for i in range(0, n):
        hits += m.get_or(keys[i], 0)
    report("map_str_put_get", n * 2, t)
    return hits

def bench_set(n: Int) -> Int:
    let t = clock().now()
    var s = Set[Int]()
    var x = 1

    for i in range(0, n):
        x = next_rand(x)
        s.add(x)

    var hits = 0
    x = 1

    for i in range(0, n):
        x = next_rand(x)
        if s.contains(x):
            hits += 1

    report("set_int_add_contains", n * 2, t)
    return hits

def bench_string(n: Int) -> Int:
    let t = clock().now()
    var sb = StringBuilder()

    for i in range(0, n):
        sb.append("word")
        sb.append(" ")

    let text = sb.build()
    let parts = text.split(" ")
    let joined = parts.join("-")
    let replaced = joined.replace("word", "w")
    report("string_build_split_join_replace", n, t)
    return replaced.byte_length() + parts.length()

def bench_bytes(n: Int) -> Int:
    let t = clock().now()
    var bb = BytesBuilder()
    for i in range(0, n):
        bb.append((i % 256).to_uint8().get(0))

    let b = bb.build()
    report("bytes_append", n, t)
    return b.length()

def bench_pq(n: Int) -> Int:
    let t = clock().now()
    var q = PriorityQueue[Int](compare: lambda (a: Int, b: Int) -> Int: a - b)
    var x = 1

    for i in range(0, n):
        x = next_rand(x)
        q.enqueue(x)

    var sum = 0
    for i in range(0, n):
        sum += q.dequeue().get(0)
    report("pq_int_enqueue_dequeue", n * 2, t)
    return sum

def bench_sorted_map(n: Int) -> Int:
    let t = clock().now()
    var m = SortedMap[Int, Int]()
    var x = 1

    for i in range(0, n):
        x = next_rand(x)
        m.add(x, i)

    var hits = 0
    x = 1

    for i in range(0, n):
        x = next_rand(x)
        if m.contains(x):
            hits += 1

    report("sorted_map_add_contains", n * 2, t)
    return hits

export def main() -> Int:
    var total = 0
    total += bench_list_append(1000000)
    total += bench_list_get(1000000)
    total += bench_list_sort(1000000)
    total += bench_list_sort_cmp(300000)
    total += bench_map_int(1000000)
    total += bench_map_str(200000)
    total += bench_set(1000000)
    total += bench_string(200000)
    total += bench_bytes(4000000)
    total += bench_pq(300000)
    total += bench_sorted_map(300000)
    if total == 0:
        return 1

    return 0
