import stdout from "@std/io/io.ms"

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
    old := calls
    calls += 1
    return old

fn key(var calls: Int) String:
    calls += 1
    return "key-{calls}"

export fn main() Int:
    var calls = 0
    var rows = [[1], [2]]
    var first = rows[next(var calls)]
    append := first.append
    append(9)
    append(10)

    _ := stdout().write("{calls} {rows}\n")
    var lists = Lists(left: [1], right: [2])
    var left = lists.left
    var right = lists.right
    add_left := left.append
    add_right := right.append
    add_right(4)
    add_left(3)

    _ := stdout().write("{lists}\n")
    var counts = [Counter(count: 5)]
    var count = counts[0]
    bump := count.bump
    bump()
    bump(3)

    _ := stdout().write("{counts}\n")
    var pair = Counters(left: Counter(count: 1), right: Counter(count: 2))
    var first_count = pair.left
    var second_count = pair.right
    around := first_count.around
    around(fn: second_count.count += 10)

    _ := stdout().write("{pair}\n")
    var entries = Map[String, List[Int]]()
    entries.add("key-1", [7])
    calls = 0

    if var value = entries[key(var calls)]?:
        add := value.append
        add(8)
        add(9)

    _ := stdout().write("{calls} {entries}\n")
    var texts = [["first", "second"]]
    var text = texts[0]
    pop := text.pop
    popped := pop()
    _ := stdout().write("{popped} {texts}\n")
    var final_count = counts[0]
    label := final_count.label
    labeled := label()
    _ := stdout().write("{labeled} {counts}\n")
    return 0
