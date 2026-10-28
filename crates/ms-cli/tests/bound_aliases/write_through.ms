import stdout from "@std/io.ms"

type Lists:
    left: List[Int]
    right: List[Int]

type Counter:
    count: Int

impl Counter:
    var fn bump(amount: Int = 1) Unit:
        self.count += amount

    var fn around(action: fn() Unit) Unit:
        self.count += 1
        action()
        self.count += 1

    var fn label() String:
        self.count += 1
        return "count-{self.count}"

type Counters:
    left: Counter
    right: Counter

fn next(var calls: Int) Int:
    let old = calls
    calls += 1
    return old

fn key(var calls: Int) String:
    calls += 1
    return "key-{calls}"

export fn main() Int:
    var calls = 0
    var rows = [[1], [2]]
    var first = rows[next(var calls)]
    let append = first.append
    append(9)
    append(10)

    let _ = stdout().write("{calls} {rows}\n")
    var lists = Lists(left: [1], right: [2])
    var left = lists.left
    var right = lists.right
    let add_left = left.append
    let add_right = right.append
    add_right(4)
    add_left(3)

    let _ = stdout().write("{lists}\n")
    var counts = [Counter(count: 5)]
    var count = counts[0]
    let bump = count.bump
    bump()
    bump(3)

    let _ = stdout().write("{counts}\n")
    var pair = Counters(left: Counter(count: 1), right: Counter(count: 2))
    var first_count = pair.left
    var second_count = pair.right
    let around = first_count.around
    around(fn: second_count.count += 10)

    let _ = stdout().write("{pair}\n")
    var entries = Map[String, List[Int]]()
    entries.add("key-1", [7])
    calls = 0

    if var value = entries.get(key(var calls)):
        let add = value.append
        add(8)
        add(9)

    let _ = stdout().write("{calls} {entries}\n")
    var texts = [["first", "second"]]
    var text = texts[0]
    let pop = text.pop
    let popped = pop()
    let _ = stdout().write("{popped} {texts}\n")
    var final_count = counts[0]
    let label = final_count.label
    let labeled = label()
    let _ = stdout().write("{labeled} {counts}\n")
    return 0
