from "@std/io.ms" import stdout

def next(var count: Int) -> Int:
    let result = count
    count += 1
    return result

def key(var count: Int) -> String:
    count += 1
    return f"key-{count}"

def early(var entries: Map[String, List[Int]], var count: Int) -> Unit:
    if var item = entries.get(key(var count)):
        item.append(7)
        return

export def main() -> Int:
    var count = 0
    var entries = Map[String, List[Int]]()
    entries.add("key-1", [1])
    entries.add("key-2", [2])
    if var item = entries.get(key(var count)):
        item.append(9)

    let _ = stdout().write(f"{count} {entries}\n")
    count = 2

    if var item = entries.get(key(var count)):
        item.append(99)
    else:
        let _ = stdout().write(f"missing {count}\n")

    count = 0
    early(var entries, var count)

    let _ = stdout().write(f"early {count} {entries}\n")
    count = 0
    for value in [4, 5, 6]:
        if var item = entries.get(key(var count)):
            item.append(value)

    let _ = stdout().write(f"loop {count} {entries}\n")
    var rows = [[[1]], [[2]]]
    count = 0
    if var item = rows[next(var count)].first():
        item.append(9)

    let _ = stdout().write(f"{count} {rows}\n")
    count = 0
    if var item = rows[next(var count)].last():
        item.append(10)

    let _ = stdout().write(f"{count} {rows}\n")
    var empty: List[List[List[Int]]] = [[], [[2]]]
    count = 0

    if var item = empty[next(var count)].first():
        item.append(99)
    else:
        let _ = stdout().write(f"empty {count} {empty}\n")

    return 0
