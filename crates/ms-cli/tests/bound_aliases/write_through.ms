import stdout from "@std/io/io.ms"

type Lists:
    left: List[Int]
    right: List[Int]

type Counter:
    count: Int

fn var Counter.bump(amount: Int = 1) Void:
    self.count += amount

fn var Counter.around(action: fn() Void) Void:
    self.count += 1
    action()
    self.count += 1

fn var Counter.label() String:
    self.count += 1
    return f"count-{self.count}"

type Counters:
    left: Counter
    right: Counter

fn next(var calls: Int) Int:
    old := calls
    calls += 1
    return old

fn key(var calls: Int) String:
    calls += 1
    return f"key-{calls}"

fn main() Void:
    var calls = 0
    var rows = [[1], [2]]
    var first = rows[next(calls)]
    append := first.append
    append(9)
    append(10)

    void stdout().write(f"{calls} {rows}\n")
    var lists = Lists(left: [1], right: [2])
    var left = lists.left
    var right = lists.right
    add_left := left.append
    add_right := right.append
    add_right(4)
    add_left(3)

    void stdout().write(f"{lists}\n")
    var counts = [Counter(count: 5)]
    var count = counts[0]
    bump := count.bump
    bump()
    bump(3)

    void stdout().write(f"{counts}\n")
    var pair = Counters(left: Counter(count: 1), right: Counter(count: 2))
    var first_count = pair.left
    var second_count = pair.right
    around := first_count.around
    around(fn: second_count.count += 10)

    void stdout().write(f"{pair}\n")
    var entries = Map[String, List[Int]]()
    entries.add("key-1", [7])
    calls = 0

    if var value = entries[key(calls)]?:
        add := value.append
        add(8)
        add(9)

    void stdout().write(f"{calls} {entries}\n")
    var texts = [["first", "second"]]
    var text = texts[0]
    pop := text.pop
    popped := pop()
    void stdout().write(f"{popped} {texts}\n")
    var final_count = counts[0]
    label := final_count.label
    labeled := label()
    void stdout().write(f"{labeled} {counts}\n")
