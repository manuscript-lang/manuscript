def f(var rows: List[List[Int]]) -> Int:
    if var head = rows.first():
        head.append(1)
    rows.append([2])
    return rows.length()
