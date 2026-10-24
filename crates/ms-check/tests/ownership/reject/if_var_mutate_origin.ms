def f(var rows: List[List[Int]]) -> Int:
    if var head = rows.first():
        rows.append([3])  # error: cannot change `rows`
        head.append(1)

    return rows.length()
