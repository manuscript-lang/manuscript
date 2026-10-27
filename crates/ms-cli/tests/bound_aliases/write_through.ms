from "@std/io.ms" import stdout

type Lists:
    left: List[Int]
    right: List[Int]

type Counter:
    count: Int

impl Counter:
    var def bump(amount: Int = 1) -> Unit:
        self.count += amount

    var def around(action: Callable[[], Unit]) -> Unit:
        self.count += 1
        action()
        self.count += 1

    var def label() -> String:
        self.count += 1
        return f"count-{self.count}"

type Counters:
    left: Counter
    right: Counter

def next(var calls: Int) -> Int:
    let old = calls
    calls += 1
    return old

def key(var calls: Int) -> String:
    calls += 1
    return f"key-{calls}"

export def main() -> Int:
    var calls = 0
    var rows = [[1], [2]]
    var first = rows[next(var calls)]
    let append = first.append
    append(9)
    append(10)

    let _ = stdout().write(f"{calls} {rows}\n")
    var lists = Lists(left: [1], right: [2])
    var left = lists.left
    var right = lists.right
    let add_left = left.append
    let add_right = right.append
    add_right(4)
    add_left(3)

    let _ = stdout().write(f"{lists}\n")
    var counts = [Counter(count: 5)]
    var count = counts[0]
    let bump = count.bump
    bump()
    bump(3)

    let _ = stdout().write(f"{counts}\n")
    var pair = Counters(left: Counter(count: 1), right: Counter(count: 2))
    var first_count = pair.left
    var second_count = pair.right
    let around = first_count.around
    around(lambda: second_count.count += 10)

    let _ = stdout().write(f"{pair}\n")
    var entries = Map[String, List[Int]]()
    entries.add("key-1", [7])
    calls = 0

    if var value = entries.get(key(var calls)):
        let add = value.append
        add(8)
        add(9)

    let _ = stdout().write(f"{calls} {entries}\n")
    var texts = [["first", "second"]]
    var text = texts[0]
    let pop = text.pop
    let popped = pop()
    let _ = stdout().write(f"{popped} {texts}\n")
    var final_count = counts[0]
    let label = final_count.label
    let labeled = label()
    let _ = stdout().write(f"{labeled} {counts}\n")
    return 0
